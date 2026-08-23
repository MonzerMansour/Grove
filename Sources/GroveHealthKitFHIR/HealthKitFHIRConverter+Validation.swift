//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Every context check the converter runs before it mints an identifier.

#if canImport(HealthKit)

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import GroveHealthKit
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRConverter {
    static func validate(context: HealthKitFHIRConversionContext) throws(GroveHealthKitFHIRError) {
        // Checked first: an empty bundle identifier still yields a syntactically valid graph
        // namespace (`urn:grove:healthkit-graph:`), so nothing downstream would catch it. A host
        // can carry CFBundleName without CFBundleIdentifier, so the name check would not either.
        guard !context.converter.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GroveHealthKitFHIRError.invalidConverterApplication("bundleIdentifier")
        }
        guard !context.converter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GroveHealthKitFHIRError.invalidConverterApplication("name")
        }
        guard !context.converter.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GroveHealthKitFHIRError.invalidConverterApplication("version")
        }
        try validateIdentifierSystem(context.graphIdentifierSystem)
        if let system = context.recordingDeviceIdentifierSystem {
            try validateIdentifierSystem(system)
        }
        _ = try validateReference(
            reference: context.subject,
            field: "subject",
            expectedResourceType: "Patient"
        )
        var studyIdentities: Set<GroveFHIRTypedReferenceIdentity> = []
        for study in context.researchStudies {
            let identity = try validateReference(
                reference: study,
                field: "researchStudies",
                expectedResourceType: "ResearchStudy"
            )
            guard studyIdentities.insert(identity).inserted else {
                throw GroveHealthKitFHIRError.duplicateReference(field: "researchStudies")
            }
        }
    }

    private static func validateIdentifierSystem(_ system: String) throws(GroveHealthKitFHIRError) {
        do {
            _ = try GroveFHIRBusinessIdentifier(system: system, value: "validation")
        } catch {
            throw .invalidExchangeIdentity(String(describing: error))
        }
    }

    private static func validateReference(
        reference: Reference,
        field: String,
        expectedResourceType: String
    ) throws(GroveHealthKitFHIRError) -> GroveFHIRTypedReferenceIdentity {
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
}

#endif
