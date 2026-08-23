//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The graph assembly keeps one complete exchange transaction together.
// swiftlint:disable function_body_length

import CryptoKit
import FHIRModelsExtensions
public import Foundation
public import GroveFHIRContract
public import ModelsR4


/// Product identity of the application performing a Sensor-to-FHIR conversion.
public struct SensorFHIRApplication: Hashable, Sendable {
    public let identifier: GroveFHIRBusinessIdentifier
    public let name: String
    public let version: String?

    public init(identifier: GroveFHIRBusinessIdentifier, name: String, version: String? = nil) {
        self.identifier = identifier
        self.name = name
        self.version = version
    }
}


/// Identity and descriptive fields of the physical recording device, when known.
public struct SensorFHIRRecordingDevice: Hashable, Sendable {
    public let identifier: GroveFHIRBusinessIdentifier
    public let name: String?
    public let manufacturer: String?
    public let modelNumber: String?

    public init(
        identifier: GroveFHIRBusinessIdentifier,
        name: String? = nil,
        manufacturer: String? = nil,
        modelNumber: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.manufacturer = manufacturer
        self.modelNumber = modelNumber
    }
}


/// Optional repository-assigned logical ids for one Sensor exchange graph.
public struct SensorFHIRRepositoryIDs: Hashable, Sendable {
    public let bundle: GroveFHIRRepositoryID?
    public let record: GroveFHIRRepositoryID?
    public let recordingDevice: GroveFHIRRepositoryID?
    public let converterApplication: GroveFHIRRepositoryID?
    public let provenance: GroveFHIRRepositoryID?

    public init(
        bundle: GroveFHIRRepositoryID? = nil,
        record: GroveFHIRRepositoryID? = nil,
        recordingDevice: GroveFHIRRepositoryID? = nil,
        converterApplication: GroveFHIRRepositoryID? = nil,
        provenance: GroveFHIRRepositoryID? = nil
    ) {
        self.bundle = bundle
        self.record = record
        self.recordingDevice = recordingDevice
        self.converterApplication = converterApplication
        self.provenance = provenance
    }
}


/// Explicit deployment and audit inputs used to build one reproducible graph.
public struct SensorFHIRConversionContext: Sendable {
    public let subject: Reference
    public let converter: SensorFHIRApplication
    public let graphIdentifierSystem: String
    public let recordingDevice: SensorFHIRRecordingDevice?
    public let converterWasGateway: Bool
    public let issuedAt: Date
    public let recordedAt: Date
    public let researchStudies: [Reference]
    public let repositoryIDs: SensorFHIRRepositoryIDs

    public init(
        subject: Reference,
        converter: SensorFHIRApplication,
        graphIdentifierSystem: String,
        recordingDevice: SensorFHIRRecordingDevice? = nil,
        converterWasGateway: Bool = false,
        issuedAt: Date,
        recordedAt: Date,
        researchStudies: [Reference] = [],
        repositoryIDs: SensorFHIRRepositoryIDs = .init()
    ) {
        self.subject = subject
        self.converter = converter
        self.graphIdentifierSystem = graphIdentifierSystem
        self.recordingDevice = recordingDevice
        self.converterWasGateway = converterWasGateway
        self.issuedAt = issuedAt
        self.recordedAt = recordedAt
        self.researchStudies = researchStudies
        self.repositoryIDs = repositoryIDs
    }
}


/// Complete business identities of one emitted Sensor exchange graph.
public struct SensorFHIRGraphIdentifiers: Hashable, Sendable {
    public let bundle: GroveFHIRBusinessIdentifier
    public let record: GroveFHIRBusinessIdentifier
    public let recordingDevice: GroveFHIRBusinessIdentifier?
    public let converterApplication: GroveFHIRBusinessIdentifier
    public let provenance: GroveFHIRBusinessIdentifier?
}


/// The typed primary FHIR resource emitted for a Sensor record.
public enum SensorFHIRPrimaryResource: Sendable {
    case observation(Observation)
    case recordingDocument(DocumentReference)
}


