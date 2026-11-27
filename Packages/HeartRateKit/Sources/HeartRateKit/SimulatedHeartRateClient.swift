import Foundation

/// A `HeartRateSensorClient` that needs no hardware.
///
/// The iOS Simulator has no Bluetooth radio, so the app uses this client there,
/// and SwiftUI previews and demos use it too. It advertises two demo sensors and
/// streams a heart rate that rises and falls like an interval workout.
public final class SimulatedHeartRateClient: HeartRateSensorClient {
    public static let demoSensors = [
        DiscoveredSensor(id: UUID(uuidString: "6E7A1C1E-0000-4000-8000-000000000001")!, name: "Demo Chest Strap", rssi: -48),
        DiscoveredSensor(id: UUID(uuidString: "6E7A1C1E-0000-4000-8000-000000000002")!, name: "Demo Watch", rssi: -71),
    ]

    private let interval: Duration

    /// - Parameter interval: Time between measurements. Sensors typically notify once per second.
    public init(interval: Duration = .seconds(1)) {
        self.interval = interval
    }

    public func availabilityUpdates() -> AsyncStream<BluetoothAvailability> {
        AsyncStream { $0.yield(.poweredOn) }
    }

    public func scan() -> AsyncStream<DiscoveredSensor> {
        AsyncStream { continuation in
            let task = Task {
                for sensor in Self.demoSensors {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    continuation.yield(sensor)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func connect(to sensorID: UUID) -> AsyncThrowingStream<SensorUpdate, Error> {
        AsyncThrowingStream { continuation in
            guard let index = Self.demoSensors.firstIndex(where: { $0.id == sensorID }) else {
                continuation.finish(throwing: SensorError.sensorNotFound)
                return
            }
            let interval = self.interval
            let task = Task {
                continuation.yield(.bodySensorLocation(index == 0 ? .chest : .wrist))
                continuation.yield(.batteryLevel(index == 0 ? 86 : 54))
                var simulation = WorkoutSimulation()
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: interval)
                    } catch {
                        break
                    }
                    continuation.yield(.measurement(simulation.next()))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Produces plausible measurements: the rate drifts toward a target that
/// rises and falls over a few minutes, with beat-to-beat jitter.
struct WorkoutSimulation {
    private var elapsed = 0.0
    private var bpm = 72.0

    mutating func next() -> HeartRateMeasurement {
        elapsed += 1
        let target = 100 + 40 * sin(elapsed / 25)
        bpm += (target - bpm) * 0.2 + Double.random(in: -2...2)
        let beatLength = 60 / bpm
        let rrIntervals = (0..<2).map { _ in beatLength + Double.random(in: -0.025...0.025) }
        return HeartRateMeasurement(
            beatsPerMinute: Int(bpm.rounded()),
            sensorContact: .detected,
            rrIntervals: rrIntervals
        )
    }
}
