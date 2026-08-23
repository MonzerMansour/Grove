//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Public source-neutral record types are intentionally grouped as one contract inventory.
// swiftlint:disable file_types_order type_contents_order

public import Foundation
public import GroveFHIRContract
public import ModelsR4


/// Contract-level failures raised before Grove emits a Sensor FHIR resource.
public enum SensorFHIRRecordError: Error, Equatable, Sendable {
    case emptySourceTypeIdentifier
    case incompleteCode(system: String, code: String)
    case emptySamples
    case invalidDimensions(Int)
    case sampleCountNotDivisibleByDimensions(sampleCount: Int, dimensions: Int)
    case nonFiniteSample(index: Int)
    case invalidSamplingPeriod(Double)
    case invalidEffectivePeriod
    case emptyECGChannels
    case mismatchedECGChannelLength(expected: Int, actual: Int, channel: Int)
    case duplicateECGLead(system: String, code: String)
    case invalidAttachmentTitle
    case invalidContentType
    case invalidRecordingFormat
    case emptyPayload
    case invalidSidecarPath(String)
    case payloadTooLarge(byteCount: Int)
    case rawPayloadAdmissionRequired
}


/// A complete coded concept used to name a sensor stream or ECG channel.
public struct SensorFHIRCode: Hashable, Sendable {
    public let system: String
    public let code: String
    public let display: String?

    public init(system: String, code: String, display: String? = nil) throws {
        guard !system.isEmpty,
              !code.isEmpty,
              let url = URL(string: system),
              url.scheme != nil,
              url.absoluteString == system else {
            throw SensorFHIRRecordError.incompleteCode(system: system, code: code)
        }
        self.system = system
        self.code = code
        self.display = display
    }

    var coding: Coding {
        Coding(
            code: code.asFHIRStringPrimitive(),
            display: display?.asFHIRStringPrimitive(),
            system: FHIRPrimitive(FHIRURI(stringLiteral: system))
        )
    }

    var concept: CodeableConcept {
        CodeableConcept(coding: [coding])
    }
}


/// One source-neutral, uniformly sampled numeric time series.
public struct GroveSensorSampledDataRecord: Sendable {
    public let identifier: GroveFHIRBusinessIdentifier
    public let sourceTypeIdentifier: String
    public let code: SensorFHIRCode
    public let start: Date
    public let end: Date
    public let samples: [Double]
    public let dimensions: Int
    public let periodMilliseconds: Double
    public let origin: Double
    public let unitCode: String
    public let unitDisplay: String?

    let adapterProfile: FHIRPrimitive<Canonical>?

    public init(
        identifier: GroveFHIRBusinessIdentifier,
        sourceTypeIdentifier: String,
        code: SensorFHIRCode,
        start: Date,
        end: Date,
        samples: [Double],
        dimensions: Int = 1,
        periodMilliseconds: Double,
        origin: Double = 0,
        unitCode: String,
        unitDisplay: String? = nil
    ) throws {
        try self.init(
            identifier: identifier,
            sourceTypeIdentifier: sourceTypeIdentifier,
            code: code,
            start: start,
            end: end,
            samples: samples,
            dimensions: dimensions,
            periodMilliseconds: periodMilliseconds,
            origin: origin,
            unitCode: unitCode,
            unitDisplay: unitDisplay,
            adapterProfile: nil
        )
    }

    init(
        identifier: GroveFHIRBusinessIdentifier,
        sourceTypeIdentifier: String,
        code: SensorFHIRCode,
        start: Date,
        end: Date,
        samples: [Double],
        dimensions: Int,
        periodMilliseconds: Double,
        origin: Double,
        unitCode: String,
        unitDisplay: String?,
        adapterProfile: FHIRPrimitive<Canonical>?
    ) throws {
        guard !sourceTypeIdentifier.isEmpty else {
            throw SensorFHIRRecordError.emptySourceTypeIdentifier
        }
        guard !samples.isEmpty else {
            throw SensorFHIRRecordError.emptySamples
        }
        guard dimensions > 0, dimensions <= Int(Int32.max) else {
            throw SensorFHIRRecordError.invalidDimensions(dimensions)
        }
        guard samples.count.isMultiple(of: dimensions) else {
            throw SensorFHIRRecordError.sampleCountNotDivisibleByDimensions(
                sampleCount: samples.count,
                dimensions: dimensions
            )
        }
        guard periodMilliseconds.isFinite, periodMilliseconds > 0 else {
            throw SensorFHIRRecordError.invalidSamplingPeriod(periodMilliseconds)
        }
        let frameCount = samples.count / dimensions
        guard start <= end, frameCount == 1 || start < end else {
            throw SensorFHIRRecordError.invalidEffectivePeriod
        }
        guard origin.isFinite else {
            throw SensorFHIRRecordError.nonFiniteSample(index: -1)
        }
        if let index = samples.firstIndex(where: { !$0.isFinite }) {
            throw SensorFHIRRecordError.nonFiniteSample(index: index)
        }
        guard !unitCode.isEmpty else {
            throw SensorFHIRRecordError.incompleteCode(system: Self.ucum, code: unitCode)
        }
        self.identifier = identifier
        self.sourceTypeIdentifier = sourceTypeIdentifier
        self.code = code
        self.start = start
        self.end = end
        self.samples = samples
        self.dimensions = dimensions
        self.periodMilliseconds = periodMilliseconds
        self.origin = origin
        self.unitCode = unitCode
        self.unitDisplay = unitDisplay
        self.adapterProfile = adapterProfile
    }
}


