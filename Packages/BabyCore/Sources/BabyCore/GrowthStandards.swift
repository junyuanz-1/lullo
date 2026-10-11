import Foundation

public enum GrowthMetric: String, Codable, CaseIterable, Sendable, Identifiable {
    case weight
    case length
    case headCircumference

    public var id: String { rawValue }

    /// Reads this metric from a growth event (kg or cm).
    public func value(of event: EventRecord) -> Double? {
        switch self {
        case .weight: return event.weightKg
        case .length: return event.heightCm
        case .headCircumference: return event.headCm
        }
    }
}

/// Box-Cox (LMS) parameters for one month of age.
public struct LMS: Equatable, Sendable {
    public var month: Double
    public var l: Double
    public var m: Double
    public var s: Double

    public init(month: Double, l: Double, m: Double, s: Double) {
        self.month = month
        self.l = l
        self.m = m
        self.s = s
    }

    public func zScore(for value: Double) -> Double {
        guard value > 0 else { return -.infinity }
        if abs(l) < 1e-9 { return log(value / m) / s }
        return (pow(value / m, l) - 1) / (l * s)
    }

    public func value(forZ z: Double) -> Double {
        if abs(l) < 1e-9 { return m * exp(s * z) }
        return m * pow(1 + l * s * z, 1 / l)
    }
}

public struct GrowthCurvePoint: Equatable, Sendable {
    public var month: Double
    public var value: Double
}

/// WHO Child Growth Standards, birth to 24 months.
public enum GrowthStandards {
    public static let maxMonth: Double = 24
    /// Percentiles drawn on growth charts.
    public static let chartPercentiles: [Double] = [3, 15, 50, 85, 97]

    public static func table(for metric: GrowthMetric, sex: Sex) -> [LMS]? {
        switch (metric, sex) {
        case (.weight, .male): return weightMale
        case (.weight, .female): return weightFemale
        case (.length, .male): return lengthMale
        case (.length, .female): return lengthFemale
        case (.headCircumference, .male): return headMale
        case (.headCircumference, .female): return headFemale
        case (_, .unspecified): return nil
        }
    }

    /// LMS parameters at a (fractional) age in months, linearly interpolated.
    public static func lms(for metric: GrowthMetric, sex: Sex, ageInMonths age: Double) -> LMS? {
        guard let table = table(for: metric, sex: sex), age >= 0, age <= maxMonth else { return nil }
        let lower = Int(age.rounded(.down))
        if lower >= table.count - 1 { return table.last }
        let a = table[lower]
        let b = table[lower + 1]
        let t = age - Double(lower)
        return LMS(
            month: age,
            l: a.l + (b.l - a.l) * t,
            m: a.m + (b.m - a.m) * t,
            s: a.s + (b.s - a.s) * t
        )
    }

    /// Percentile (0–100) of a measurement, or `nil` if outside the reference range.
    public static func percentile(of value: Double, metric: GrowthMetric, sex: Sex, ageInMonths age: Double) -> Double? {
        guard let lms = lms(for: metric, sex: sex, ageInMonths: age) else { return nil }
        return Statistics.normalCDF(lms.zScore(for: value)) * 100
    }

    public static func curve(for metric: GrowthMetric, sex: Sex, percentile: Double, step: Double = 0.5) -> [GrowthCurvePoint] {
        guard table(for: metric, sex: sex) != nil else { return [] }
        let z = Statistics.inverseNormalCDF(percentile / 100)
        var points: [GrowthCurvePoint] = []
        var month = 0.0
        while month <= maxMonth + 1e-9 {
            if let lms = lms(for: metric, sex: sex, ageInMonths: month) {
                points.append(GrowthCurvePoint(month: month, value: lms.value(forZ: z)))
            }
            month += step
        }
        return points
    }
}

extension Statistics {
    public static func normalCDF(_ z: Double) -> Double {
        0.5 * erfc(-z / 2.0.squareRoot())
    }

    /// Acklam's rational approximation (relative error < 1.2e-9).
    public static func inverseNormalCDF(_ p: Double) -> Double {
        precondition(p > 0 && p < 1, "p must be in (0, 1)")
        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
                 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
                 6.680131188771972e+01, -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
                 -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
                 3.754408661907416e+00]
        let low = 0.02425
        if p < low {
            let q = (-2 * log(p)).squareRoot()
            return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        if p > 1 - low {
            let q = (-2 * log(1 - p)).squareRoot()
            return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        let q = p - 0.5
        let r = q * q
        return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q /
            (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
    }
}
