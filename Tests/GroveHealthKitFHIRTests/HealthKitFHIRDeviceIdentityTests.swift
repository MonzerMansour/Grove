//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// One participant's recorder is one Device, however many samples it produced.
@Suite
struct HealthKitFHIRDeviceIdentityTests {
    private let converter = HealthKitFHIRConverter()
    private let timestamp = Date(timeIntervalSince1970: 1_787_148_600)

    private func context(subject: String) -> HealthKitFHIRConversionContext {
        HealthKitFHIRConversionContext(
            subject: Reference(reference: subject.asFHIRStringPrimitive()),
            converter: HealthKitFHIRApplication(
                name: "Example Study",
                bundleIdentifier: "org.grovealliance.example-study",
                version: "2.0.0 (42)"
            ),
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph",
            conversionInstant: timestamp
        )
    }

    private func watch(firmware: String = "11.2", manufacturer: String? = "Apple Inc.") -> HKDevice {
        HKDevice(
            name: "Apple Watch",
            manufacturer: manufacturer,
            model: manufacturer == nil ? nil : "Watch",
            hardwareVersion: manufacturer == nil ? nil : "Watch7,12",
            firmwareVersion: firmware,
            softwareVersion: "26.0",
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
    }

    private func sample(_ device: HKDevice, offset: TimeInterval) -> HKQuantitySample {
        HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 62),
            start: timestamp.addingTimeInterval(offset),
            end: timestamp.addingTimeInterval(offset),
            device: device,
            metadata: nil
        )
    }

    @Test("One recorder is one device across samples, with no configuration")
    func recorderDeduplicatesByDefault() throws {
        let device = watch()
        let context = context(subject: "Patient/1a2b3c")
        let first = try converter.convert(sample(device, offset: 0), context: context)
        let second = try converter.convert(sample(device, offset: 600), context: context)
        #expect(first.graphIdentifiers.recordingDevice == second.graphIdentifiers.recordingDevice)
    }

    @Test("A firmware update keeps the same device rather than minting another")
    func firmwareUpdateKeepsOneDevice() throws {
        let context = context(subject: "Patient/1a2b3c")
        let before = try converter.convert(sample(watch(firmware: "11.2"), offset: 0), context: context)
        let after = try converter.convert(sample(watch(firmware: "11.3"), offset: 600), context: context)
        #expect(before.graphIdentifiers.recordingDevice == after.graphIdentifiers.recordingDevice)
    }

    @Test("Two participants wearing the same model are two devices")
    func identicalModelsStayDistinctPerParticipant() throws {
        let device = watch()
        let mine = try converter.convert(sample(device, offset: 0), context: context(subject: "Patient/1a2b3c"))
        let yours = try converter.convert(sample(device, offset: 0), context: context(subject: "Patient/9z8y7x"))
        #expect(mine.graphIdentifiers.recordingDevice != yours.graphIdentifiers.recordingDevice)
    }

    @Test("A device naming only its manufacturer falls back rather than collapsing every device")
    func degenerateFingerprintFailsClosed() throws {
        let vague = HKDevice(
            name: nil,
            manufacturer: "Apple Inc.",
            model: nil,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
        let context = context(subject: "Patient/1a2b3c")
        let first = try converter.convert(sample(vague, offset: 0), context: context)
        let second = try converter.convert(sample(vague, offset: 600), context: context)
        #expect(first.graphIdentifiers.recordingDevice != second.graphIdentifiers.recordingDevice)
    }

    @Test("The digest matches the identity contract's published vectors")
    func digestMatchesThePublishedVectors() {
        #expect(
            GroveFHIRRecordingDeviceIdentity.value(
                subject: "Patient/1a2b3c",
                adapter: "healthkit",
                recorder: .init(manufacturer: "Apple Inc.", model: "Watch", hardwareVersion: "Watch7,12")
            ) == "v1:24be7c46d4f2dd7603a7c265ddbbba606350b9a3853d083f2f8e20298e1cea12"
        )
        #expect(
            GroveFHIRRecordingDeviceIdentity.value(
                subject: "Patient/9z8y7x",
                adapter: "healthkit",
                recorder: .init(manufacturer: "Apple Inc.", model: "Watch", hardwareVersion: "Watch7,12")
            ) == "v1:87628d0c3f69e0cf925be66b02f512af7cb9f261877097a9b46a29077c427f59"
        )
    }
}


/// A host with no bundle identity must fail through the typed error path, never trap and never
/// mint a graph namespace shared by every such host.
@Suite
struct HealthKitFHIRApplicationIdentityTests {
    @Test("A bundle-less host is rejected as an invalid converter application")
    func bundleLessHostIsRejected() {
        let context = HealthKitFHIRConversionContext(
            subject: Reference(reference: "Patient/1a2b3c".asFHIRStringPrimitive()),
            converter: HealthKitFHIRApplication(name: "Runner", bundleIdentifier: "", version: "1.0")
        )
        #expect(throws: GroveHealthKitFHIRError.invalidConverterApplication("bundleIdentifier")) {
            try HealthKitFHIRConverter.validate(context: context)
        }
    }

    @Test("The empty namespace such a host derives is never treated as valid")
    func emptyNamespaceIsNotSilentlyAccepted() {
        let application = HealthKitFHIRApplication(name: "Runner", bundleIdentifier: "", version: "1.0")
        // Syntactically a valid URN, which is exactly why validation cannot rely on it.
        #expect(application.graphIdentifierSystem == "urn:grove:healthkit-graph:")
    }
}

#endif
