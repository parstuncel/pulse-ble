import Foundation

/// State of the Bluetooth radio as far as this app can use it.
public enum BluetoothAvailability: Equatable, Sendable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

/// A heart rate sensor found while scanning.
public struct DiscoveredSensor: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    /// Signal strength in dBm, when known.
    public var rssi: Int?

    public init(id: UUID, name: String, rssi: Int? = nil) {
        self.id = id
        self.name = name
        self.rssi = rssi
    }
}

/// Values a connected sensor reports.
public enum SensorUpdate: Equatable, Sendable {
    case measurement(HeartRateMeasurement)
    case bodySensorLocation(BodySensorLocation)
    case batteryLevel(Int)
}

public enum SensorError: Error, Equatable {
    case bluetoothUnavailable
    case sensorNotFound
    case serviceNotFound
    case connectionFailed(reason: String?)
    case disconnected(reason: String?)
}

/// Finds and connects to Bluetooth Low Energy heart rate sensors.
///
/// Every operation is an async sequence whose lifetime is the operation:
/// cancelling the task that iterates `scan()` stops scanning, and cancelling
/// the task that iterates `connect(to:)` disconnects from the sensor.
public protocol HeartRateSensorClient: AnyObject, Sendable {
    /// Emits the current availability immediately, then every change.
    func availabilityUpdates() -> AsyncStream<BluetoothAvailability>

    /// Emits sensors advertising the Heart Rate service. A sensor can be
    /// emitted again with an updated signal strength.
    func scan() -> AsyncStream<DiscoveredSensor>

    /// Connects to a sensor and streams its updates. The stream throws a
    /// `SensorError` when the connection fails or drops.
    func connect(to sensorID: UUID) -> AsyncThrowingStream<SensorUpdate, Error>
}
