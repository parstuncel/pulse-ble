import Foundation
import Testing
import HeartRateKit
@testable import HeartRateFeature

/// A client whose streams the test drives by hand.
final class MockHeartRateClient: HeartRateSensorClient {
    let availability = AsyncStream.makeStream(of: BluetoothAvailability.self)
    let scanning = AsyncStream.makeStream(of: DiscoveredSensor.self)
    let connection = AsyncThrowingStream.makeStream(of: SensorUpdate.self, throwing: Error.self)

    func availabilityUpdates() -> AsyncStream<BluetoothAvailability> { availability.stream }
    func scan() -> AsyncStream<DiscoveredSensor> { scanning.stream }
    func connect(to sensorID: UUID) -> AsyncThrowingStream<SensorUpdate, Error> { connection.stream }
}

/// Polls until `condition` holds, so tests do not depend on scheduling order.
@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return true
}

@MainActor
struct MonitorViewModelTests {
    let client = MockHeartRateClient()
    let strap = DiscoveredSensor(id: UUID(), name: "Strap", rssi: -50)

    @Test func publishesBluetoothAvailability() async {
        let model = MonitorViewModel(client: client)
        model.start()
        client.availability.continuation.yield(.poweredOff)
        #expect(await eventually { model.availability == .poweredOff })
        client.availability.continuation.yield(.poweredOn)
        #expect(await eventually { model.availability == .poweredOn })
    }

    @Test func scanningListsEachSensorOnceWithLatestSignal() async {
        let model = MonitorViewModel(client: client)
        model.startScan()
        #expect(model.phase == .scanning)

        client.scanning.continuation.yield(strap)
        client.scanning.continuation.yield(DiscoveredSensor(id: strap.id, name: "Strap", rssi: -80))
        client.scanning.continuation.yield(DiscoveredSensor(id: UUID(), name: "Watch"))

        #expect(await eventually { model.sensors.count == 2 })
        #expect(model.sensors.first?.rssi == -80)

        model.stopScan()
        #expect(model.phase == .idle)
    }

    @Test func becomesConnectedOnFirstUpdateAndRecordsData() async {
        let model = MonitorViewModel(client: client)
        model.connect(to: strap)
        #expect(model.phase == .connecting(strap))

        client.connection.continuation.yield(.bodySensorLocation(.chest))
        client.connection.continuation.yield(.batteryLevel(77))
        client.connection.continuation.yield(.measurement(HeartRateMeasurement(beatsPerMinute: 60, rrIntervals: [1.0])))
        client.connection.continuation.yield(.measurement(HeartRateMeasurement(beatsPerMinute: 70, rrIntervals: [0.95])))

        #expect(await eventually { model.samples.count == 2 })
        #expect(model.phase == .connected(strap))
        #expect(model.latest?.beatsPerMinute == 70)
        #expect(model.bodySensorLocation == .chest)
        #expect(model.batteryLevel == 77)
        #expect(model.averageBPM == 65)
        #expect(model.minimumBPM == 60)
        #expect(model.maximumBPM == 70)
        #expect(model.rmssd.map { abs($0 - 50) < 0.0001 } == true)
    }

    @Test func keepsOnlyTheMostRecentSamples() async {
        let model = MonitorViewModel(client: client, sampleLimit: 3)
        model.connect(to: strap)
        for bpm in [60, 61, 62, 63, 64] {
            client.connection.continuation.yield(.measurement(HeartRateMeasurement(beatsPerMinute: bpm)))
        }
        #expect(await eventually { model.latest?.beatsPerMinute == 64 })
        #expect(model.samples.map(\.bpm) == [62, 63, 64])
    }

    @Test func aDroppedConnectionShowsAnError() async {
        let model = MonitorViewModel(client: client)
        model.connect(to: strap)
        client.connection.continuation.finish(throwing: SensorError.disconnected(reason: nil))

        #expect(await eventually { model.phase == .failed("The sensor disconnected.") })
    }

    @Test func disconnectingIsNotReportedAsAFailure() async throws {
        let model = MonitorViewModel(client: client)
        model.connect(to: strap)
        client.connection.continuation.yield(.measurement(HeartRateMeasurement(beatsPerMinute: 80)))
        #expect(await eventually { model.phase == .connected(strap) })

        model.disconnect()
        client.connection.continuation.finish(throwing: SensorError.disconnected(reason: nil))
        try await Task.sleep(for: .milliseconds(50))

        #expect(model.phase == .idle)
    }

    @Test func connectingAgainClearsThePreviousSession() async {
        let model = MonitorViewModel(client: client)
        model.connect(to: strap)
        client.connection.continuation.yield(.measurement(HeartRateMeasurement(beatsPerMinute: 80)))
        #expect(await eventually { model.samples.count == 1 })

        model.connect(to: strap)
        #expect(model.samples.isEmpty)
        #expect(model.latest == nil)
    }
}