/// One complete Sensor conversion graph and collection Bundle.
public struct SensorFHIRConversion: Sendable {
    public let sourceIdentifier: Identifier
    public let sourceTypeIdentifier: String
    public let graphIdentifiers: SensorFHIRGraphIdentifiers
    public let primaryResource: SensorFHIRPrimaryResource
    public let recordingDevice: Device?
    public let converterApplication: Device
    public let provenance: Provenance?
    public let bundle: ModelsR4.Bundle
}


/// Explicit successes and failures from a batch conversion.
public struct SensorFHIRBatchResult: Sendable {
    public let conversions: [SensorFHIRConversion]
    public let failures: [SensorFHIRRecordFailure]
}


/// Builds source-neutral R4 graphs for sampled data, ECG, and native recordings.
public struct SensorFHIRConverter: Sendable {
    public init() {}

    public func convert(
        _ record: SensorFHIRRecord,
        context: SensorFHIRConversionContext
    ) throws(SensorFHIRConversionError) -> SensorFHIRConversion {
        do {
            return try Self.convertRecord(record, context: context)
        } catch {
            throw SensorFHIRConversionError(conversionFailure: error)
        }
    }

    /// Converts every input and returns a typed failure for every record that was not emitted.
    public func convert<S: Sequence>(
        _ records: S,
        context: SensorFHIRConversionContext
    ) -> SensorFHIRBatchResult where S.Element == SensorFHIRRecord {
        var conversions: [SensorFHIRConversion] = []
        var failures: [SensorFHIRRecordFailure] = []
        for record in records {
            do {
                conversions.append(try convert(record, context: context))
            } catch {
                failures.append(SensorFHIRRecordFailure(
                    sourceIdentifier: record.identifier,
                    sourceTypeIdentifier: record.sourceTypeIdentifier,
                    reason: error
                ))
            }
        }
        return SensorFHIRBatchResult(conversions: conversions, failures: failures)
    }
}


extension SensorFHIRConverter {
    static let mdc: FHIRPrimitive<FHIRURI> = "urn:iso:std:iso:11073:10101"
    static let ucum: FHIRPrimitive<FHIRURI> = "http://unitsofmeasure.org"
    static let participantType: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/provenance-participant-type"
    static let lifecycleEvent: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/iso-21089-lifecycle"

