import Foundation
import Testing
@testable import HeartRateKit

struct HeartRateMeasurementTests {
    @Test func decodesEightBitHeartRate() throws {
        let measurement = try HeartRateMeasurement(data: Data([0x00, 72]))
        #expect(measurement == HeartRateMeasurement(beatsPerMinute: 72))
    }

    @Test func decodesSixteenBitHeartRate() throws {
        // 0x012C = 300, little-endian.
        let measurement = try HeartRateMeasurement(data: Data([0x01, 0x2C, 0x01]))
        #expect(measurement.beatsPerMinute == 300)
    }

    @Test(arguments: [
        (UInt8(0b000), HeartRateMeasurement.SensorContact.notSupported),
        (UInt8(0b010), .notSupported), // "detected" bit without "supported" bit is meaningless
        (UInt8(0b100), .notDetected),
        (UInt8(0b110), .detected),
    ])
    func decodesSensorContact(flags: UInt8, expected: HeartRateMeasurement.SensorContact) throws {
        let measurement = try HeartRateMeasurement(data: Data([flags, 60]))
        #expect(measurement.sensorContact == expected)
    }

    @Test func decodesEnergyExpended() throws {
        // 0x2710 = 10000 kJ.
        let measurement = try HeartRateMeasurement(data: Data([0x08, 60, 0x10, 0x27]))
        #expect(measurement.energyExpended == 10_000)
    }

    @Test func decodesRRIntervalsInSeconds() throws {
        // 1024/1024 s and 512/1024 s.
        let measurement = try HeartRateMeasurement(data: Data([0x10, 70, 0x00, 0x04, 0x00, 0x02]))
        #expect(measurement.rrIntervals == [1.0, 0.5])
    }

    @Test func decodesEveryFieldTogether() throws {
        let data = Data([0x1F, 0x2C, 0x01, 0x10, 0x27, 0x00, 0x04])
        let measurement = try HeartRateMeasurement(data: data)
        #expect(measurement == HeartRateMeasurement(
            beatsPerMinute: 300,
            sensorContact: .detected,
            energyExpended: 10_000,
            rrIntervals: [1.0]
        ))
    }

    @Test func rejectsEmptyPacket() {
        #expect(throws: HeartRateMeasurement.DecodingError.empty) {
            try HeartRateMeasurement(data: Data())
        }
    }

    @Test func rejectsTruncatedHeartRate() {
        #expect(throws: HeartRateMeasurement.DecodingError.truncated(field: "heart rate")) {
            try HeartRateMeasurement(data: Data([0x01, 0x2C]))
        }
    }

    @Test func rejectsTruncatedEnergyExpended() {
        #expect(throws: HeartRateMeasurement.DecodingError.truncated(field: "energy expended")) {
            try HeartRateMeasurement(data: Data([0x08, 60, 0x10]))
        }
    }

    @Test func rejectsHalfAnRRInterval() {
        #expect(throws: HeartRateMeasurement.DecodingError.truncated(field: "RR interval")) {
            try HeartRateMeasurement(data: Data([0x10, 70, 0x00, 0x04, 0x00]))
        }
    }
}

struct BodySensorLocationTests {
    @Test func decodesKnownLocation() {
        #expect(BodySensorLocation(data: Data([0x01])) == .chest)
        #expect(BodySensorLocation(data: Data([0x02])) == .wrist)
    }

    @Test func rejectsReservedAndEmptyValues() {
        #expect(BodySensorLocation(data: Data([0x07])) == nil)
        #expect(BodySensorLocation(data: Data()) == nil)
    }
}

struct HeartRateVariabilityTests {
    @Test func needsAtLeastTwoIntervals() {
        #expect(HeartRateVariability.rmssd(rrIntervals: []) == nil)
        #expect(HeartRateVariability.rmssd(rrIntervals: [0.8]) == nil)
    }

    @Test func isZeroForAPerfectlySteadyRhythm() {
        #expect(HeartRateVariability.rmssd(rrIntervals: [0.8, 0.8, 0.8]) == 0)
    }

    @Test func isRootMeanSquareOfSuccessiveDifferences() throws {
        // Differences are +50 ms and -50 ms, so RMSSD is 50 ms.
        let rmssd = try #require(HeartRateVariability.rmssd(rrIntervals: [0.80, 0.85, 0.80]))
        #expect(abs(rmssd - 50) < 0.0001)
    }
}
