//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
public import Foundation


/// The published recording-device identity algorithm from `catalog/exchange-identity.json`.
///
/// A recording Device has no natural identifier, so without one every sample carries its own
/// Device resource and a single watch is stored once per reading. This digest gives one Device
/// per participant's recorder instead.
///
/// The subject partitions the key because a wearable belongs to a person: two participants
/// wearing the same model are two devices, which is what `Device` means in R4. Firmware and
/// software are deliberately absent — they change over a recorder's life, and each Observation
/// states the versions in force when it was recorded.
public enum GroveFHIRRecordingDeviceIdentity: Sendable {
    /// What a platform states about the recorder that produced a sample.
    public struct Recorder: Hashable, Sendable {
        public var manufacturer: String?
        public var model: String?
        public var hardwareVersion: String?

        public init(manufacturer: String? = nil, model: String? = nil, hardwareVersion: String? = nil) {
            self.manufacturer = manufacturer
            self.model = model
            self.hardwareVersion = hardwareVersion
        }
    }

    private static let domain = "grove-recording-device-id-v1"

    /// The identifier value that deduplicates this recorder, or `nil` when the platform states
    /// too little to identify one.
    ///
    /// Requires a manufacturer and at least one of model or hardware version: a source naming
    /// only its manufacturer would otherwise collapse every device a participant owns into one
    /// resource, so this fails closed and the caller keeps its per-sample identity.
    public static func value(subject: String, adapter: String, recorder: Recorder) -> String? {
        guard !subject.isEmpty,
              let manufacturer = recorder.manufacturer,
              !manufacturer.isEmpty else {
            return nil
        }
        let model = recorder.model ?? ""
        let hardwareVersion = recorder.hardwareVersion ?? ""
        guard !model.isEmpty || !hardwareVersion.isEmpty else {
            return nil
        }
        return digest([domain, subject, adapter, manufacturer, model, hardwareVersion])
    }

    /// RFC 8785/JCS serialization of an array of strings, matching the published lexical rules.
    public static func canonicalName(_ parts: [String]) -> String {
        "[" + parts.map { GroveFHIRExchangeIdentity.quotedJCSString($0) }.joined(separator: ",") + "]"
    }

    private static func digest(_ parts: [String]) -> String {
        let hashed = SHA256.hash(data: Data(canonicalName(parts).utf8))
        return "v1:" + hashed.map { String(format: "%02x", $0) }.joined()
    }
}
