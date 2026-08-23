//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The converter keeps the complete graph transaction together; literal formatting follows FHIR shape.
// swiftlint:disable file_length multiline_literal_brackets

#if canImport(HealthKit)

import FHIRModelsExtensions
import Foundation
public import GroveFHIRContract
import GroveHealthKit
public import HealthKit
public import ModelsR4


/// Profile-aware HealthKit-to-FHIR R4 facade.
///
/// The converter consumes already-fetched `HKSample` values. It does not query HealthKit,
/// authorize data access, synchronize anchors, persist resources, or upload anything.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct HealthKitFHIRConverter: Sendable {
    public init() {}

    /// Converts one sample only when the closed catalog admits its exact published contract.
    public func convert(
        _ sample: HKSample,
        context: HealthKitFHIRConversionContext
    ) throws(GroveHealthKitFHIRError) -> HealthKitFHIRConversion {
        do {
            return try Self.convertSample(sample, context: context)
        } catch {
            throw GroveHealthKitFHIRError(conversionFailure: error)
        }
    }

    /// Converts one sample for a subject, deriving the rest of the context from the running app.
    ///
    /// Equivalent to building a ``HealthKitFHIRConversionContext`` with only its subject. Use the
    /// context form to set a study reference, a disclosure policy, or a fixed conversion instant.
    ///
    /// ```swift
    /// let conversion = try HealthKitFHIRConverter().convert(sample, for: patient)
    /// ```
    public func convert(
        _ sample: HKSample,
        for subject: Reference
    ) throws(GroveHealthKitFHIRError) -> HealthKitFHIRConversion {
        try convert(sample, context: HealthKitFHIRConversionContext(subject: subject))
    }

    /// Converts every input for a subject, deriving the rest of the context from the running app.
    public func convert<S: Sequence>(
        _ samples: S,
        for subject: Reference
    ) -> HealthKitFHIRBatchResult where S.Element == HKSample {
        convert(samples, context: HealthKitFHIRConversionContext(subject: subject))
    }

    /// Converts every input and returns a typed failure for every record that was not emitted.
    public func convert<S: Sequence>(
        _ samples: S,
        context: HealthKitFHIRConversionContext
    ) -> HealthKitFHIRBatchResult where S.Element == HKSample {
        var conversions: [HealthKitFHIRConversion] = []
        var failures: [HealthKitFHIRRecordFailure] = []
        for sample in samples {
            do {
                conversions.append(try convert(sample, context: context))
            } catch {
                failures.append(HealthKitFHIRRecordFailure(
                    sourceUUID: sample.uuid,
                    sourceTypeIdentifier: sample.sampleType.identifier,
                    reason: error
                ))
            }
        }
        return HealthKitFHIRBatchResult(conversions: conversions, failures: failures)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRConverter {
    struct IdentifiedDevice {
        var resource: Device
        let identity: GroveFHIRBusinessIdentifier
    }

    private struct HealthKitSleepStage {
        let sharedCode: String
        let sharedDisplay: String
        let sourceCode: String
        let sourceDisplay: String
    }

    static let mdc: FHIRPrimitive<FHIRURI> = "urn:iso:std:iso:11073:10101"
    static let participantType: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/provenance-participant-type"
    static let lifecycleEvent: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/iso-21089-lifecycle"
    static let observationCategory: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/observation-category"
    /// Displays for the measurements whose generated contract carries no code display.
    private static let measurementDisplays = [
        "blood-pressure": "Blood pressure panel with all children optional",
        "body-height": "Body height",
        "body-mass-index": "Body mass index (BMI) [Ratio]",
        "body-temperature": "Body temperature",
        "body-weight": "Body weight",
        "distance": "Distance traveled",
        "heart-rate": "Heart rate",
        "oxygen-saturation": "Oxygen saturation in Arterial blood",
        "respiratory-rate": "Respiratory rate"
    ]

    private static func convertSample(
        _ sample: HKSample,
        context: HealthKitFHIRConversionContext
    ) throws -> HealthKitFHIRConversion {
        try validate(context: context)
        if sample is HKElectrocardiogram {
            throw GroveHealthKitFHIRError.missingECGEvidence
        }
        guard let binding = HealthKitFHIRCatalog.binding(for: sample) else {
            throw unconvertibleSampleError(forSourceTypeIdentifier: sample.sampleType.identifier)
        }
        return try assembleGraph(for: sample, context: context) { recordingDeviceURL, converterURL in
            try observation(
                for: sample,
                binding: binding,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        }
    }

    // Assembly is intentionally one atomic, reviewable graph transaction.
    // swiftlint:disable:next function_body_length
    static func assembleGraph(
        for sample: HKSample,
        context: HealthKitFHIRConversionContext,
        observationBuilder: (_ recordingDeviceURL: String?, _ converterURL: String) throws -> Observation
    ) throws -> HealthKitFHIRConversion {
        let sourceUUID = sample.uuid
        let sourceUUIDString = sourceUUID.uuidString.lowercased()
        let observationIdentity = try GroveFHIRBusinessIdentifier(
            system: GroveFHIRCanonical.healthKitObjectIdentifierSystem,
            value: sourceUUIDString
        )
        let converterIdentity = try GroveFHIRBusinessIdentifier(
            system: GroveFHIRCanonical.appleBundleIdentifierSystem,
            value: context.converter.bundleIdentifier
        )
        let bundleIdentity = try derivedIdentity(
            context: context,
            sourceUUID: sourceUUIDString,
            role: "exchange-bundle"
        )
        let provenanceIdentity = try derivedIdentity(
            context: context,
            sourceUUID: sourceUUIDString,
            role: "conversion-provenance"
        )

        var converterApplication = applicationDevice(context.converter)
        converterApplication.id = context.repositoryIDs.converterApplication?.primitive
        var recordingDevice = try Self.recordingDevice(
            for: sample.device,
            context: context,
            sourceUUID: sourceUUIDString
        )
        recordingDevice?.resource.id = context.repositoryIDs.recordingDevice?.primitive
        var sourceAuthor = try Self.sourceAuthor(
            for: sample.sourceRevision,
            classification: context.sourceActor,
            context: context,
            sourceUUID: sourceUUIDString
        )
        if context.repositoryIDs.recordingDevice != nil, recordingDevice == nil {
            throw GroveHealthKitFHIRError.invalidExchangeIdentity(
                "a recording-device repository id was supplied, but this record has no recording device"
            )
        }
        if context.repositoryIDs.sourceAuthor != nil, sourceAuthor == nil {
            throw GroveHealthKitFHIRError.invalidExchangeIdentity(
                "a source-author repository id was supplied, but source authoring is omitted or unavailable"
            )
        }

        let sourceAuthorUsesConverter = sourceAuthor?.identity == converterIdentity
        if sourceAuthorUsesConverter {
            if let sourceID = context.repositoryIDs.sourceAuthor,
               let converterID = context.repositoryIDs.converterApplication,
               sourceID != converterID {
                throw GroveHealthKitFHIRError.invalidExchangeIdentity(
                    "one application cannot have two repository ids in the same graph"
                )
            }
            converterApplication.id = (
                context.repositoryIDs.converterApplication ?? context.repositoryIDs.sourceAuthor
            )?.primitive
            sourceAuthor = IdentifiedDevice(resource: converterApplication, identity: converterIdentity)
        } else {
            sourceAuthor?.resource.id = context.repositoryIDs.sourceAuthor?.primitive
        }

        let observationURL = try GroveFHIRExchangeIdentity.fullURL(for: observationIdentity)
        let converterURL = try GroveFHIRExchangeIdentity.fullURL(for: converterIdentity)
        let recordingDeviceURL = try recordingDevice.map { try GroveFHIRExchangeIdentity.fullURL(for: $0.identity) }
        let sourceAuthorURL = try sourceAuthor.map { try GroveFHIRExchangeIdentity.fullURL(for: $0.identity) }
        var observation = try observationBuilder(recordingDeviceURL, converterURL)
        observation.id = context.repositoryIDs.observation?.primitive
        observation.identifier = [observationIdentity.fhirIdentifier]

        var provenance = try Self.provenance(
            sourceIdentifier: observationIdentity.fhirIdentifier,
            targetURL: observationURL,
            converterURL: converterURL,
            sourceAuthorURL: sourceAuthorURL,
            recordedAt: context.conversionInstant
        )
        provenance.id = context.repositoryIDs.provenance?.primitive

        var entries = [
            try GroveFHIRExchangeIdentity.entry(
                identifier: observationIdentity,
                resource: ResourceProxy(with: observation)
            )
        ]
        if let recordingDevice {
            entries.append(try GroveFHIRExchangeIdentity.entry(
                identifier: recordingDevice.identity,
                resource: ResourceProxy(with: recordingDevice.resource)
            ))
        }
        entries.append(try GroveFHIRExchangeIdentity.entry(
            identifier: converterIdentity,
            resource: ResourceProxy(with: converterApplication)
        ))
        if let sourceAuthor, !sourceAuthorUsesConverter {
            entries.append(try GroveFHIRExchangeIdentity.entry(
                identifier: sourceAuthor.identity,
                resource: ResourceProxy(with: sourceAuthor.resource)
            ))
        }
        entries.append(try GroveFHIRExchangeIdentity.entry(
            identifier: provenanceIdentity,
            resource: ResourceProxy(with: provenance)
        ))
        try GroveFHIRExchangeIdentity.validate(entries: entries)

        var bundle = Bundle(
            entry: entries,
            identifier: bundleIdentity.fhirIdentifier,
            meta: Meta(profile: [GroveFHIRProfile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try Instant(date: context.conversionInstant)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryIDs.bundle?.primitive

        return HealthKitFHIRConversion(
            sourceIdentifier: observationIdentity.fhirIdentifier,
            graphIdentifiers: HealthKitFHIRGraphIdentifiers(
                bundle: bundleIdentity,
                observation: observationIdentity,
                recordingDevice: recordingDevice?.identity,
                converterApplication: converterIdentity,
                sourceAuthor: sourceAuthor?.identity,
                provenance: provenanceIdentity
            ),
            observation: observation,
            recordingDevice: recordingDevice?.resource,
            converterApplication: converterApplication,
            sourceAuthor: sourceAuthor?.resource,
            provenance: provenance,
            bundle: bundle
        )
    }

    /// The catalog-driven reason a sample without a binding fails closed.
    static func unconvertibleSampleError(
        forSourceTypeIdentifier identifier: String
    ) -> GroveHealthKitFHIRError {
        guard let entry = HealthKitFHIRCatalog.entry(forSourceTypeIdentifier: identifier) else {
            return .unsupportedSampleType(identifier)
        }
        switch entry.implementationStatus {
        case .intentionallyUnsupported:
            return .intentionallyUnsupported(sampleType: identifier, reason: entry.requirement ?? "")
        case .platformExclusive:
            return .platformExclusiveDocument(sampleType: identifier)
        case .supported where identifier == HKWorkoutType.workoutType().identifier:
            return .notYetConvertible(sampleType: identifier)
        case .supported where identifier == HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue
            || identifier == HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue:
            return .componentSampleRequiresCorrelation(sampleType: identifier)
        case .supported, .deferred:
            return .unsupportedSampleType(identifier)
        }
    }

    static func derivedIdentity(
        context: HealthKitFHIRConversionContext,
        sourceUUID: String,
        role: String
    ) throws -> GroveFHIRBusinessIdentifier {
        try GroveFHIRBusinessIdentifier(
            system: context.graphIdentifierSystem,
            value: "\(sourceUUID)|\(role)"
        )
    }

    private static func observation(
        for sample: HKSample,
        binding: HealthKitFHIRBinding,
        context: HealthKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        let contract = binding.contract
        var observation = Observation(
            code: CodeableConcept(coding: [
                Coding(
                    code: contract.code.code.asFHIRStringPrimitive(),
                    display: measurementDisplay(contract).asFHIRStringPrimitive(),
                    system: FHIRPrimitive(FHIRURI(stringLiteral: contract.code.system))
                ),
                Coding(
                    code: sample.sampleType.identifier.asFHIRStringPrimitive(),
                    display: HealthKitFHIRCatalog.entry(for: sample)?.title.asFHIRStringPrimitive(),
                    system: GroveFHIRCanonical.healthKitSourceType
                )
            ]),
            status: FHIRPrimitive(.final)
        )
        observation.meta = Meta(profile: contract.profiles)
        observation.subject = context.subject
        observation.issued = FHIRPrimitive(try Instant(date: context.conversionInstant))
        observation.category = category(for: contract.id).map { [CodeableConcept(coding: [$0])] }
        observation.method = contract.method.map { method in
            CodeableConcept(coding: [Coding(
                code: method.code.asFHIRStringPrimitive(),
                display: method.display.asFHIRStringPrimitive(),
                system: GroveFHIRCanonical.aggregationMethodCodeSystem
            )])
        }
        try applyEffective(to: &observation, sample: sample, contract: contract)
        try applyResult(to: &observation, sample: sample, binding: binding, contract: contract)
        try applyHeartRateMotionContext(to: &observation, sample: sample)
        try applyInsulinDeliveryReason(to: &observation, sample: sample)
        try applyMenstrualCycleStart(to: &observation, sample: sample, contract: contract)
        applyObservationGraphContext(
            to: &observation,
            sample: sample,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        return observation
    }

    private static func applyResult(
        to observation: inout Observation,
        sample: HKSample,
        binding: HealthKitFHIRBinding,
        contract: HealthKitFHIRObservationContract
    ) throws {
        if case .bloodPressure = binding {
            guard let correlation = sample as? HKCorrelation else {
                throw GroveHealthKitFHIRError.invalidValue
            }
            observation.component = try bloodPressureComponents(correlation, contract: contract)
            return
        }
        observation.value = try result(for: binding, sample: sample, contract: contract)
    }

    // The closed binding dispatch is intentionally spelled as a single exhaustive switch.
    // swiftlint:disable:next cyclomatic_complexity
    private static func result(
        for binding: HealthKitFHIRBinding,
        sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> Observation.ValueX {
        switch binding {
        case let .quantity(_, unit):
            .quantity(try fhirQuantity(
                value: try quantitySample(sample).quantity.doubleValue(for: unit),
                contract: quantityContract(contract)
            ))
        case .percent:
            .quantity(try fhirQuantity(
                value: try quantitySample(sample).quantity.doubleValue(for: .percent()) * 100,
                contract: quantityContract(contract)
            ))
        case .sessionRate:
            .quantity(try sessionRateValue(sample, contract: contract))
        case .sessionDuration:
            .quantity(try sessionDurationValue(sample, contract: contract))
        case .assessmentScore:
            .quantity(try assessmentScoreValue(sample, contract: contract))
        case .sleepStage:
            .codeableConcept(try sleepStageValue(sample, contract: contract))
        case .severity:
            .codeableConcept(try severityValue(sample, contract: contract))
        case .presence:
            .codeableConcept(try presenceValue(sample, contract: contract))
        case let .categoryValue(_, absorption):
            .codeableConcept(try absorbedCategoryValue(sample, absorption: absorption, contract: contract))
        case .fixedCode:
            .codeableConcept(try fixedCodeValue(sample, contract: contract))
        case .sexualActivity:
            .codeableConcept(try sexualActivityValue(sample, contract: contract))
        case .bloodPressure:
            throw GroveHealthKitFHIRError.invalidValue
        }
    }

    private static func sessionRateValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> Quantity {
        let quantitySample = try quantitySample(sample)
        let hours = quantitySample.endDate.timeIntervalSince(quantitySample.startDate) / 3_600
        return try fhirQuantity(
            value: quantitySample.quantity.doubleValue(for: .count()) / hours,
            contract: quantityContract(contract)
        )
    }

    private static func assessmentScoreValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> Quantity {
        guard let assessment = sample as? HKScoredAssessment else {
            throw GroveHealthKitFHIRError.invalidValue
        }
        return try fhirQuantity(value: Double(assessment.score), contract: quantityContract(contract))
    }

    private static func sleepStageValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> CodeableConcept {
        let stage = try sleepStage(try categorySample(sample).value, sampleType: sample.sampleType.identifier)
        return CodeableConcept(coding: [
            Coding(
                code: stage.sharedCode.asFHIRStringPrimitive(),
                display: stage.sharedDisplay.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: try resultCodeSystem(contract)))
            ),
            Coding(
                code: stage.sourceCode.asFHIRStringPrimitive(),
                display: stage.sourceDisplay.asFHIRStringPrimitive(),
                system: GroveFHIRCanonical.healthKitSleepAnalysis
            )
        ])
    }

    static func quantitySample(_ sample: HKSample) throws -> HKQuantitySample {
        guard let quantitySample = sample as? HKQuantitySample else {
            throw GroveHealthKitFHIRError.invalidValue
        }
        return quantitySample
    }

    static func categorySample(_ sample: HKSample) throws -> HKCategorySample {
        guard let categorySample = sample as? HKCategorySample else {
            throw GroveHealthKitFHIRError.invalidValue
        }
        return categorySample
    }

    static func quantityContract(
        _ contract: HealthKitFHIRObservationContract
    ) throws -> GroveFHIRQuantityContract {
        guard let quantity = contract.quantity else {
            throw GroveHealthKitFHIRError.invalidValue
        }
        return quantity
    }

    static func resultCodeSystem(_ contract: HealthKitFHIRObservationContract) throws -> String {
        guard let resultCodeSystem = contract.resultCodeSystem else {
            throw GroveHealthKitFHIRError.missingNormativeCode(contract.id)
        }
        return resultCodeSystem
    }

    private static func applyObservationGraphContext(
        to observation: inout Observation,
        sample: HKSample,
        context: HealthKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) {
        applyGraphContext(
            to: &observation,
            context: context,
            graphContext: HealthKitECGGraphContext(
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            ),
            wasUserEntered: (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true
        )
    }

    private static func applyEffective(
        to observation: inout Observation,
        sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws {
        let timeZone = try healthKitTimeZone(for: sample)
        switch contract.effective {
        case .dateTime:
            observation.effective = .dateTime(FHIRPrimitive(try HealthKitFHIRMobileCanonicalization.effectiveDateTime(
                sample.startDate,
                timeZone: timeZone
            )))
        case .period:
            guard sample.endDate > sample.startDate else {
                throw GroveHealthKitFHIRError.invalidEffectivePeriod(sampleType: sample.sampleType.identifier)
            }
            observation.effective = .period(Period(
                end: FHIRPrimitive(try HealthKitFHIRMobileCanonicalization.effectiveDateTime(
                    sample.endDate,
                    timeZone: timeZone
                )),
                start: FHIRPrimitive(try HealthKitFHIRMobileCanonicalization.effectiveDateTime(
                    sample.startDate,
                    timeZone: timeZone
                ))
            ))
        }
        if sample.metadata?[HKMetadataKeyTimeZone] != nil {
            attachTimeZoneExtension(to: &observation, identifier: timeZone.identifier)
        }
    }

    private static func attachTimeZoneExtension(to observation: inout Observation, identifier: String) {
        let timeZoneExtension = Extension(
            url: GroveFHIRCanonical.timezone,
            value: .code(identifier.asFHIRStringPrimitive())
        )
        switch observation.effective {
        case .dateTime(var dateTime):
            dateTime.append(extension: timeZoneExtension, behaviour: .replace)
            observation.effective = .dateTime(dateTime)
        case .period(var period):
            if var start = period.start {
                start.append(extension: timeZoneExtension, behaviour: .replace)
                period.start = start
            }
            if var end = period.end {
                end.append(extension: timeZoneExtension, behaviour: .replace)
                period.end = end
            }
            observation.effective = .period(period)
        default:
            break
        }
    }

    static func fhirQuantity(
        value: Double,
        contract: GroveFHIRQuantityContract
    ) throws -> Quantity {
        Quantity(
            code: contract.code.asFHIRStringPrimitive(),
            system: FHIRPrimitive(FHIRURI(stringLiteral: contract.system)),
            unit: contract.unit.asFHIRStringPrimitive(),
            value: try HealthKitFHIRMobileCanonicalization.scalarDecimal(value)
        )
    }

    private static func bloodPressureComponents(
        _ correlation: HKCorrelation,
        contract: HealthKitFHIRObservationContract
    ) throws -> [ObservationComponent] {
        try contract.components.map { component in
            let healthKitIdentifier: HKQuantityTypeIdentifier = component.id == "systolic"
                ? .bloodPressureSystolic
                : .bloodPressureDiastolic
            guard let sample = correlation.objects
                .compactMap({ $0 as? HKQuantitySample })
                .first(where: { $0.quantityType.identifier == healthKitIdentifier.rawValue }) else {
                throw GroveHealthKitFHIRError.missingRequiredComponent(
                    sampleType: correlation.correlationType.identifier,
                    component: component.id
                )
            }
            guard let componentQuantity = component.quantity else {
                throw GroveHealthKitFHIRError.invalidValue
            }
            return ObservationComponent(
                code: CodeableConcept(coding: [Coding(
                    code: component.code.asFHIRStringPrimitive(),
                    system: FHIRPrimitive(FHIRURI(stringLiteral: component.system))
                )]),
                value: .quantity(try fhirQuantity(
                    value: sample.quantity.doubleValue(for: .millimeterOfMercury()),
                    contract: componentQuantity
                ))
            )
        }
    }

    private static func sleepStage(
        _ value: Int,
        sampleType: String
    ) throws -> HealthKitSleepStage {
        switch value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            HealthKitSleepStage(
                sharedCode: "in-bed",
                sharedDisplay: "In bed",
                sourceCode: "inBed",
                sourceDisplay: "In bed"
            )
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            HealthKitSleepStage(
                sharedCode: "asleep-unspecified",
                sharedDisplay: "Asleep, unspecified stage",
                sourceCode: "asleepUnspecified",
                sourceDisplay: "Asleep, unspecified"
            )
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            HealthKitSleepStage(
                sharedCode: "awake",
                sharedDisplay: "Awake",
                sourceCode: "awake",
                sourceDisplay: "Awake"
            )
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            HealthKitSleepStage(
                sharedCode: "light",
                sharedDisplay: "Light sleep",
                sourceCode: "asleepCore",
                sourceDisplay: "Asleep, core"
            )
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            HealthKitSleepStage(
                sharedCode: "deep",
                sharedDisplay: "Deep sleep",
                sourceCode: "asleepDeep",
                sourceDisplay: "Asleep, deep"
            )
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            HealthKitSleepStage(
                sharedCode: "rem",
                sharedDisplay: "REM sleep",
                sourceCode: "asleepREM",
                sourceDisplay: "Asleep, REM"
            )
        default:
            throw GroveHealthKitFHIRError.unsupportedSampleValue(
                sampleType: sampleType,
                value: value
            )
        }
    }

    private static func measurementDisplay(_ contract: HealthKitFHIRObservationContract) -> String {
        contract.code.display ?? measurementDisplays[contract.id, default: contract.id]
    }

    private static func category(for id: String) -> Coding? {
        let code: (String, String)? = switch id {
        case "heart-rate", "body-weight", "blood-pressure", "body-temperature",
             "respiratory-rate", "oxygen-saturation", "body-height", "body-mass-index":
            ("vital-signs", "Vital Signs")
        case "step-count", "distance", "active-energy", "sleep-stage":
            ("activity", "Activity")
        default:
            nil
        }
        return code.map { code, display in
            Coding(
                code: code.asFHIRStringPrimitive(),
                display: display.asFHIRStringPrimitive(),
                system: observationCategory
            )
        }
    }

    private static func applyHeartRateMotionContext(
        to observation: inout Observation,
        sample: HKSample
    ) throws {
        guard sample.sampleType.identifier == HKQuantityTypeIdentifier.heartRate.rawValue,
              let raw = sample.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber else {
            return
        }
        let coding: Coding = switch raw.intValue {
        case 0:
            Coding(code: "not-set", display: "Not Set", system: GroveFHIRCanonical.healthKitHeartRateMotionContext)
        case 1:
            Coding(code: "sedentary", display: "Sedentary", system: GroveFHIRCanonical.healthKitHeartRateMotionContext)
        case 2:
            Coding(code: "active", display: "Active", system: GroveFHIRCanonical.healthKitHeartRateMotionContext)
        default:
            throw GroveHealthKitFHIRError.unsupportedMetadataValue(
                key: HKMetadataKeyHeartRateMotionContext,
                value: raw.stringValue
            )
        }
        let component = ObservationComponent(
            code: CodeableConcept(coding: [Coding(
                code: HKMetadataKeyHeartRateMotionContext.asFHIRStringPrimitive(),
                display: "Heart Rate Motion Context".asFHIRStringPrimitive(),
                system: GroveFHIRCanonical.healthKitMetadataKey
            )]),
            value: .codeableConcept(CodeableConcept(coding: [coding]))
        )
        observation.component = (observation.component ?? []) + [component]
    }

    private static func applyInsulinDeliveryReason(
        to observation: inout Observation,
        sample: HKSample
    ) throws {
        guard sample.sampleType.identifier == HKQuantityTypeIdentifier.insulinDelivery.rawValue else {
            return
        }
        guard let raw = sample.metadata?[HKMetadataKeyInsulinDeliveryReason] as? NSNumber else {
            throw GroveHealthKitFHIRError.missingRequiredMetadata(
                sampleType: sample.sampleType.identifier,
                key: HKMetadataKeyInsulinDeliveryReason
            )
        }
        let coding: Coding = switch raw.intValue {
        case HKInsulinDeliveryReason.basal.rawValue:
            Coding(code: "basal", display: "Basal", system: GroveFHIRCanonical.healthKitInsulinDeliveryReason)
        case HKInsulinDeliveryReason.bolus.rawValue:
            Coding(code: "bolus", display: "Bolus", system: GroveFHIRCanonical.healthKitInsulinDeliveryReason)
        default:
            throw GroveHealthKitFHIRError.unsupportedMetadataValue(
                key: HKMetadataKeyInsulinDeliveryReason,
                value: raw.stringValue
            )
        }
        let component = ObservationComponent(
            code: CodeableConcept(coding: [Coding(
                code: HKMetadataKeyInsulinDeliveryReason.asFHIRStringPrimitive(),
                display: "Insulin Delivery Reason".asFHIRStringPrimitive(),
                system: GroveFHIRCanonical.healthKitMetadataKey
            )]),
            value: .codeableConcept(CodeableConcept(coding: [coding]))
        )
        observation.component = (observation.component ?? []) + [component]
    }

    private static func applyMenstrualCycleStart(
        to observation: inout Observation,
        sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws {
        guard sample.sampleType.identifier == HKCategoryTypeIdentifier.menstrualFlow.rawValue else {
            return
        }
        let component = try menstrualCycleStartComponent(
            metadata: sample.metadata ?? [:],
            sampleType: sample.sampleType.identifier,
            contract: contract
        )
        observation.component = (observation.component ?? []) + [component]
    }

    /// HealthKit makes cycle-start metadata mandatory on every menstrual-flow sample, so its absence fails closed.
    ///
    /// HealthKit rejects a sample without the key at construction, so only this guard can prove the
    /// converter never silently drops it.
    static func menstrualCycleStartComponent(
        metadata: [String: Any],
        sampleType: String,
        contract: HealthKitFHIRObservationContract
    ) throws -> ObservationComponent {
        guard let contractComponent = contract.components.first(where: { $0.id == "cycleStart" }),
              let resultCodeSystem = contractComponent.resultCodeSystem else {
            throw GroveHealthKitFHIRError.missingRequiredComponent(
                sampleType: sampleType,
                component: "cycleStart"
            )
        }
        let cycleStart: Bool
        switch metadata[HKMetadataKeyMenstrualCycleStart] {
        case nil:
            throw GroveHealthKitFHIRError.missingRequiredMetadata(
                sampleType: sampleType,
                key: HKMetadataKeyMenstrualCycleStart
            )
        case let value as Bool:
            cycleStart = value
        case let other?:
            throw GroveHealthKitFHIRError.unsupportedMetadataValue(
                key: HKMetadataKeyMenstrualCycleStart,
                value: String(describing: other)
            )
        }
        let code = cycleStart ? "cycle-start" : "not-cycle-start"
        guard let resultCode = contractComponent.resultCodes.first(where: { $0.code == code }) else {
            throw GroveHealthKitFHIRError.missingNormativeCode(contract.id)
        }
        return ObservationComponent(
            code: CodeableConcept(coding: [Coding(
                code: contractComponent.code.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: contractComponent.system))
            )]),
            value: .codeableConcept(CodeableConcept(coding: [Coding(
                code: resultCode.code.asFHIRStringPrimitive(),
                display: resultCode.display.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: resultCodeSystem))
            )]))
        )
    }


    static func applyManualRecordingMethod(to observation: inout Observation) {
        observation.append(
            extension: Extension(
                url: GroveFHIRCanonical.recordingMethod,
                value: .coding(Coding(
                    code: "manual-entry",
                    display: "Manual entry",
                    system: GroveFHIRCanonical.recordingMethodCodeSystem
                ))
            ),
            behaviour: .replace
        )
    }
}

#endif