/// One uniformly sampled ECG lead channel, expressed in millivolts.
public struct GroveSensorECGChannel: Sendable {
    public let lead: SensorFHIRCode
    public let millivolts: [Double]
    public let originMillivolts: Double

    public init(
        lead: SensorFHIRCode,
        millivolts: [Double],
        originMillivolts: Double = 0
    ) throws {
        guard !millivolts.isEmpty else {
            throw SensorFHIRRecordError.emptySamples
        }
        guard originMillivolts.isFinite else {
            throw SensorFHIRRecordError.nonFiniteSample(index: -1)
        }
        if let index = millivolts.firstIndex(where: { !$0.isFinite }) {
            throw SensorFHIRRecordError.nonFiniteSample(index: index)
        }
        self.lead = lead
        self.millivolts = millivolts
        self.originMillivolts = originMillivolts
    }
}


/// A source-neutral ECG recording with one or more uniformly sampled lead channels.
public struct GroveSensorECGRecord: Sendable {
    public let identifier: GroveFHIRBusinessIdentifier
    public let sourceTypeIdentifier: String
    public let start: Date
    public let end: Date
    public let periodMilliseconds: Double
    public let channels: [GroveSensorECGChannel]

    let adapterProfile: FHIRPrimitive<Canonical>?

    public init(
        identifier: GroveFHIRBusinessIdentifier,
        sourceTypeIdentifier: String,
        start: Date,
        end: Date,
        periodMilliseconds: Double,
        channels: [GroveSensorECGChannel]
    ) throws {
        try self.init(
            identifier: identifier,
            sourceTypeIdentifier: sourceTypeIdentifier,
            start: start,
            end: end,
            periodMilliseconds: periodMilliseconds,
            channels: channels,
            adapterProfile: nil
        )
    }

    init(
        identifier: GroveFHIRBusinessIdentifier,
        sourceTypeIdentifier: String,
        start: Date,
        end: Date,
        periodMilliseconds: Double,
        channels: [GroveSensorECGChannel],
        adapterProfile: FHIRPrimitive<Canonical>?
    ) throws {
        guard !sourceTypeIdentifier.isEmpty else {
            throw SensorFHIRRecordError.emptySourceTypeIdentifier
        }
        guard start <= end else {
            throw SensorFHIRRecordError.invalidEffectivePeriod
        }
        guard periodMilliseconds.isFinite, periodMilliseconds > 0 else {
            throw SensorFHIRRecordError.invalidSamplingPeriod(periodMilliseconds)
        }
        guard !channels.isEmpty else {
            throw SensorFHIRRecordError.emptyECGChannels
        }
        let expectedSampleCount = channels[0].millivolts.count
        for (index, channel) in channels.enumerated() where channel.millivolts.count != expectedSampleCount {
            throw SensorFHIRRecordError.mismatchedECGChannelLength(
                expected: expectedSampleCount,
                actual: channel.millivolts.count,
                channel: index
            )
        }
        var leads: Set<SensorFHIRCode> = []
        for channel in channels where !leads.insert(channel.lead).inserted {
            throw SensorFHIRRecordError.duplicateECGLead(
                system: channel.lead.system,
                code: channel.lead.code
            )
        }
        guard expectedSampleCount == 1 || start < end else {
            throw SensorFHIRRecordError.invalidEffectivePeriod
        }
        self.identifier = identifier
        self.sourceTypeIdentifier = sourceTypeIdentifier
        self.start = start
        self.end = end
        self.periodMilliseconds = periodMilliseconds
        self.channels = channels
        self.adapterProfile = adapterProfile
    }
}


