import Foundation
import Testing
@testable import HeartRateKit

struct SimulatedHeartRateClientTests {
    @Test func scanFindsTheDemoSensors() async {
        let client = SimulatedHeartRateClient()
        var found: [DiscoveredSensor] = []
        for await sensor in client.scan() {
            found.append(sensor)
            if found.count == SimulatedHeartRateClient.demoSensors.count { break }
        }
        #expect(found == SimulatedHeartRateClient.demoSensors)
    }

    @Test func connectingStreamsMetadataThenMeasurements() async throws {
        let client = SimulatedHeartRateClient(interval: .milliseconds(5))
        let chestStrap = SimulatedHeartRateClient.demoSensors[0]

        var updates: [SensorUpdate] = []
        for try await update in client.connect(to: chestStrap.id) {
            updates.append(update)
            if updates.count == 4 { break }
        }

        #expect(updates[0] == .bodySensorLocation(.chest))
        #expect(updates[1] == .batteryLevel(86))
        for update in updates.dropFirst(2) {
            guard case .measurement(let measurement) = update else {
                Issue.record("Expected a measurement, got \(update)")
                continue
            }
            #expect((40...200).contains(measurement.beatsPerMinute))
            #expect(measurement.sensorContact == .detected)
            #expect(!measurement.rrIntervals.isEmpty)
        }
    }

    @Test func connectingToAnUnknownSensorFails() async {
        let client = SimulatedHeartRateClient()
        await #expect(throws: SensorError.sensorNotFound) {
            for try await _ in client.connect(to: UUID()) {}
        }
    }
}
