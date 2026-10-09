import Foundation

/// Admission policy, not an iOS memory guarantee. The caller must sample the
/// process's current allowance again after downloads and during inference.
enum VisionResources {
    enum Tier: String, Codable { case compact, full }
    static let MiB = 1024 * 1024
    static let stopHeadroom = 256 * MiB

    static func requiredBytes(weights: Int, tier: Tier) -> Int {
        // Reserve room beyond the weights for tokenizer, vision activations,
        // conversation KV cache and the app. Physical RAM is not the app limit.
        weights + (tier == .compact ? 1024 : 1792) * MiB
    }

    static func choose(available: Int, physical: UInt64, mobile: Bool,
                       compactWeights: Int, fullWeights: Int,
                       preferCompact: Bool = false) -> Tier? {
        guard available > 0, compactWeights > 0, fullWeights > 0 else { return nil }
        let conservative = preferCompact || (mobile && physical < 11_000_000_000)
        if !conservative, available >= requiredBytes(weights: fullWeights, tier: .full) { return .full }
        if available >= requiredBytes(weights: compactWeights, tier: .compact) { return .compact }
        return nil
    }

    static func imagePixels(_ tier: Tier) -> Int { tier == .compact ? 560 : 672 }
    static func prefillStep(_ tier: Tier) -> Int { tier == .compact ? 64 : 128 }
}