/// An externally encoded or embedded native sensor recording.
///
/// Construction fails closed unless the caller supplies exactly one
/// ``GroveSensorRawPayloadAdmission``. Grove consumes that producer-side assertion during
/// initialization and does not retain or serialize it into the FHIR graph.
public struct GroveSensorRecordingDocument: Sendable {
    /// Where the native recording bytes travel.
    public enum Payload: Sendable {
        case inline(Data)
        case sidecar(path: String, bytes: Data)
    }

    public let identifier: GroveFHIRBusinessIdentifier
    public let sourceTypeIdentifier: String
    public let type: SensorFHIRCode
    public let title: String
    public let contentType: String
    public let format: String
    public let payload: Payload
    public let related: [GroveFHIRBusinessIdentifier]

    let adapterProfile: FHIRPrimitive<Canonical>?

    public init(
        identifier: GroveFHIRBusinessIdentifier,
        sourceTypeIdentifier: String,
        type: SensorFHIRCode,
        title: String,
        contentType: String,
        format: String,
        payload: Payload,
        rawPayloadAdmission: GroveSensorRawPayloadAdmission?,
        related: [GroveFHIRBusinessIdentifier] = []
    ) throws {
        try self.init(
            identifier: identifier,
            sourceTypeIdentifier: sourceTypeIdentifier,
            type: type,
            title: title,
            contentType: contentType,
            format: format,
            payload: payload,
            rawPayloadAdmission: rawPayloadAdmission,
            related: related,
            adapterProfile: nil
        )
    }

    init(
        identifier: GroveFHIRBusinessIdentifier,
        sourceTypeIdentifier: String,
        type: SensorFHIRCode,
        title: String,
        contentType: String,
        format: String,
        payload: Payload,
        rawPayloadAdmission: GroveSensorRawPayloadAdmission?,
        related: [GroveFHIRBusinessIdentifier],
        adapterProfile: FHIRPrimitive<Canonical>?
    ) throws {
        guard !sourceTypeIdentifier.isEmpty else {
            throw SensorFHIRRecordError.emptySourceTypeIdentifier
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorFHIRRecordError.invalidAttachmentTitle
        }
        guard Self.isValidContentType(contentType) else {
            throw SensorFHIRRecordError.invalidContentType
        }
        guard !format.isEmpty else {
            throw SensorFHIRRecordError.invalidRecordingFormat
        }
        let bytes: Data
        switch payload {
        case .inline(let data), .sidecar(_, let data):
            bytes = data
        }
        guard !bytes.isEmpty else {
            throw SensorFHIRRecordError.emptyPayload
        }
        if case .sidecar(let path, _) = payload {
            guard Self.isRelativeSidecarPath(path) else {
                throw SensorFHIRRecordError.invalidSidecarPath(path)
            }
        }
        guard rawPayloadAdmission != nil else {
            throw SensorFHIRRecordError.rawPayloadAdmissionRequired
        }
        self.identifier = identifier
        self.sourceTypeIdentifier = sourceTypeIdentifier
        self.type = type
        self.title = title
        self.contentType = contentType
        self.format = format
        self.payload = payload
        self.related = related
        self.adapterProfile = adapterProfile
    }

    static func isRelativeSidecarPath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".."
              }),
              let components = URLComponents(string: path),
              components.scheme == nil,
              components.host == nil,
              components.query == nil,
              components.fragment == nil,
              components.percentEncodedPath == path else {
            return false
        }
        return true
    }

    private static func isValidContentType(_ contentType: String) -> Bool {
        let parts = contentType.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return false
        }
        let tokenCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "!#$&^_.+-"))
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy(tokenCharacters.contains)
        }
    }
}


/// One record accepted by the source-neutral Sensor FHIR converter.
public enum SensorFHIRRecord: Sendable {
    case sampledData(GroveSensorSampledDataRecord)
    case electrocardiogram(GroveSensorECGRecord)
    case recordingDocument(GroveSensorRecordingDocument)

    public var identifier: GroveFHIRBusinessIdentifier {
        switch self {
        case .sampledData(let record): record.identifier
        case .electrocardiogram(let record): record.identifier
        case .recordingDocument(let record): record.identifier
        }
    }

    public var sourceTypeIdentifier: String {
        switch self {
        case .sampledData(let record): record.sourceTypeIdentifier
        case .electrocardiogram(let record): record.sourceTypeIdentifier
        case .recordingDocument(let record): record.sourceTypeIdentifier
        }
    }
}


extension GroveSensorSampledDataRecord {
    fileprivate static let ucum = "http://unitsofmeasure.org"
}
