//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


#if canImport(HealthKit)

import Foundation


/// Product identity of the application performing a HealthKit-to-FHIR conversion.
public struct HealthKitFHIRApplication: Hashable, Sendable {
    /// The identity of the running application, read from its main bundle.
    ///
    /// A host without a bundle identifier — a command-line tool, a bare test runner — has no
    /// application identity to state. Rather than trap in a default argument, this yields an
    /// identity that conversion rejects as ``GroveHealthKitFHIRError/invalidConverterApplication``,
    /// so such a host fails through the same typed path as any other invalid context.
    public static var main: HealthKitFHIRApplication {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        let identifier = bundle.bundleIdentifier ?? ""
        let name = (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String ?? identifier
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = (info["CFBundleVersion"] as? String).map { " (\($0))" } ?? ""
        return HealthKitFHIRApplication(name: name, bundleIdentifier: identifier, version: version + build)
    }

    public let name: String
    public let bundleIdentifier: String
    public let version: String

    /// The identifier namespace this application owns for graph nodes it mints.
    ///
    /// A bundle identifier is globally unique and stable across releases, so it is a valid
    /// default namespace for a deployment that does not yet own a server URL. Override it with
    /// ``HealthKitFHIRConversionContext/graphIdentifierSystem`` once one exists.
    public var graphIdentifierSystem: String {
        "urn:grove:healthkit-graph:\(bundleIdentifier)"
    }

    public init(name: String, bundleIdentifier: String, version: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
    }
}

#endif
