// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeartRateKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HeartRateKit", targets: ["HeartRateKit"]),
        .library(name: "HeartRateFeature", targets: ["HeartRateFeature"]),
    ],
    targets: [
        // Bluetooth layer: GATT decoding, CoreBluetooth client, simulated sensor.
        .target(name: "HeartRateKit"),
        // Presentation layer: view model and SwiftUI screens.
        .target(name: "HeartRateFeature", dependencies: ["HeartRateKit"]),
        .testTarget(name: "HeartRateKitTests", dependencies: ["HeartRateKit"]),
        .testTarget(name: "HeartRateFeatureTests", dependencies: ["HeartRateFeature", "HeartRateKit"]),
    ]
)
