const std = @import("std");

const lib = @import("lib");

// Freestanding: keep the panic path from pulling newlib's abort — and its _exit /
// _kill / _getpid syscall stubs, absent on Pebble — into the app link. A trap is
// enough; a render fault just leaves the framebuffer untouched for that strip.
pub const panic = std.debug.FullPanic(struct {
    fn handler(_: []const u8, _: ?usize) noreturn {
        @trap();
    }
}.handler);

const width = 260;
const band_height = 1;

const config = lib.Config{
    .background_enabled = false,
    .prism_normalized_size = 0.9,
    .prism_glow_linear_green = 0.75,
    .prism_glow_normalized_width = 0.07,
    .rainbow_normalized_spread = 0.5,
    .hand_glow_normalized_width = 0.02,
    .rainbow_palette_id = .oklch_balanced,
    .texture = .dither_pebble,
    .grain_normalized_deviation = 0.1,
    .supersample_enabled = true,
};

// Derived from config so linear_buffer's size always matches the factor renderBand uses.
const supersample = lib.frame.supersampleFactor(config);

const image = lib.Image.init(width, width);

// Frame-scoped scratch reused across bands; sized at comptime so the app carries no
// allocator. linear_buffer holds the supersampled strip, srgb_buffer the downsampled
// one. dither_error_buffer persists Floyd–Steinberg's pending row errors between
// bands and is zeroed by renderBand when band_index 0 is rendered.
var linear_buffer: [width * band_height * supersample * supersample]lib.Linear = undefined;
var srgb_buffer: [width * band_height]lib.Srgb = undefined;
var dither_error_buffer: [lib.dither_pebble.errorBufferSize(width)]f32 = undefined;

/// Renders strip `band_index` of the frame into `out` as one GColor8 byte per pixel
/// (`AARRGGBB`, opaque). Bands must be rendered top-to-bottom (0, 1, 2, …): the dither
/// diffuses error downward and keeps it in `dither_error_buffer` between calls.
export fn pebbleRenderBand(out: [*]u8, band_index: u16, hour: u8, minute: u8) callconv(.c) void {
    const band = lib.frame.renderBand(
        config,
        lib.Time.init(hour, @floatFromInt(minute)),
        image,
        band_height,
        band_index,
        &linear_buffer,
        &srgb_buffer,
        &dither_error_buffer,
    ) catch return;

    // Dither already snapped every channel to {0, 85, 170, 255}, so >> 6 yields the
    // 0–3 cube level directly; pack it with an opaque alpha (0b11) prefix.
    for (band.buffer, 0..) |pixel, x| {
        out[x] = 0xC0 | ((pixel.r >> 6) << 4) | ((pixel.g >> 6) << 2) | (pixel.b >> 6);
    }
}
