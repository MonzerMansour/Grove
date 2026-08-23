//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFHIRContract


/// A typed failure for one record; batch conversion never drops input silently.
public struct SensorFHIRRecordFailure: Error, Equatable, Sendable {
    public let sourceIdentifier: GroveFHIRBusinessIdentifier
    public let sourceTypeIdentifier: String
    public let reason: SensorFHIRConversionError
}


/// Why one source record could not be converted.
public enum SensorFHIRConversionError: Error, Equatable, Sendable {
    case invalidConverterApplication(String)
    case invalidExchangeIdentity(String)
    case repositoryIDWithoutRecordingDevice
    case payloadTooLarge(byteCount: Int)
    /// A required typed FHIR reference is empty or targets the wrong resource type.
    case invalidReference(field: String, expectedResourceType: String)
    /// A repeated reference would create ambiguous duplicate graph relationships.
    case duplicateReference(field: String)
    /// A dependency raised a failure this domain does not model, named by type.
    ///
    /// Only the type is carried: a failing FHIR date conversion describes itself with the exact
    /// instant it could not convert, and that instant identifies a participant.
    case unexpectedConversionFailure(String)
}


extension SensorFHIRConversionError {
    /// Narrows any conversion failure to this published domain, so the converter's typed
    /// throws stay exhaustive even when a dependency raises its own error.
    init(conversionFailure error: any Error) {
        switch error {
        case let error as SensorFHIRConversionError:
            self = error
        case let error as GroveFHIRExchangeIdentityError:
            self = .invalidExchangeIdentity(String(describing: error))
        default:
            self = .unexpectedConversionFailure(String(reflecting: type(of: error)))
        }
    }
}
