const std = @import("std");

const band = @import("band.zig");
const color = @import("color.zig");
const dither = @import("dither.zig");
const effect = @import("effect.zig");
const grain_effect = @import("effect/grain.zig");
const vignette_effect = @import("effect/vignette.zig");
const gamma = @import("gamma.zig");
const glow = @import("glow.zig");
const palette = @import("palette.zig");
const scene = @import("scene.zig");

/// Falloff type matching C FalloffType enum.
pub const FalloffType = enum(i32) {
    linear = 0,
    quadratic = 1,
    cubic = 2,
    exponential = 3,

    pub fn toZig(self: FalloffType) glow.Falloff {
        return switch (self) {
            .linear => .linear,
            .quadratic => .quadratic,
            .cubic => .cubic,
            .exponential => .exponential,
        };
    }
};

/// Ray palette matching C RayPalette enum.
pub const RayPalette = enum(i32) {
    oklch_balanced = 0,
    saturated = 1,
    spectral = 2,
    neon = 3,
    muted = 4,
    eink_pure = 5,
    eink_dither = 6,
    eink_full = 7,
    album_cover = 8,
    spectra6 = 9,

    pub fn toZig(self: RayPalette) palette.Type {
        return @enumFromInt(@intFromEnum(self));
    }
};

/// Prism configuration matching C PrismConfig.
pub const PrismConfig = extern struct {
    size: f32,
    rainbow_spread: f32,
};

/// Glow configuration matching C GlowConfig.
pub const GlowConfig = extern struct {
    r: i32,
    g: i32,
    b: i32,
    width: f32,
    intensity: f32,
    falloff: FalloffType,
};

/// Ray configuration matching C RayConfig.
pub const RayConfig = extern struct {
    glow_width: f32,
    intensity: f32,
    falloff: FalloffType,
    ray_palette: RayPalette,
    gradient_fill: i32,
    reverse: i32,
};

/// Marker configuration matching C MarkerConfig.
pub const MarkerConfig = extern struct {
    visible: i32,
    length: f32,
    glow_width: f32,
    glow_intensity: f32,
    falloff: FalloffType,
};

/// Grain configuration matching C GrainConfig.
pub const GrainConfig = extern struct {
    intensity: f32,
    scale: f32,
    threshold: f32,
    prism_only: i32,
};

/// Vignette configuration matching C VignetteConfig.
pub const VignetteConfig = extern struct {
    enabled: i32,
    strength: f32,
    background: f32,
};

/// Dither error algorithm matching C DitherErrorAlgorithm.
pub const DitherErrorAlgorithm = enum(i32) {
    atkinson = 0,
    floyd_steinberg = 1,
};

/// Dither ordered matrix matching C DitherOrderedMatrix.
pub const DitherOrderedMatrix = enum(i32) {
    bayer_2x2 = 0,
    bayer_4x4 = 1,
    bayer_8x8 = 2,
    blue_noise_64 = 3,
};

/// Dither palette mode matching C DitherPaletteMode.
pub const DitherPaletteMode = enum(i32) {
    ideal = 0,
    spectra6_inky = 1,
    spectra6_epdopt = 2,
};

/// Dither type matching C DitherType.
pub const DitherType = enum(i32) {
    error_diffusion = 0,
    ordered = 1,
};

/// Scene dither configuration matching C SceneDitherConfig.
pub const SceneDitherConfig = extern struct {
    enabled: i32,
    dither_type: DitherType,
    mode: DitherPaletteMode,
    strength: f32,
    algorithm: DitherErrorAlgorithm,
    oklab_error: i32,
    ordered_matrix: DitherOrderedMatrix,
    spread: f32,
    chroma_weight: f32,
};

/// Complete watchface configuration matching C WatchfaceConfig.
/// Field layout must match the TypeScript definition in src/config.ts.
pub const WatchfaceConfig = extern struct {
    hour: i32,
    minute: f32,
    prism: PrismConfig,
    glow_config: GlowConfig,
    ray: RayConfig,
    marker: MarkerConfig,
    grain: GrainConfig,
    vignette: VignetteConfig,
    dither: SceneDitherConfig,
    entry_u: f32,
    exit_u: f32,
};

/// Convert C config to Zig scene config types.
pub fn toSceneConfig(c: *const WatchfaceConfig) struct {
    prism: scene.PrismConfig,
    glow_config: scene.GlowConfig,
    ray: scene.RayConfig,
    marker: scene.MarkerConfig,
} {
    return .{
        .prism = .{
            .size = c.prism.size,
            .rainbow_spread = c.prism.rainbow_spread,
        },
        .glow_config = .{
            .color = color.rgb(
                @as(f32, @floatFromInt(c.glow_config.r)) / 255.0,
                @as(f32, @floatFromInt(c.glow_config.g)) / 255.0,
                @as(f32, @floatFromInt(c.glow_config.b)) / 255.0,
            ),
            .width = c.glow_config.width,
            .intensity = c.glow_config.intensity,
            .falloff = c.glow_config.falloff.toZig(),
        },
        .ray = .{
            .glow_width = c.ray.glow_width,
            .intensity = c.ray.intensity,
            .falloff = c.ray.falloff.toZig(),
            .palette_type = c.ray.ray_palette.toZig(),
            .gradient_fill = c.ray.gradient_fill != 0,
            .reverse = c.ray.reverse != 0,
        },
        .marker = .{
            .visible = c.marker.visible != 0,
            .length = c.marker.length,
            .glow_width = c.marker.glow_width,
            .glow_intensity = c.marker.glow_intensity,
            .falloff = c.marker.falloff.toZig(),
        },
    };
}

/// Convert C grain config to Zig grain config.
pub fn toGrainConfig(c: *const GrainConfig) grain_effect.Config {
    return .{
        .intensity = c.intensity,
        .scale = c.scale,
        .threshold = c.threshold,
        .prism_only = c.prism_only != 0,
    };
}

/// Convert C vignette config to Zig vignette config.
pub fn toVignetteConfig(c: *const VignetteConfig) vignette_effect.Config {
    return .{
        .enabled = c.enabled != 0,
        .strength = c.strength,
        .background = c.background,
    };
}

/// Convert C dither config to Zig error diffusion config.
pub fn toErrorDiffusionConfig(c: *const SceneDitherConfig) dither.error_diffusion.Config {
    return .{
        .algorithm = switch (c.algorithm) {
            .atkinson => .atkinson,
            .floyd_steinberg => .floyd_steinberg,
        },
        .strength = c.strength,
        .chroma_weight = c.chroma_weight,
        .oklab_error = c.oklab_error != 0,
    };
}

/// Convert C dither config to Zig ordered dither config.
pub fn toOrderedDitherConfig(c: *const SceneDitherConfig) dither.ordered.Config {
    return .{
        .matrix = switch (c.ordered_matrix) {
            .bayer_2x2 => .bayer2x2,
            .bayer_4x4 => .bayer4x4,
            .bayer_8x8 => .bayer8x8,
            .blue_noise_64 => .blue_noise,
        },
        .spread = c.spread,
        .chroma_weight = c.chroma_weight,
    };
}

/// Convert C dither palette mode to Zig palette type.
pub fn toDitherPaletteType(mode: DitherPaletteMode) dither.PaletteType {
    return switch (mode) {
        .ideal => .ideal,
        .spectra6_inky => .spectra6_inky,
        .spectra6_epdopt => .spectra6_epdopt,
    };
}
