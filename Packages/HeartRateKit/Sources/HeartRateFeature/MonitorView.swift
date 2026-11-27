import HeartRateKit
import SwiftUI

/// Root screen: the sensor list until a sensor is chosen, then live monitoring.
public struct MonitorView: View {
    private let model: MonitorViewModel

    public init(model: MonitorViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .connecting(let sensor), .connected(let sensor):
                    LiveView(model: model, sensor: sensor)
                case .idle, .scanning, .failed:
                    ScanView(model: model)
                }
            }
        }
        .tint(.red)
        .task { model.start() }
    }
}

#Preview("Simulated sensor") {
    MonitorView(model: MonitorViewModel(client: SimulatedHeartRateClient()))
}
