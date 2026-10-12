import Foundation

public enum UnitSystem: String, Codable, CaseIterable, Sendable {
    case metric
    case imperial
}

public enum TemperatureUnit: String, Codable, CaseIterable, Sendable {
    case celsius
    case fahrenheit
}

public enum UnitConversion {
    public static let mlPerFluidOunce = 29.5735
    public static let kgPerPound = 0.45359237
    public static let cmPerInch = 2.54

    public static func ounces(fromML ml: Double) -> Double { ml / mlPerFluidOunce }
    public static func ml(fromOunces oz: Double) -> Double { oz * mlPerFluidOunce }
    public static func pounds(fromKg kg: Double) -> Double { kg / kgPerPound }
    public static func kg(fromPounds lb: Double) -> Double { lb * kgPerPound }
    public static func inches(fromCm cm: Double) -> Double { cm / cmPerInch }
    public static func cm(fromInches inches: Double) -> Double { inches * cmPerInch }
    public static func fahrenheit(fromCelsius c: Double) -> Double { c * 9 / 5 + 32 }
    public static func celsius(fromFahrenheit f: Double) -> Double { (f - 32) * 5 / 9 }

    /// Upper bound for `poundsAndOunces`, far above any real weight.
    static let maxPounds = 10_000.0

    /// Splits a weight into whole pounds and remaining ounces (16 oz per lb).
    /// Non-finite or negative weights give zero and huge ones are clamped, since
    /// converting them to `Int` would trap.
    public static func poundsAndOunces(fromKg kg: Double) -> (pounds: Int, ounces: Double) {
        var totalPounds = pounds(fromKg: kg)
        guard totalPounds.isFinite, totalPounds > 0 else { return (0, 0) }
        totalPounds = min(totalPounds, maxPounds)
        var whole = Int(totalPounds.rounded(.down))
        var ounces = (totalPounds - Double(whole)) * 16
        if ounces >= 15.95 {
            whole += 1
            ounces = 0
        }
        return (whole, ounces)
    }
}
