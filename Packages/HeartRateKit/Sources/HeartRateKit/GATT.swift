import CoreBluetooth

/// Bluetooth SIG assigned numbers used by this package.
public enum GATT {
    /// Heart Rate service (0x180D).
    public static var heartRateService: CBUUID { CBUUID(string: "180D") }
    /// Heart Rate Measurement characteristic (0x2A37), notify only.
    public static var heartRateMeasurement: CBUUID { CBUUID(string: "2A37") }
    /// Body Sensor Location characteristic (0x2A38), read only.
    public static var bodySensorLocation: CBUUID { CBUUID(string: "2A38") }
    /// Battery service (0x180F).
    public static var batteryService: CBUUID { CBUUID(string: "180F") }
    /// Battery Level characteristic (0x2A19), percentage 0-100.
    public static var batteryLevel: CBUUID { CBUUID(string: "2A19") }
}