    private static func convertRecord(
        _ record: SensorFHIRRecord,
        context: SensorFHIRConversionContext
    ) throws -> SensorFHIRConversion {
        try validate(context: context)
        let bundleIdentity = try derivedIdentity(
            role: "exchange-bundle",
            record: record.identifier,
            system: context.graphIdentifierSystem
        )
        let provenanceIdentity = try derivedIdentity(
            role: "conversion-provenance",
            record: record.identifier,
            system: context.graphIdentifierSystem
        )

        let recordURL = try GroveFHIRExchangeIdentity.fullURL(for: record.identifier)
        let converterURL = try GroveFHIRExchangeIdentity.fullURL(for: context.converter.identifier)
        let recordingDeviceURL = try context.recordingDevice.map {
            try GroveFHIRExchangeIdentity.fullURL(for: $0.identifier)
        }

        var converterApplication = applicationDevice(context.converter)
        converterApplication.id = context.repositoryIDs.converterApplication?.primitive
        var recordingDevice = context.recordingDevice.map(recordingDevice)
        recordingDevice?.id = context.repositoryIDs.recordingDevice?.primitive

        let primaryResource = try primaryResource(
            record,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        let primaryProxy: ResourceProxy
        switch primaryResource {
        case .observation(var observation):
            observation.id = context.repositoryIDs.record?.primitive
            primaryProxy = ResourceProxy(with: observation)
        case .recordingDocument(var document):
            document.id = context.repositoryIDs.record?.primitive
            primaryProxy = ResourceProxy(with: document)
        }

        var provenance = try provenance(
            sourceIdentifier: record.identifier.fhirIdentifier,
            targetURL: recordURL,
            converterURL: converterURL,
            recordedAt: context.recordedAt
        )
        provenance.id = context.repositoryIDs.provenance?.primitive

        var entries = [
            try GroveFHIRExchangeIdentity.entry(identifier: record.identifier, resource: primaryProxy)
        ]
        if let recordingDevice, let identity = context.recordingDevice?.identifier {
            entries.append(try GroveFHIRExchangeIdentity.entry(
                identifier: identity,
                resource: ResourceProxy(with: recordingDevice)
            ))
        }
        entries.append(try GroveFHIRExchangeIdentity.entry(
            identifier: context.converter.identifier,
            resource: ResourceProxy(with: converterApplication)
        ))
        entries.append(try GroveFHIRExchangeIdentity.entry(
            identifier: provenanceIdentity,
            resource: ResourceProxy(with: provenance)
        ))
        try GroveFHIRExchangeIdentity.validate(entries: entries)

        var bundle = Bundle(
            entry: entries,
            identifier: bundleIdentity.fhirIdentifier,
            meta: Meta(profile: [GroveFHIRProfile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try Instant(date: context.recordedAt)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryIDs.bundle?.primitive

        let retainedPrimary: SensorFHIRPrimaryResource
        switch primaryResource {
        case .observation(var observation):
            observation.id = context.repositoryIDs.record?.primitive
            retainedPrimary = .observation(observation)
        case .recordingDocument(var document):
            document.id = context.repositoryIDs.record?.primitive
            retainedPrimary = .recordingDocument(document)
        }
        return SensorFHIRConversion(
            sourceIdentifier: record.identifier.fhirIdentifier,
            sourceTypeIdentifier: record.sourceTypeIdentifier,
            graphIdentifiers: SensorFHIRGraphIdentifiers(
                bundle: bundleIdentity,
                record: record.identifier,
                recordingDevice: context.recordingDevice?.identifier,
                converterApplication: context.converter.identifier,
                provenance: provenanceIdentity
            ),
            primaryResource: retainedPrimary,
            recordingDevice: recordingDevice,
            converterApplication: converterApplication,
            provenance: provenance,
            bundle: bundle
        )
    }

    private static func validate(context: SensorFHIRConversionContext) throws {
        guard !context.converter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorFHIRConversionError.invalidConverterApplication("name")
        }
        if context.converter.version?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw SensorFHIRConversionError.invalidConverterApplication("version")
        }
        _ = try GroveFHIRBusinessIdentifier(system: context.graphIdentifierSystem, value: "validation")
        if context.repositoryIDs.recordingDevice != nil, context.recordingDevice == nil {
            throw SensorFHIRConversionError.repositoryIDWithoutRecordingDevice
        }
        _ = try validateReference(context.subject, field: "subject", expectedResourceType: "Patient")
        var studyIdentities: Set<GroveFHIRTypedReferenceIdentity> = []
        for study in context.researchStudies {
            let identity = try validateReference(
                study,
                field: "researchStudies",
                expectedResourceType: "ResearchStudy"
            )
            guard studyIdentities.insert(identity).inserted else {
                throw SensorFHIRConversionError.duplicateReference(field: "researchStudies")
            }
        }
    }

    private static func validateReference(
        _ reference: Reference,
        field: String,
        expectedResourceType: String
    ) throws(SensorFHIRConversionError) -> GroveFHIRTypedReferenceIdentity {
        do {
            return try GroveFHIRTypedReference.validate(
                reference,
                expectedResourceType: expectedResourceType
            )
        } catch {
            switch error {
            case .unboundBundleUUID:
                throw .invalidExchangeIdentity(
                    "\(field) contains a UUID URN that is not an entry in the emitted Bundle"
                )
            case .invalidReference:
                throw .invalidReference(field: field, expectedResourceType: expectedResourceType)
            }
        }
    }

    private static func derivedIdentity(
        role: String,
        record: GroveFHIRBusinessIdentifier,
        system: String
    ) throws -> GroveFHIRBusinessIdentifier {
        let recordURL = try GroveFHIRExchangeIdentity.fullURL(for: record)
        let recordUUID = recordURL.dropFirst("urn:uuid:".count)
        return try GroveFHIRBusinessIdentifier(system: system, value: "\(role):\(recordUUID)")
    }
}
