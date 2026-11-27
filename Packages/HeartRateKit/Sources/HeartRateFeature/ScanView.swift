import HeartRateKit
import SwiftUI

struct ScanView: View {
    let model: MonitorViewModel

    var body: some View {
        List {
            if let notice = availabilityNotice {
                Section {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            if case .failed(let message) = model.phase {
                Section {
                    Label(message, systemImage: "bolt.heart.fill")
                        .foregroundStyle(.red)
                }
            }

            Section("Nearby sensors") {
                if model.sensors.isEmpty {
                    emptyState
                } else {
                    ForEach(model.sensors) { sensor in
                        Button {
                            model.connect(to: sensor)
                        } label: {
                            SensorRow(sensor: sensor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Pulse")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.phase == .scanning {
                    Button("Stop") { model.stopScan() }
                } else {
                    Button("Scan") { model.startScan() }
                        .disabled(model.availability != .poweredOn)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if model.phase == .scanning {
                ProgressView("Scanning…")
                    .padding()
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            model.phase == .scanning ? "Looking for sensors" : "No sensors yet",
            systemImage: "heart.text.square",
            description: Text("Put on a chest strap or a watch that broadcasts heart rate over Bluetooth, then tap Scan.")
        )
    }

    private var availabilityNotice: String? {
        switch model.availability {
        case .poweredOn, .unknown: nil
        case .poweredOff: "Bluetooth is turned off."
        case .unauthorized: "Pulse needs Bluetooth access. You can allow it in Settings."
        case .unsupported: "This device does not support Bluetooth Low Energy."
        case .resetting: "Bluetooth is restarting…"
        }
    }
}

struct SensorRow: View {
    let sensor: DiscoveredSensor

    var body: some View {
        HStack {
            Image(systemName: "heart.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
            Text(sensor.name)
                .font(.body.weight(.medium))
            Spacer()
            if let rssi = sensor.rssi {
                Image(systemName: "cellularbars", variableValue: Self.signalStrength(rssi: rssi))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Signal \(rssi) dBm")
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    /// Maps -100 dBm (unusable) ... -40 dBm (excellent) to 0 ... 1.
    static func signalStrength(rssi: Int) -> Double {
        min(max(Double(rssi + 100) / 60, 0), 1)
    }
}
