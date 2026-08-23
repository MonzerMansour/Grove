//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


#if canImport(HealthKit)

public import GroveFHIRContract
public import ModelsR4


/// Complete business identities of one emitted exchange graph.
public struct HealthKitFHIRGraphIdentifiers: Hashable, Sendable {
    public let bundle: GroveFHIRBusinessIdentifier
    public let observation: GroveFHIRBusinessIdentifier
    public let recordingDevice: GroveFHIRBusinessIdentifier?
    public let converterApplication: GroveFHIRBusinessIdentifier
    public let sourceAuthor: GroveFHIRBusinessIdentifier?
    public let provenance: GroveFHIRBusinessIdentifier
}


/// One complete conversion graph.
///
/// Resources have no logical `Resource.id` unless the caller supplied a repository id.
/// Deterministic UUIDv5 Bundle fullUrls connect graph entries.
public struct HealthKitFHIRConversion: Sendable {
    public let sourceIdentifier: Identifier
    public let graphIdentifiers: HealthKitFHIRGraphIdentifiers
    public let observation: Observation
    public let recordingDevice: Device?
    public let converterApplication: Device
    public let sourceAuthor: Device?
    public let provenance: Provenance
    public let bundle: ModelsR4.Bundle
}

#endif
