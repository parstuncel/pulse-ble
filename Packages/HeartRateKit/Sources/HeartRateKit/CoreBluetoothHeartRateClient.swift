import CoreBluetooth
import Foundation
import os

/// `HeartRateSensorClient` backed by CoreBluetooth.
///
/// CoreBluetooth is delegate based. This type bridges it to Swift Concurrency:
/// every delegate callback arrives on one private serial queue, all mutable
/// state is read and written only on that queue (which is what makes the
/// `@unchecked Sendable` conformance sound), and results leave through
/// `AsyncStream`s. Cancelling the consuming task stops the scan or closes
/// the connection.
public final class CoreBluetoothHeartRateClient: NSObject, HeartRateSensorClient, @unchecked Sendable {
    private struct Connection {
        let token: UUID
        let peripheral: CBPeripheral
        let continuation: AsyncThrowingStream<SensorUpdate, Error>.Continuation
        var isEstablished = false
    }

    private let queue = DispatchQueue(label: "HeartRateKit.CoreBluetooth")
    private let logger = Logger(subsystem: "HeartRateKit", category: "CoreBluetooth")
    private var central: CBCentralManager!

    // Queue-confined state.
    private var availabilityObservers: [UUID: AsyncStream<BluetoothAvailability>.Continuation] = [:]
    private var activeScan: (token: UUID, continuation: AsyncStream<DiscoveredSensor>.Continuation)?
    private var connection: Connection?
    /// CoreBluetooth does not retain discovered peripherals, so we must.
    private var peripherals: [UUID: CBPeripheral] = [:]

    public override init() {
        super.init()
        queue.sync {
            central = CBCentralManager(delegate: self, queue: queue)
        }
    }

    // MARK: HeartRateSensorClient

    public func availabilityUpdates() -> AsyncStream<BluetoothAvailability> {
        AsyncStream { continuation in
            let token = UUID()
            queue.async {
                self.availabilityObservers[token] = continuation
                continuation.yield(BluetoothAvailability(self.central.state))
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.queue.async { self.availabilityObservers[token] = nil }
            }
        }
    }

