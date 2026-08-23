//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Source-neutral FHIR graph construction keeps each complete resource projection adjacent for auditability.
// swiftlint:disable file_length function_body_length function_parameter_count multiline_literal_brackets discouraged_optional_collection

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


/// Why one source record could not be converted.
public enum SensorFHIRConversionError: Error, Equatable, Sendable {
    case invalidConverterApplication(String)
    case invalidExchangeIdentity(String)
    case repositoryIDWithoutRecordingDevice
    case repositoryIDWithoutProvenance
    case payloadTooLarge(byteCount: Int)
}


/// A typed failure for one record; batch conversion never drops input silently.
public struct SensorFHIRRecordFailure: Error, Equatable, Sendable {
    public let sourceIdentifier: GroveFHIRBusinessIdentifier
    public let sourceTypeIdentifier: String
    public let reason: SensorFHIRConversionError
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
    ) throws -> SensorFHIRConversion {
        do {
            return try Self.convertRecord(record, context: context)
        } catch let error as SensorFHIRConversionError {
            throw error
        } catch let error as GroveFHIRExchangeIdentityError {
            throw SensorFHIRConversionError.invalidExchangeIdentity(String(describing: error))
        }
    }

    public func convert<S: Sequence>(
        _ records: S,
        context: SensorFHIRConversionContext
    ) -> SensorFHIRBatchResult where S.Element == SensorFHIRRecord {
        var conversions: [SensorFHIRConversion] = []
        var failures: [SensorFHIRRecordFailure] = []
        for record in records {
            do {
                conversions.append(try convert(record, context: context))
            } catch let reason as SensorFHIRConversionError {
                failures.append(SensorFHIRRecordFailure(
                    sourceIdentifier: record.identifier,
                    sourceTypeIdentifier: record.sourceTypeIdentifier,
                    reason: reason
                ))
            } catch {
                failures.append(SensorFHIRRecordFailure(
                    sourceIdentifier: record.identifier,
                    sourceTypeIdentifier: record.sourceTypeIdentifier,
                    reason: .invalidExchangeIdentity(String(describing: error))
                ))
            }
        }
        return SensorFHIRBatchResult(conversions: conversions, failures: failures)
    }
}


extension SensorFHIRConverter {
    private static let mdc: FHIRPrimitive<FHIRURI> = "urn:iso:std:iso:11073:10101"
    private static let ucum: FHIRPrimitive<FHIRURI> = "http://unitsofmeasure.org"
    private static let participantType: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/provenance-participant-type"
    private static let lifecycleEvent: FHIRPrimitive<FHIRURI> =
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

