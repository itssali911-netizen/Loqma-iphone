import Foundation

enum MealImageContent {
    /// A featureless frame cannot support portion or ingredient estimates.
    /// This gate runs before sending any image to the analysis service.
    static func hasVisibleDetail(_ samples: [UInt8]) -> Bool {
        guard samples.count >= 64 else { return false }
        let count=Double(samples.count)
        let mean=samples.reduce(0.0) { $0+Double($1) }/count
        let variance=samples.reduce(0.0) { $0+pow(Double($1)-mean,2) }/count
        return variance >= 4
    }
}
