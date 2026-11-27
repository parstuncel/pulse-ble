import Foundation

public enum HeartRateVariability {
    /// Root mean square of successive differences between RR intervals, in milliseconds.
    ///
    /// RMSSD is the standard short-term measure of heart rate variability.
    /// Returns `nil` when there are fewer than two intervals.
    public static func rmssd(rrIntervals: [Double]) -> Double? {
        guard rrIntervals.count >= 2 else { return nil }
        let differences = zip(rrIntervals.dropFirst(), rrIntervals).map { ($0 - $1) * 1000 }
        let meanSquare = differences.reduce(0) { $0 + $1 * $1 } / Double(differences.count)
        return meanSquare.squareRoot()
    }
}
