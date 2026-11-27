import Charts
import HeartRateKit
import SwiftUI

struct LiveView: View {
    let model: MonitorViewModel
    let sensor: DiscoveredSensor

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HeartRateHeader(
                    bpm: model.latest?.beatsPerMinute,
                    isConnecting: model.phase == .connecting(sensor)
                )
                SensorInfo(
                    contact: model.latest?.sensorContact,
                    location: model.bodySensorLocation,
                    battery: model.batteryLevel
                )
                HeartRateChart(samples: model.samples)
                StatsGrid(model: model)
            }
            .padding()
        }
        .navigationTitle(sensor.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Disconnect", role: .destructive) { model.disconnect() }
            }
        }
    }
}

private struct HeartRateHeader: View {
    let bpm: Int?
    let isConnecting: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)
                .symbolEffect(.bounce, value: bpm)
            Text(bpm.map(String.init) ?? "--")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(isConnecting ? "Connecting…" : "BPM")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .animation(.snappy, value: bpm)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bpm.map { "\($0) beats per minute" } ?? "Waiting for heart rate")
    }
}

private struct SensorInfo: View {
    let contact: HeartRateMeasurement.SensorContact?
    let location: BodySensorLocation?
    let battery: Int?

    var body: some View {
        HStack(spacing: 8) {
            if let contact, contact != .notSupported {
                chip(
                    contact == .detected ? "Skin contact" : "No contact",
                    systemImage: contact == .detected ? "hand.raised.fill" : "hand.raised.slash"
                )
            }
            if let location {
                chip(location.displayName, systemImage: "figure.stand")
            }
            if let battery {
                chip("\(battery)%", systemImage: Self.batterySymbol(for: battery))
            }
        }
        .font(.subheadline)
    }

    private func chip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.fill.tertiary, in: Capsule())
    }

    static func batterySymbol(for level: Int) -> String {
        switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

private struct HeartRateChart: View {
    let samples: [MonitorViewModel.Sample]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 2 minutes")
                .font(.headline)
            if samples.count < 2 {
                ContentUnavailableView("Collecting data", systemImage: "waveform.path.ecg")
                    .frame(height: 200)
            } else {
                Chart(samples) { sample in
                    AreaMark(
                        x: .value("Time", sample.date),
                        yStart: .value("Baseline", yDomain.lowerBound),
                        yEnd: .value("BPM", sample.bpm)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.red.opacity(0.35), .red.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(x: .value("Time", sample.date), y: .value("BPM", sample.bpm))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: yDomain)
                .chartXAxis(.hidden)
                .frame(height: 200)
                .accessibilityLabel("Heart rate over the last two minutes")
            }
        }
        .padding()
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Fits the data with some headroom so small changes stay visible.
    private var yDomain: ClosedRange<Int> {
        let values = samples.map(\.bpm)
        let low = (values.min() ?? 60) - 10
        let high = (values.max() ?? 100) + 10
        return max(low, 30)...max(high, low + 20)
    }
}

private struct StatsGrid: View {
    let model: MonitorViewModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Average", value: model.averageBPM.map(String.init), unit: "BPM")
            StatCard(title: "Range", value: range, unit: "BPM")
            StatCard(
                title: "HRV (RMSSD)",
                value: model.rmssd.map { String(Int($0.rounded())) },
                unit: "ms",
                footnote: "Beat-to-beat variability from RR intervals"
            )
            StatCard(title: "Samples", value: String(model.samples.count), unit: "")
        }
    }

    private var range: String? {
        guard let low = model.minimumBPM, let high = model.maximumBPM else { return nil }
        return "\(low)–\(high)"
    }
}

private struct StatCard: View {
    let title: String
    let value: String?
    let unit: String
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "--")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding()
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