    public func scan() -> AsyncStream<DiscoveredSensor> {
        AsyncStream { continuation in
            let token = UUID()
            queue.async {
                // One scan at a time: a new scan replaces the previous one.
                self.activeScan?.continuation.finish()
                self.activeScan = (token, continuation)
                self.startScanningIfPossible()
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    guard self.activeScan?.token == token else { return }
                    self.activeScan = nil
                    if self.central.isScanning { self.central.stopScan() }
                }
            }
        }
    }

    public func connect(to sensorID: UUID) -> AsyncThrowingStream<SensorUpdate, Error> {
        AsyncThrowingStream { continuation in
            let token = UUID()
            queue.async {
                guard self.central.state == .poweredOn else {
                    continuation.finish(throwing: SensorError.bluetoothUnavailable)
                    return
                }
                let known = self.peripherals[sensorID]
                guard let peripheral = known ?? self.central.retrievePeripherals(withIdentifiers: [sensorID]).first else {
                    continuation.finish(throwing: SensorError.sensorNotFound)
                    return
                }
                // One sensor at a time.
                self.closeConnection(error: nil)
                self.connection = Connection(token: token, peripheral: peripheral, continuation: continuation)
                peripheral.delegate = self
                self.central.connect(peripheral)
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    guard self.connection?.token == token else { return }
                    self.closeConnection(error: nil)
                }
            }
        }
    }

    // MARK: Queue-confined helpers

    private func startScanningIfPossible() {
        guard let activeScan, central.state == .poweredOn else { return }
        // A sensor already connected to this phone (for example by another app) stops advertising.
        for peripheral in central.retrieveConnectedPeripherals(withServices: [GATT.heartRateService]) {
            report(peripheral, rssi: nil, advertisedName: nil, to: activeScan.continuation)
        }
        // Duplicates keep the signal strength live while the list is on screen.
        central.scanForPeripherals(
            withServices: [GATT.heartRateService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    private func report(
        _ peripheral: CBPeripheral,
        rssi: Int?,
        advertisedName: String?,
        to continuation: AsyncStream<DiscoveredSensor>.Continuation
    ) {
        peripherals[peripheral.identifier] = peripheral
        let name = peripheral.name ?? advertisedName ?? "Heart rate sensor"
        continuation.yield(DiscoveredSensor(id: peripheral.identifier, name: name, rssi: rssi))
    }

    private func closeConnection(error: SensorError?) {
        guard let connection else { return }
        self.connection = nil
        central.cancelPeripheralConnection(connection.peripheral)
        if let error {
            connection.continuation.finish(throwing: error)
        } else {
            connection.continuation.finish()
        }
    }

    private func isCurrent(_ peripheral: CBPeripheral) -> Bool {
        connection?.peripheral === peripheral
    }
}

// MARK: - CBCentralManagerDelegate

extension CoreBluetoothHeartRateClient: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let availability = BluetoothAvailability(central.state)
        logger.info("Bluetooth availability: \(String(describing: availability), privacy: .public)")
        for observer in availabilityObservers.values {
            observer.yield(availability)
        }
        if central.state == .poweredOn {
            // Resume a scan that was requested while Bluetooth was off.
            startScanningIfPossible()
        } else {
            closeConnection(error: .bluetoothUnavailable)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let activeScan else { return }
        // 127 is CoreBluetooth's "RSSI not available".
        let rssi = RSSI.intValue == 127 ? nil : RSSI.intValue
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        report(peripheral, rssi: rssi, advertisedName: advertisedName, to: activeScan.continuation)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard isCurrent(peripheral) else { return }
        connection?.isEstablished = true
        peripheral.discoverServices([GATT.heartRateService, GATT.batteryService])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard isCurrent(peripheral) else { return }
        closeConnection(error: .connectionFailed(reason: error?.localizedDescription))
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        // Ignore the disconnect we caused ourselves when replacing a connection
        // to the same peripheral: the new connection is not established yet.
        guard let connection, connection.peripheral === peripheral, connection.isEstablished else { return }
        self.connection = nil
        connection.continuation.finish(throwing: SensorError.disconnected(reason: error?.localizedDescription))
    }
}

// MARK: - CBPeripheralDelegate

extension CoreBluetoothHeartRateClient: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard isCurrent(peripheral) else { return }
        if let error {
            closeConnection(error: .connectionFailed(reason: error.localizedDescription))
            return
        }
        let services = peripheral.services ?? []
        guard services.contains(where: { $0.uuid == GATT.heartRateService }) else {
            closeConnection(error: .serviceNotFound)
            return
        }
        for service in services {
            let characteristics = service.uuid == GATT.heartRateService
                ? [GATT.heartRateMeasurement, GATT.bodySensorLocation]
                : [GATT.batteryLevel]
            peripheral.discoverCharacteristics(characteristics, for: service)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard isCurrent(peripheral) else { return }
        if let error {
            logger.error("Characteristic discovery failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case GATT.heartRateMeasurement:
                peripheral.setNotifyValue(true, for: characteristic)
            case GATT.bodySensorLocation:
                peripheral.readValue(for: characteristic)
            case GATT.batteryLevel:
                peripheral.readValue(for: characteristic)
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            default:
                break
            }
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard isCurrent(peripheral), characteristic.uuid == GATT.heartRateMeasurement, let error else { return }
        // Without measurement notifications the connection is useless.
        closeConnection(error: .connectionFailed(reason: error.localizedDescription))
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let connection, connection.peripheral === peripheral else { return }
        if let error {
            logger.error("Reading \(characteristic.uuid.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case GATT.heartRateMeasurement:
            do {
                connection.continuation.yield(.measurement(try HeartRateMeasurement(data: data)))
            } catch {
                // One malformed packet should not end the session.
                logger.warning("Dropped malformed heart rate packet: \(String(describing: error), privacy: .public)")
            }
        case GATT.bodySensorLocation:
            if let location = BodySensorLocation(data: data) {
                connection.continuation.yield(.bodySensorLocation(location))
            }
        case GATT.batteryLevel:
            if let level = data.first {
                connection.continuation.yield(.batteryLevel(Int(min(level, 100))))
            }
        default:
            break
        }
    }
}

extension BluetoothAvailability {
    init(_ state: CBManagerState) {
        switch state {
        case .poweredOn: self = .poweredOn
        case .poweredOff: self = .poweredOff
        case .unauthorized: self = .unauthorized
        case .unsupported: self = .unsupported
        case .resetting: self = .resetting
        case .unknown: self = .unknown
        @unknown default: self = .unknown
        }
    }
}
