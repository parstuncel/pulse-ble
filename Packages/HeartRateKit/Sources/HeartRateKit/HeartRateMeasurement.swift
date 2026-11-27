import Foundation

/// A decoded value of the Heart Rate Measurement characteristic (0x2A37),
/// as defined by the Bluetooth SIG Heart Rate Service specification.
public struct HeartRateMeasurement: Equatable, Sendable {
    public enum SensorContact: Equatable, Sendable {
        /// The sensor does not report whether it touches the skin.
        case notSupported
        case notDetected
        case detected
    }

    public var beatsPerMinute: Int
    public var sensorContact: SensorContact
    /// Accumulated energy expended in kilojoules, when the sensor reports it.
    public var energyExpended: Int?
    /// Time between consecutive beats in seconds, oldest first.
    public var rrIntervals: [Double]

    public init(
        beatsPerMinute: Int,
        sensorContact: SensorContact = .notSupported,
        energyExpended: Int? = nil,
        rrIntervals: [Double] = []
    ) {
        self.beatsPerMinute = beatsPerMinute
        self.sensorContact = sensorContact
        self.energyExpended = energyExpended
        self.rrIntervals = rrIntervals
    }
}

extension HeartRateMeasurement {
    public enum DecodingError: Error, Equatable {
        case empty
        case truncated(field: String)
    }

    /// Bits of the first byte of the characteristic value.
    private enum Flag {
        static let valueIsUInt16: UInt8 = 1 << 0
        static let contactDetected: UInt8 = 1 << 1
        static let contactSupported: UInt8 = 1 << 2
        static let energyExpendedPresent: UInt8 = 1 << 3
        static let rrIntervalsPresent: UInt8 = 1 << 4
    }

    /// Decodes the raw characteristic value. All multi-byte fields are little-endian.
    public init(data: Data) throws(DecodingError) {
        var reader = ByteReader(data)
        guard let flags = reader.readUInt8() else { throw .empty }

        let beatsPerMinute: Int
        if flags & Flag.valueIsUInt16 != 0 {
            guard let value = reader.readUInt16() else { throw .truncated(field: "heart rate") }
            beatsPerMinute = Int(value)
        } else {
            guard let value = reader.readUInt8() else { throw .truncated(field: "heart rate") }
            beatsPerMinute = Int(value)
        }

        let contact: SensorContact =
            if flags & Flag.contactSupported == 0 { .notSupported }
            else if flags & Flag.contactDetected != 0 { .detected }
            else { .notDetected }

        var energyExpended: Int?
        if flags & Flag.energyExpendedPresent != 0 {
            guard let value = reader.readUInt16() else { throw .truncated(field: "energy expended") }
            energyExpended = Int(value)
        }

        // RR intervals fill the rest of the packet, in units of 1/1024 second.
        var rrIntervals: [Double] = []
        if flags & Flag.rrIntervalsPresent != 0 {
            while !reader.isAtEnd {
                guard let value = reader.readUInt16() else { throw .truncated(field: "RR interval") }
                rrIntervals.append(Double(value) / 1024)
            }
        }

        self.init(
            beatsPerMinute: beatsPerMinute,
            sensorContact: contact,
            energyExpended: energyExpended,
            rrIntervals: rrIntervals
        )
    }
}

/// Reads little-endian integers from a byte buffer without trapping on short input.
struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    var isAtEnd: Bool { offset >= bytes.count }

    mutating func readUInt8() -> UInt8? {
        guard offset < bytes.count else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readUInt16() -> UInt16? {
        guard offset + 1 < bytes.count else { return nil }
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }
}
