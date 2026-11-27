import HeartRateFeature
import HeartRateKit
import SwiftUI

@main
struct PulseApp: App {
    @State private var model = MonitorViewModel(client: PulseApp.makeClient())

    var body: some Scene {
        WindowGroup {
            MonitorView(model: model)
                #if DEBUG
                .task { await autoConnectIfRequested() }
                #endif
        }
    }

    #if DEBUG
    /// For screenshots and demos: `-scan` starts scanning on launch,
    /// `-autoconnect` also connects to the first sensor found.
    private func autoConnectIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-scan") {
            model.startScan()
        }
        guard arguments.contains("-autoconnect") else { return }
        model.startScan()
        while model.sensors.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        model.connect(to: model.sensors[0])
    }
    #endif

    /// The iOS Simulator has no Bluetooth radio, so it runs against a simulated sensor.
    /// On a device, launch with the `-demo` argument to do the same.
    private static func makeClient() -> any HeartRateSensorClient {
        #if targetEnvironment(simulator)
        return SimulatedHeartRateClient()
        #else
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            return SimulatedHeartRateClient()
        }
        return CoreBluetoothHeartRateClient()
        #endif
    }
}
