//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


#if canImport(HealthKit)

public import Foundation
public import GroveFHIRContract
public import ModelsR4


/// Optional logical ids already assigned by a FHIR repository.
///
/// These are never derived from HealthKit identities or Bundle UUID URNs.
public struct HealthKitFHIRRepositoryIDs: Hashable, Sendable {
    public let bundle: GroveFHIRRepositoryID?
    public let observation: GroveFHIRRepositoryID?
    public let recordingDevice: GroveFHIRRepositoryID?
    public let converterApplication: GroveFHIRRepositoryID?
    public let sourceAuthor: GroveFHIRRepositoryID?
    public let provenance: GroveFHIRRepositoryID?

    public init(
        bundle: GroveFHIRRepositoryID? = nil,
        observation: GroveFHIRRepositoryID? = nil,
        recordingDevice: GroveFHIRRepositoryID? = nil,
        converterApplication: GroveFHIRRepositoryID? = nil,
        sourceAuthor: GroveFHIRRepositoryID? = nil,
        provenance: GroveFHIRRepositoryID? = nil
    ) {
        self.bundle = bundle
        self.observation = observation
        self.recordingDevice = recordingDevice
        self.converterApplication = converterApplication
        self.sourceAuthor = sourceAuthor
        self.provenance = provenance
    }
}


/// Explicit inputs needed to make a reproducible, auditable FHIR graph.
public struct HealthKitFHIRConversionContext: Sendable {
    public let subject: Reference
    public let converter: HealthKitFHIRApplication
    /// Deployment-owned identifier namespace for graph nodes that have no natural identity.
    ///
    /// A sample's Observation is identified by its HealthKit object UUID, but the Bundle, the
    /// conversion Provenance, and derived Device resources exist only because of this export.
    /// Their business identifiers are minted deterministically inside this namespace, so the
    /// same conversion always produces the same graph and re-sends deduplicate on the server.
    ///
    /// Defaults to ``HealthKitFHIRApplication/graphIdentifierSystem``, which is derived from the
    /// converting app's bundle identifier. Pass one stable URL you own once the deployment has a
    /// server namespace, for example `https://mystudy.example.org/fhir/identifiers/mobile-graph`.
    ///
    /// - Note: See <doc:ConfiguringAConversion> for what an identifier namespace is in FHIR.
    public let graphIdentifierSystem: String
    public let sourceActor: HealthKitFHIRSourceActor
    public let converterWasGateway: Bool
    /// The instant of this conversion event.
    ///
    /// Written to `Observation.issued`, `Provenance.occurred`/`recorded`, and `Bundle.timestamp`;
    /// each sample's own measurement time always comes from the sample and lands in
    /// `Observation.effective`. Defaults to the wall clock; pass a fixed instant to make a
    /// conversion reproducible.
    public let conversionInstant: Date
    /// Deployment-owned namespace that authorizes disclosure of an opaque, local
    /// `HKDevice.localIdentifier`. It does not authorize UDI disclosure.
    public let recordingDeviceIdentifierSystem: String?
    /// Explicit UDI disclosure policy. The default omits the UDI even when HealthKit
    /// supplies one.
    public let udiDisclosurePolicy: HealthKitFHIRUDIDisclosurePolicy
    /// Explicit policy for the linkable source-revision evidence required by correlated
    /// ECG symptoms.
    public let sourceRevisionDisclosurePolicy: HealthKitFHIRSourceDisclosurePolicy
    public let researchStudies: [Reference]
    public let repositoryIDs: HealthKitFHIRRepositoryIDs

    /// Creates a conversion context, deriving everything that can be read from the running app.
    ///
    /// Only ``subject`` has no local answer: nothing on the device knows who the receiving
    /// system thinks this data is about. See <doc:ConfiguringAConversion>.
    ///
    /// ```swift
    /// let context = HealthKitFHIRConversionContext(subject: Reference(reference: "Patient/example"))
    /// ```
    public init(
        subject: Reference,
        converter: HealthKitFHIRApplication = .main,
        graphIdentifierSystem: String? = nil,
        sourceActor: HealthKitFHIRSourceActor = .omit,
        converterWasGateway: Bool = false,
        conversionInstant: Date = .now,
        recordingDeviceIdentifierSystem: String? = nil,
        udiDisclosurePolicy: HealthKitFHIRUDIDisclosurePolicy = .omit,
        sourceRevisionDisclosurePolicy: HealthKitFHIRSourceDisclosurePolicy = .omit,
        researchStudies: [Reference] = [],
        repositoryIDs: HealthKitFHIRRepositoryIDs = .init()
    ) {
        self.subject = subject
        self.converter = converter
        self.graphIdentifierSystem = graphIdentifierSystem ?? converter.graphIdentifierSystem
        self.sourceActor = sourceActor
        self.converterWasGateway = converterWasGateway
        self.conversionInstant = conversionInstant
        self.recordingDeviceIdentifierSystem = recordingDeviceIdentifierSystem
        self.udiDisclosurePolicy = udiDisclosurePolicy
        self.sourceRevisionDisclosurePolicy = sourceRevisionDisclosurePolicy
        self.researchStudies = researchStudies
        self.repositoryIDs = repositoryIDs
    }
}

#endif
