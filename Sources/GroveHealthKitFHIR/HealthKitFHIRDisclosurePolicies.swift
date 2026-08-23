//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


#if canImport(HealthKit)


/// Explicit interpretation of `HKSourceRevision.source` for one conversion.
///
/// HealthKit exposes no reliable application/device discriminator. The converter never
/// guesses from a name, identifier shape, or product type.
public enum HealthKitFHIRSourceActor: Hashable, Sendable {
    /// Omit the source author from Provenance.
    case omit
    /// The caller has established that the source is an application.
    case application
    /// The caller has established that the source is a device. The opaque HealthKit
    /// source identifier is disclosed only when explicitly authorized.
    case device(discloseIdentifier: Bool)
}


/// Controls disclosure of globally identifying recording-device information.
///
/// Selecting ``authorizedUDI`` is an explicit caller attestation that disclosing the
/// HealthKit UDI is necessary for the deployment and has been authorized. This is
/// independent of the deployment-local identifier namespace configured on
/// ``HealthKitFHIRConversionContext``.
public enum HealthKitFHIRUDIDisclosurePolicy: Hashable, Sendable {
    /// Omit globally identifying device information. This is the privacy-preserving default.
    case omit
    /// Disclose the UDI supplied by HealthKit after the caller has established necessity
    /// and authorization.
    case authorizedUDI
}


/// Controls disclosure of the complete source revision attached to a correlated ECG symptom.
///
/// The bundle identifier, product type, software version, and operating-system version can
/// be linkable. This policy is therefore independent of recording-device and UDI disclosure.
public enum HealthKitFHIRSourceDisclosurePolicy: Hashable, Sendable {
    /// Do not disclose correlated-symptom source revision fields. This is the default.
    /// Because the ECG contract requires those fields, correlated symptoms fail closed.
    case omit
    /// The caller has established necessity and authorization to disclose every required
    /// correlated-symptom `HKSourceRevision` field.
    case authorized
}

#endif
