//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Device and Provenance construction.
// swiftlint:disable multiline_literal_brackets

#if canImport(HealthKit)

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import GroveHealthKit
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRConverter {
    static func applicationDevice(_ application: HealthKitFHIRApplication) -> Device {
        var device = Device()
        device.meta = Meta(profile: [GroveFHIRProfile.groveApplicationDevice])
        device.identifier = [Identifier(
            system: GroveFHIRCanonical.appleBundleIdentifier,
            value: application.bundleIdentifier.asFHIRStringPrimitive()
        )]
        device.deviceName = [DeviceDeviceName(
            name: application.name.asFHIRStringPrimitive(),
            type: FHIRPrimitive(.userFriendlyName)
        )]
        device.version = [DeviceVersion(
            type: CodeableConcept(coding: [Coding(
                code: "531975",
                display: "MDC_ID_PROD_SPEC_SW",
                system: mdc
            )]),
            value: application.version.asFHIRStringPrimitive()
        )]
        return device
    }

    static func recordingDevice(
        for healthKitDevice: HKDevice?,
        context: HealthKitFHIRConversionContext,
        sourceUUID: String
    ) throws -> IdentifiedDevice? {
        guard let healthKitDevice else {
            return nil
        }
        var device = Device()
        device.meta = Meta(profile: [GroveFHIRProfile.groveRecordingDevice])
        if let name = healthKitDevice.name?.nonEmpty {
            device.deviceName = [DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )]
        }
        device.manufacturer = healthKitDevice.manufacturer?.nonEmpty?.asFHIRStringPrimitive()
        device.modelNumber = healthKitDevice.model?.nonEmpty?.asFHIRStringPrimitive()
        var versions: [DeviceVersion] = []
        versions.appendVersion(healthKitDevice.hardwareVersion, code: "531974", display: "MDC_ID_PROD_SPEC_HW")
        versions.appendVersion(healthKitDevice.firmwareVersion, code: "531976", display: "MDC_ID_PROD_SPEC_FW")
        versions.appendVersion(healthKitDevice.softwareVersion, code: "531975", display: "MDC_ID_PROD_SPEC_SW")
        device.version = versions.isEmpty ? nil : versions

        let localIdentity: GroveFHIRBusinessIdentifier?
        if let system = context.recordingDeviceIdentifierSystem,
           let localIdentifier = healthKitDevice.localIdentifier?.nonEmpty {
            let identifier = try GroveFHIRBusinessIdentifier(system: system, value: localIdentifier)
            device.identifier = [identifier.fhirIdentifier]
            localIdentity = identifier
        } else {
            localIdentity = nil
        }
        if context.udiDisclosurePolicy == .authorizedUDI,
           let udi = healthKitDevice.udiDeviceIdentifier?.nonEmpty {
            device.udiCarrier = [DeviceUdiCarrier(deviceIdentifier: udi.asFHIRStringPrimitive())]
        }
        // Published precedence: an authorized local identifier, then the deduplicating digest a
        // device-identity scope unlocks, then the per-sample identity that asserts no shared
        // device at all.
        let identity: GroveFHIRBusinessIdentifier
        if let localIdentity {
            identity = localIdentity
        } else if let value = deduplicatingIdentity(for: healthKitDevice, context: context) {
            identity = try GroveFHIRBusinessIdentifier(
                system: context.graphIdentifierSystem,
                value: value
            )
        } else {
            identity = try derivedIdentity(
                context: context,
                sourceUUID: sourceUUID,
                role: "recording-device"
            )
        }
        return IdentifiedDevice(resource: device, identity: identity)
    }

    /// The published recording-device digest, or `nil` when the platform states too little to
    /// identify a recorder.
    ///
    /// The subject is taken from its literal reference. An identifier-only subject has no pinned
    /// lexical form, so it yields no shared device identity rather than an unstable one.
    private static func deduplicatingIdentity(
        for healthKitDevice: HKDevice,
        context: HealthKitFHIRConversionContext
    ) -> String? {
        guard let subject = context.subject.reference?.value?.string else {
            return nil
        }
        return GroveFHIRRecordingDeviceIdentity.value(
            subject: subject,
            adapter: "healthkit",
            recorder: GroveFHIRRecordingDeviceIdentity.Recorder(
                manufacturer: healthKitDevice.manufacturer?.nonEmpty,
                model: healthKitDevice.model?.nonEmpty,
                hardwareVersion: healthKitDevice.hardwareVersion?.nonEmpty
            )
        )
    }

    static func sourceAuthor(
        for revision: HKSourceRevision,
        classification: HealthKitFHIRSourceActor,
        context: HealthKitFHIRConversionContext,
        sourceUUID: String
    ) throws -> IdentifiedDevice? {
        switch classification {
        case .omit:
            return nil
        case .application:
            return try sourceApplicationAuthor(for: revision)
        case .device(let discloseIdentifier):
            return try sourceDeviceAuthor(
                for: revision,
                discloseIdentifier: discloseIdentifier,
                context: context,
                sourceUUID: sourceUUID
            )
        }
    }

    private static func sourceApplicationAuthor(
        for revision: HKSourceRevision
    ) throws -> IdentifiedDevice? {
        guard let name = revision.source.name.nonEmpty,
              let bundleIdentifier = revision.source.bundleIdentifier.nonEmpty else {
            return nil
        }
        var device = applicationDevice(HealthKitFHIRApplication(
            name: name,
            bundleIdentifier: bundleIdentifier,
            version: revision.version?.nonEmpty ?? "unknown"
        ))
        if revision.version?.nonEmpty == nil {
            device.version = nil
        }
        return IdentifiedDevice(
            resource: device,
            identity: try GroveFHIRBusinessIdentifier(
                system: GroveFHIRCanonical.appleBundleIdentifierSystem,
                value: bundleIdentifier
            )
        )
    }

    private static func sourceDeviceAuthor(
        for revision: HKSourceRevision,
        discloseIdentifier: Bool,
        context: HealthKitFHIRConversionContext,
        sourceUUID: String
    ) throws -> IdentifiedDevice? {
        var device = Device()
        if let name = revision.source.name.nonEmpty {
            device.deviceName = [DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )]
        }
        device.modelNumber = revision.productType?.nonEmpty?.asFHIRStringPrimitive()
        let identity: GroveFHIRBusinessIdentifier
        if discloseIdentifier, let identifier = revision.source.bundleIdentifier.nonEmpty {
            identity = try GroveFHIRBusinessIdentifier(
                system: GroveFHIRCanonical.healthKitSourceDeviceIdentifierSystem,
                value: identifier
            )
            device.identifier = [identity.fhirIdentifier]
        } else {
            identity = try derivedIdentity(
                context: context,
                sourceUUID: sourceUUID,
                role: "source-author-device"
            )
        }
        guard device.deviceName != nil || device.identifier != nil || device.modelNumber != nil else {
            return nil
        }
        return IdentifiedDevice(resource: device, identity: identity)
    }

    static func provenance(
        sourceIdentifier: Identifier,
        targetURL: String,
        converterURL: String,
        sourceAuthorURL: String?,
        recordedAt: Date
    ) throws -> Provenance {
        let author = sourceAuthorURL.map { url in
            ProvenanceAgent(
                type: CodeableConcept(coding: [Coding(
                    code: "author",
                    display: "Author",
                    system: participantType
                )]),
                who: Reference(reference: url.asFHIRStringPrimitive())
            )
        }
        var entity = ProvenanceEntity(
            role: FHIRPrimitive(.source),
            what: Reference(identifier: sourceIdentifier)
        )
        entity.agent = author.map { [$0] }
        return Provenance(
            activity: CodeableConcept(coding: [Coding(
                code: "transform",
                display: "Transform/Translate Record Lifecycle Event",
                system: lifecycleEvent
            )]),
            agent: [ProvenanceAgent(
                type: CodeableConcept(coding: [Coding(
                    code: "assembler",
                    display: "Assembler",
                    system: participantType
                )]),
                who: Reference(reference: converterURL.asFHIRStringPrimitive())
            )],
            entity: [entity],
            meta: Meta(profile: [GroveFHIRHealthKitCatalog.conversionProvenanceProfile]),
            occurred: .dateTime(FHIRPrimitive(try DateTime(date: recordedAt))),
            recorded: FHIRPrimitive(try Instant(date: recordedAt)),
            target: [Reference(reference: targetURL.asFHIRStringPrimitive())]
        )
    }
}


extension Array where Element == DeviceVersion {
    fileprivate mutating func appendVersion(_ value: String?, code: String, display: String) {
        guard let value = value?.nonEmpty else {
            return
        }
        append(DeviceVersion(
            type: CodeableConcept(coding: [Coding(
                code: code.asFHIRStringPrimitive(),
                display: display.asFHIRStringPrimitive(),
                system: "urn:iso:std:iso:11073:10101"
            )]),
            value: value.asFHIRStringPrimitive()
        ))
    }
}


extension String {
    fileprivate var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

#endif
