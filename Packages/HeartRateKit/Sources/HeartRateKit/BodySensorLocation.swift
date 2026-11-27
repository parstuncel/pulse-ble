import Foundation

/// Value of the Body Sensor Location characteristic (0x2A38).
public enum BodySensorLocation: UInt8, CaseIterable, Sendable {
    case other = 0
    case chest
    case wrist
    case finger
    case hand
    case earLobe
    case foot

    public init?(data: Data) {
        guard let raw = data.first else { return nil }
        self.init(rawValue: raw)
    }

    public var displayName: String {
        switch self {
        case .other: "Other"
        case .chest: "Chest"
        case .wrist: "Wrist"
        case .finger: "Finger"
        case .hand: "Hand"
        case .earLobe: "Ear lobe"
        case .foot: "Foot"
        }
    }
}
