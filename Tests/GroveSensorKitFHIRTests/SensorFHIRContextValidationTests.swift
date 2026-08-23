//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
@testable import GroveSensorKitFHIR
import ModelsR4
import Testing


/// The converter refuses a context whose references cannot mean what the graph needs them to mean.
@Suite
struct SensorFHIRContextValidationTests {
    private static let start = Date(timeIntervalSince1970: 1_787_009_400)

    private static func context(
        subject: Reference,
        researchStudies: [Reference] = []
    ) throws -> SensorFHIRConversionContext {
        SensorFHIRConversionContext(
            subject: subject,
            converter: SensorFHIRApplication(
                identifier: try GroveFHIRBusinessIdentifier(
                    system: "https://study.example.org/fhir/identifiers/application",
                    value: "org.grovealliance.conformance-fixture|0.3.0"
                ),
                name: "Grove Conformance Fixture",
                version: "0.3.0"
            ),
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/sensor-graph",
            issuedAt: start.addingTimeInterval(10),
            recordedAt: start.addingTimeInterval(20),
            researchStudies: researchStudies
        )
    }

    private static func record() throws -> SensorFHIRRecord {
        .recordingDocument(try GroveSensorRecordingDocument(
            identifier: GroveFHIRBusinessIdentifier(
                system: "https://study.example.org/fhir/identifiers/sensorkit-record",
                value: "ambient-light-1"
            ),
            sourceTypeIdentifier: "SRSensor.ambientLightSensor",
            type: SensorFHIRCode(
                system: "https://grovealliance.org/fhir/sensor/CodeSystem/grove-sensor-recording",
                code: "ambient-light",
                display: "Ambient light"
            ),
            title: "Ambient light recording",
            contentType: "text/csv",
            format: "grove-csv-1",
            payload: .inline(Data("t,lux\n0,120\n".utf8)),
            rawPayloadAdmission: .verifiedSanitizedInput
        ))
    }

    @Test("A subject that is not a Patient reference is rejected")
    func rejectsNonPatientSubject() throws {
        let context = try Self.context(subject: Reference(reference: "Group/cohort-1"))
        #expect(throws: SensorFHIRConversionError.invalidReference(
            field: "subject",
            expectedResourceType: "Patient"
        )) {
            try SensorFHIRConverter().convert(Self.record(), context: context)
        }
    }

    @Test("A study reference pointing at the wrong resource type is rejected")
    func rejectsNonStudyReference() throws {
        let context = try Self.context(
            subject: Reference(reference: "Patient/example"),
            researchStudies: [Reference(reference: "Patient/example")]
        )
        #expect(throws: SensorFHIRConversionError.invalidReference(
            field: "researchStudies",
            expectedResourceType: "ResearchStudy"
        )) {
            try SensorFHIRConverter().convert(Self.record(), context: context)
        }
    }

    @Test("The same study listed twice would create an ambiguous graph and is rejected")
    func rejectsDuplicateStudy() throws {
        let study = Reference(reference: "ResearchStudy/heart-counts")
        let context = try Self.context(
            subject: Reference(reference: "Patient/example"),
            researchStudies: [study, study]
        )
        #expect(throws: SensorFHIRConversionError.duplicateReference(field: "researchStudies")) {
            try SensorFHIRConverter().convert(Self.record(), context: context)
        }
    }

    @Test("A batch reports the typed reason for each rejected record rather than relabelling it")
    func batchReportsTypedReasons() throws {
        let context = try Self.context(subject: Reference(reference: "Group/cohort-1"))
        let result = SensorFHIRConverter().convert([try Self.record()], context: context)
        #expect(result.conversions.isEmpty)
        #expect(result.failures.map(\.reason) == [
            .invalidReference(field: "subject", expectedResourceType: "Patient")
        ])
    }
}