    private static func primaryResource(
        _ record: SensorFHIRRecord,
        context: SensorFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> SensorFHIRPrimaryResource {
        switch record {
        case .sampledData(let record):
            return .observation(try observation(
                record,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            ))
        case .electrocardiogram(let record):
            return .observation(try observation(
                record,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            ))
        case .recordingDocument(let record):
            return .recordingDocument(try document(
                record,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            ))
        }
    }

    private static func observation(
        _ record: GroveSensorSampledDataRecord,
        context: SensorFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        var profiles = [GroveFHIRProfile.groveSensorSampledDataObservation]
        if let adapterProfile = record.adapterProfile {
            profiles.append(adapterProfile)
        }
        var observation = Observation(code: record.code.concept, status: FHIRPrimitive(.final))
        observation.meta = Meta(profile: profiles)
        observation.identifier = [record.identifier.fhirIdentifier]
        observation.subject = context.subject
        observation.effective = .period(try period(start: record.start, end: record.end))
        observation.issued = FHIRPrimitive(try Instant(date: context.issuedAt))
        observation.device = recordingDeviceURL.map(reference)
        observation.extension = contextExtensions(context, converterURL: converterURL)
        observation.value = .sampledData(sampledData(
            samples: record.samples,
            dimensions: record.dimensions,
            periodMilliseconds: record.periodMilliseconds,
            origin: record.origin,
            unitCode: record.unitCode,
            unitDisplay: record.unitDisplay
        ))
        return observation
    }

    private static func observation(
        _ record: GroveSensorECGRecord,
        context: SensorFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        var profiles = [GroveFHIRProfile.groveSensorEcgObservation]
        if let adapterProfile = record.adapterProfile {
            profiles.append(adapterProfile)
        }
        var observation = Observation(
            code: CodeableConcept(coding: [Coding(
                code: "11524-6".asFHIRStringPrimitive(),
                display: "EKG study".asFHIRStringPrimitive(),
                system: "http://loinc.org".asFHIRURIPrimitive()
            )]),
            status: FHIRPrimitive(.final)
        )
        observation.meta = Meta(profile: profiles)
        observation.identifier = [record.identifier.fhirIdentifier]
        observation.subject = context.subject
        observation.effective = .period(try period(start: record.start, end: record.end))
        observation.issued = FHIRPrimitive(try Instant(date: context.issuedAt))
        observation.device = recordingDeviceURL.map(reference)
        observation.extension = contextExtensions(context, converterURL: converterURL)
        observation.component = record.channels.map { channel in
            ObservationComponent(
                code: channel.lead.concept,
                value: .sampledData(sampledData(
                    samples: channel.millivolts,
                    dimensions: 1,
                    periodMilliseconds: record.periodMilliseconds,
                    origin: channel.originMillivolts,
                    unitCode: "mV",
                    unitDisplay: "mV"
                ))
            )
        }
        return observation
    }

    private static func document(
        _ record: GroveSensorRecordingDocument,
        context: SensorFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> DocumentReference {
        var profiles = [GroveFHIRProfile.groveSensorRecordingDocument]
        if let adapterProfile = record.adapterProfile {
            profiles.append(adapterProfile)
        }
        var authors = recordingDeviceURL.map { [reference($0)] } ?? []
        authors.append(reference(converterURL))
        let related = context.researchStudies + record.related.map {
            Reference(identifier: $0.fhirIdentifier)
        }
        var document = DocumentReference(
            author: authors,
            content: [DocumentReferenceContent(
                attachment: try attachment(record),
                format: Coding(
                    code: record.format.asFHIRStringPrimitive(),
                    system: GroveSensorKitContract.recordingFormatCodeSystem.asFHIRURIPrimitive()
                )
            )],
            context: related.isEmpty ? nil : DocumentReferenceContext(related: related),
            date: FHIRPrimitive(try Instant(date: context.recordedAt)),
            identifier: [record.identifier.fhirIdentifier],
            meta: Meta(profile: profiles),
            status: FHIRPrimitive(.current),
            subject: context.subject,
            type: record.type.concept
        )
        document.id = context.repositoryIDs.record?.primitive
        return document
    }

    private static func sampledData(
        samples: [Double],
        dimensions: Int,
        periodMilliseconds: Double,
        origin: Double,
        unitCode: String,
        unitDisplay: String?
    ) -> SampledData {
        SampledData(
            data: samples.map(fhirNumber).joined(separator: " ").asFHIRStringPrimitive(),
            dimensions: FHIRPrimitive(FHIRPositiveInteger(Int32(dimensions))),
            origin: Quantity(
                code: unitCode.asFHIRStringPrimitive(),
                system: ucum,
                unit: unitDisplay?.asFHIRStringPrimitive(),
                value: FHIRPrimitive(FHIRDecimal(Decimal(string: String(groveFHIRPlainDecimal: origin)) ?? 0))
            ),
            period: FHIRPrimitive(FHIRDecimal(Decimal(string: String(groveFHIRPlainDecimal: periodMilliseconds)) ?? 0))
        )
    }

    private static func fhirNumber(_ value: Double) -> String {
        String(groveFHIRPlainDecimal: value)
    }

    private static func period(start: Date, end: Date) throws -> Period {
        Period(
            end: FHIRPrimitive(try DateTime(date: end)),
            start: FHIRPrimitive(try DateTime(date: start))
        )
    }

    private static func attachment(_ record: GroveSensorRecordingDocument) throws -> Attachment {
        let bytes: Data
        switch record.payload {
        case .inline(let data), .sidecar(_, let data):
            bytes = data
        }
        guard let size = Int32(exactly: bytes.count) else {
            throw SensorFHIRConversionError.payloadTooLarge(byteCount: bytes.count)
        }
        var attachment = Attachment(
            contentType: record.contentType.asFHIRStringPrimitive(),
            hash: FHIRPrimitive(Base64Binary(with: Data(Insecure.SHA1.hash(data: bytes)))),
            size: FHIRPrimitive(FHIRUnsignedInteger(size)),
            title: record.title.asFHIRStringPrimitive()
        )
        switch record.payload {
        case .inline(let data):
            attachment.data = FHIRPrimitive(Base64Binary(with: data))
        case .sidecar(let path, _):
            attachment.url = FHIRPrimitive(FHIRURI(stringLiteral: path))
        }
        return attachment
    }

    private static func contextExtensions(
        _ context: SensorFHIRConversionContext,
        converterURL: String
    ) -> [Extension]? {
        var extensions = context.researchStudies.map { study in
            Extension(url: GroveFHIRCanonical.researchStudy, value: .reference(study))
        }
        if context.converterWasGateway {
            extensions.append(Extension(
                url: GroveFHIRCanonical.gatewayDevice,
                value: .reference(reference(converterURL))
            ))
        }
        return extensions.isEmpty ? nil : extensions
    }

    private static func applicationDevice(_ application: SensorFHIRApplication) -> Device {
        var device = Device()
        device.meta = Meta(profile: [GroveFHIRProfile.groveApplicationDevice])
        device.identifier = [application.identifier.fhirIdentifier]
        device.deviceName = [DeviceDeviceName(
            name: application.name.asFHIRStringPrimitive(),
            type: FHIRPrimitive(.userFriendlyName)
        )]
        if let version = application.version {
            device.version = [DeviceVersion(
                type: CodeableConcept(coding: [Coding(
                    code: "531975".asFHIRStringPrimitive(),
                    display: "MDC_ID_PROD_SPEC_SW".asFHIRStringPrimitive(),
                    system: mdc
                )]),
                value: version.asFHIRStringPrimitive()
            )]
        }
        return device
    }

    private static func recordingDevice(_ source: SensorFHIRRecordingDevice) -> Device {
        var device = Device()
        device.meta = Meta(profile: [GroveFHIRProfile.groveRecordingDevice])
        device.identifier = [source.identifier.fhirIdentifier]
        if let name = source.name {
            device.deviceName = [DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )]
        }
        device.manufacturer = source.manufacturer?.asFHIRStringPrimitive()
        device.modelNumber = source.modelNumber?.asFHIRStringPrimitive()
        return device
    }

    private static func provenance(
        sourceIdentifier: Identifier,
        targetURL: String,
        converterURL: String,
        recordedAt: Date
    ) throws -> Provenance {
        Provenance(
            activity: CodeableConcept(coding: [Coding(
                code: "transform".asFHIRStringPrimitive(),
                display: "Transform/Translate Record Lifecycle Event".asFHIRStringPrimitive(),
                system: lifecycleEvent
            )]),
            agent: [ProvenanceAgent(
                type: CodeableConcept(coding: [Coding(
                    code: "assembler".asFHIRStringPrimitive(),
                    display: "Assembler".asFHIRStringPrimitive(),
                    system: participantType
                )]),
                who: reference(converterURL)
            )],
            entity: [ProvenanceEntity(
                role: FHIRPrimitive(.source),
                what: Reference(identifier: sourceIdentifier)
            )],
            meta: Meta(profile: [FHIRPrimitive(Canonical(
                stringLiteral: GroveSensorKitContract.sensorConversionProvenanceProfile
            ))]),
            occurred: .dateTime(FHIRPrimitive(try DateTime(date: recordedAt))),
            recorded: FHIRPrimitive(try Instant(date: recordedAt)),
            target: [reference(targetURL)]
        )
    }

    private static func reference(_ url: String) -> Reference {
        Reference(reference: url.asFHIRStringPrimitive())
    }
}
