import Foundation
import HeartRateKit
import Observation

/// Drives the scan and live-monitor screens.
///
/// Each long-running operation is a `Task` that iterates one of the client's
/// async streams. Cancelling the task is how the screen stops a scan or
/// disconnects, so there is no separate "stop" call to keep in sync.
@MainActor
@Observable
public final class MonitorViewModel {
    public enum Phase: Equatable {
        case idle
        case scanning
        case connecting(DiscoveredSensor)
        case connected(DiscoveredSensor)
        case failed(String)
    }

    public struct Sample: Identifiable, Equatable {
        public let id: Int
        public let date: Date
        public let bpm: Int
    }

    public private(set) var availability: BluetoothAvailability = .unknown
    public private(set) var phase: Phase = .idle
    public private(set) var sensors: [DiscoveredSensor] = []

    public private(set) var latest: HeartRateMeasurement?
    public private(set) var samples: [Sample] = []
    public private(set) var bodySensorLocation: BodySensorLocation?
    public private(set) var batteryLevel: Int?
    /// Heart rate variability over the most recent RR intervals, in milliseconds.
    public private(set) var rmssd: Double?

    public var minimumBPM: Int? { samples.map(\.bpm).min() }
    public var maximumBPM: Int? { samples.map(\.bpm).max() }
    public var averageBPM: Int? {
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0) { $0 + $1.bpm }
        return Int((Double(total) / Double(samples.count)).rounded())
    }

    @ObservationIgnored private let client: any HeartRateSensorClient
    @ObservationIgnored private let sampleLimit: Int
    @ObservationIgnored private let rrWindow: Int
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var recentRRIntervals: [Double] = []
    @ObservationIgnored private var nextSampleID = 0
    @ObservationIgnored private var availabilityTask: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?

    /// - Parameters:
    ///   - sampleLimit: Samples kept for the chart. At one per second, 120 is two minutes.
    ///   - rrWindow: RR intervals used for the variability estimate.
    public init(
        client: any HeartRateSensorClient,
        sampleLimit: Int = 120,
        rrWindow: Int = 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.sampleLimit = sampleLimit
        self.rrWindow = rrWindow
        self.now = now
    }

    /// Starts observing Bluetooth availability. Safe to call more than once.
    public func start() {
        guard availabilityTask == nil else { return }
        availabilityTask = Task { [weak self, client] in
            for await availability in client.availabilityUpdates() {
                self?.availability = availability
            }
        }
    }

    public func startScan() {
        scanTask?.cancel()
        sensors = []
        phase = .scanning
        scanTask = Task { [weak self, client] in
            for await sensor in client.scan() {
                self?.upsert(sensor)
            }
        }
    }

    public func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        if phase == .scanning {
            phase = .idle
        }
    }

    public func connect(to sensor: DiscoveredSensor) {
        scanTask?.cancel()
        scanTask = nil
        connectionTask?.cancel()
        resetSession()
        phase = .connecting(sensor)

        connectionTask = Task { [weak self, client] in
            do {
                for try await update in client.connect(to: sensor.id) {
                    self?.apply(update, from: sensor)
                }
                guard !Task.isCancelled else { return }
                self?.phase = .idle
            } catch {
                // A cancelled task means the user disconnected; that is not a failure.
                guard !Task.isCancelled else { return }
                self?.phase = .failed(Self.message(for: error))
            }
        }
    }

    public func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        phase = .idle
    }

    // MARK: Private

    private func upsert(_ sensor: DiscoveredSensor) {
        if let index = sensors.firstIndex(where: { $0.id == sensor.id }) {
            sensors[index] = sensor
        } else {
            sensors.append(sensor)
        }
    }

    private func apply(_ update: SensorUpdate, from sensor: DiscoveredSensor) {
        if case .connecting = phase {
            phase = .connected(sensor)
        }
        switch update {
        case .measurement(let measurement):
            record(measurement)
        case .bodySensorLocation(let location):
            bodySensorLocation = location
        case .batteryLevel(let level):
            batteryLevel = level
        }
    }

    private func record(_ measurement: HeartRateMeasurement) {
        latest = measurement

        samples.append(Sample(id: nextSampleID, date: now(), bpm: measurement.beatsPerMinute))
        nextSampleID += 1
        if samples.count > sampleLimit {
            samples.removeFirst(samples.count - sampleLimit)
        }

        recentRRIntervals.append(contentsOf: measurement.rrIntervals)
        if recentRRIntervals.count > rrWindow {
            recentRRIntervals.removeFirst(recentRRIntervals.count - rrWindow)
        }
        rmssd = HeartRateVariability.rmssd(rrIntervals: recentRRIntervals)
    }

    private func resetSession() {
        latest = nil
        samples = []
        recentRRIntervals = []
        rmssd = nil
        bodySensorLocation = nil
        batteryLevel = nil
    }

    static func message(for error: any Error) -> String {
        switch error as? SensorError {
        case .bluetoothUnavailable:
            "Bluetooth is not available. Turn it on and try again."
        case .sensorNotFound:
            "The sensor is no longer nearby. Scan again."
        case .serviceNotFound:
            "This device does not offer the Bluetooth Heart Rate service."
        case .connectionFailed(let reason):
            ["Could not connect to the sensor.", reason].compactMap { $0 }.joined(separator: " ")
        case .disconnected(let reason):
            ["The sensor disconnected.", reason].compactMap { $0 }.joined(separator: " ")
        case nil:
            error.localizedDescription
        }
    }
}
