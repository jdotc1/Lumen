import Foundation

/// Optional theme-level geometry, typography, motion and depth. Unspecified members inherit from the
/// parent theme; after inheritance, unspecified members keep the app's default metrics.
public struct LumenThemeMetrics: Hashable, Sendable, Codable {
    /// A metric a pack can lock to preserve its measured layout.
    public enum Key: String, CaseIterable, Hashable, Sendable, Codable {
        case radiusProfile, typeScale, spacingScale, motion, depth
    }

    /// Explicit theme ramps stay within half the smallest 24 pt control height. The standard
    /// theme ramp is 4/6/8/10/12 pt; rounded is 6/8/10/12/12 pt. Omitting this field preserves
    /// the app's radius ramp, including its larger card and panel corners.
    public enum RadiusProfile: Hashable, Sendable, Codable {
        case standard
        case rounded
        case uniform(Double)

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                self = .uniform(value)
                return
            }
            switch try container.decode(String.self) {
            case "standard": self = .standard
            case "rounded": self = .rounded
            default:
                throw DecodingError.dataCorruptedError(in: container,
                    debugDescription: "radiusProfile must be standard, rounded, or a uniform radius in points")
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .standard: try container.encode("standard")
            case .rounded: try container.encode("rounded")
            case .uniform(let value): try container.encode(value)
            }
        }
    }

    public enum Motion: String, CaseIterable, Hashable, Sendable, Codable {
        case standard, reduced, none
    }

    public var radiusProfile: RadiusProfile?
    public var typeScale: Double?
    public var spacingScale: Double?
    public var motion: Motion?
    /// Optional shadows and glows, merged leaf by leaf before applying standard defaults.
    public var depth: LumenThemeDepth?

    public init(radiusProfile: RadiusProfile? = nil, typeScale: Double? = nil,
                spacingScale: Double? = nil, motion: Motion? = nil) {
        self.radiusProfile = radiusProfile
        self.typeScale = typeScale
        self.spacingScale = spacingScale
        self.motion = motion
    }

    /// Adds depth overrides while retaining the original initializer's signature.
    public init(radiusProfile: RadiusProfile? = nil, typeScale: Double? = nil,
                spacingScale: Double? = nil, motion: Motion? = nil, depth: LumenThemeDepth?) {
        self.init(radiusProfile: radiusProfile, typeScale: typeScale, spacingScale: spacingScale, motion: motion)
        self.depth = depth
    }

    /// Members explicitly supplied by this value, including neutral values such as a scale of 1.
    public var keys: Set<Key> {
        var result: Set<Key> = []
        if radiusProfile != nil { result.insert(.radiusProfile) }
        if typeScale != nil { result.insert(.typeScale) }
        if spacingScale != nil { result.insert(.spacingScale) }
        if motion != nil { result.insert(.motion) }
        if depth != nil { result.insert(.depth) }
        return result
    }

    /// This value with each specified member of `overrides` laid on top.
    public func merging(_ overrides: LumenThemeMetrics?) -> LumenThemeMetrics {
        guard let overrides else { return self }
        return LumenThemeMetrics(radiusProfile: overrides.radiusProfile ?? radiusProfile,
                                 typeScale: overrides.typeScale ?? typeScale,
                                 spacingScale: overrides.spacingScale ?? spacingScale,
                                 motion: overrides.motion ?? motion,
                                 depth: depth.map { $0.merging(overrides.depth) } ?? overrides.depth)
    }
}
