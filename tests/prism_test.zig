const std = @import("std");
const testing = std.testing;
const lib = @import("lib");

const prism = lib.prism;
const vec2 = lib.vec2;

test "containsPoint inside triangle" {
    const tri = prism.Prism.init(vec2.xy(100, 100), 60);

    // Centroid should be inside
    const cent = tri.centroid();
    try testing.expect(tri.containsPoint(cent[0], cent[1]));
}

test "containsPoint outside triangle" {
    const tri = prism.Prism.init(vec2.xy(100, 100), 60);

    // Points clearly outside
    try testing.expect(!tri.containsPoint(0, 100)); // far left
    try testing.expect(!tri.containsPoint(200, 100)); // far right
    try testing.expect(!tri.containsPoint(100, 0)); // far above
    try testing.expect(!tri.containsPoint(100, 200)); // far below
}

test "containsPoint on edge" {
    const tri = prism.Prism.init(vec2.xy(100, 100), 60);

    // Point on base edge (bottom, between bottom_right and bottom_left)
    const v1 = tri.vertices.get(.bottom_right);
    const v2 = tri.vertices.get(.bottom_left);
    const mid_base_x = (v1[0] + v2[0]) / 2;
    const mid_base_y = (v1[1] + v2[1]) / 2;
    try testing.expect(tri.containsPoint(mid_base_x, mid_base_y));
}

test "scanlineRange returns correct bounds" {
    // Equilateral: h = base * sqrt(3)/2, apex_offset = base * sqrt(3)/3, base_offset = base * sqrt(3)/6
    // With base=60, center=(100,100): apex at ~(100, 65.4), base at y~117.3
    const tri = prism.Prism.init(vec2.xy(100, 100), 60);

    // Middle scanline at y=100 (center)
    const r = tri.scanlineRange(100);
    try testing.expect(r != null);

    // At center, width should be ~2/3 of base = 40, so x from 80 to 120
    try testing.expectApproxEqAbs(r.?.x_min, 80, 1);
    try testing.expectApproxEqAbs(r.?.x_max, 120, 1);
}

test "scanlineRange outside triangle returns null" {
    const tri = prism.Prism.init(vec2.xy(100, 100), 60);

    // Above triangle (apex is at ~65.4)
    try testing.expect(tri.scanlineRange(60) == null);

    // Below triangle (base is at ~117.3)
    try testing.expect(tri.scanlineRange(125) == null);
}

test "scanlineRange at vertices" {
    const tri = prism.Prism.init(vec2.xy(100, 100), 60);
    const sqrt3 = @sqrt(3.0);
    const apex_y = 100.0 - 60.0 * sqrt3 / 3.0;
    const base_y = 100.0 + 60.0 * sqrt3 / 6.0;

    // At top (apex)
    const range_top = tri.scanlineRange(apex_y);
    try testing.expect(range_top != null);
    try testing.expectApproxEqAbs(range_top.?.x_min, 100, 1);
    try testing.expectApproxEqAbs(range_top.?.x_max, 100, 1);

    // At bottom (base)
    const range_bottom = tri.scanlineRange(base_y);
    try testing.expect(range_bottom != null);
    try testing.expectApproxEqAbs(range_bottom.?.x_min, 70, 1);
    try testing.expectApproxEqAbs(range_bottom.?.x_max, 130, 1);
}

test "equilateral creates symmetric triangle" {
    const center = vec2.xy(100, 100);
    const base = 50.0;
    const tri = prism.Prism.init(center, base);

    const cent = tri.centroid();
    try testing.expectApproxEqAbs(cent[0], 100, 1);
    try testing.expectApproxEqAbs(cent[1], 100, 1);

    // Check symmetry: bottom_right and bottom_left should be equidistant from center
    const v1 = tri.vertices.get(.bottom_right);
    const v2 = tri.vertices.get(.bottom_left);
    const d1 = @sqrt((v1[0] - center[0]) * (v1[0] - center[0]) + (v1[1] - center[1]) * (v1[1] - center[1]));
    const d2 = @sqrt((v2[0] - center[0]) * (v2[0] - center[0]) + (v2[1] - center[1]) * (v2[1] - center[1]));
    try testing.expectApproxEqAbs(d1, d2, 0.1);
}

test "minY and maxY" {
    // Equilateral with base=60, center=(100,100)
    // apex_offset = 60 * sqrt(3)/3 ~ 34.64, base_offset = 60 * sqrt(3)/6 ~ 17.32
    const tri = prism.Prism.init(vec2.xy(100, 100), 60);
    const sqrt3 = @sqrt(3.0);

    try testing.expectApproxEqAbs(tri.minY(), 100.0 - 60.0 * sqrt3 / 3.0, 1);
    try testing.expectApproxEqAbs(tri.maxY(), 100.0 + 60.0 * sqrt3 / 6.0, 1);
}

test "vertices returns correct values" {
    // Equilateral: apex_offset = base * sqrt(3)/3, base_offset = base * sqrt(3)/6
    const tri = prism.Prism.init(vec2.xy(100, 100), 60);
    const sqrt3 = @sqrt(3.0);
    const apex_offset = 60.0 * sqrt3 / 3.0;
    const base_offset = 60.0 * sqrt3 / 6.0;

    const v0 = tri.vertices.get(.apex);
    const v1 = tri.vertices.get(.bottom_right);
    const v2 = tri.vertices.get(.bottom_left);

    // apex
    try testing.expectApproxEqAbs(v0[0], 100, 1);
    try testing.expectApproxEqAbs(v0[1], 100 - apex_offset, 1);

    // v1 = bottom-right
    try testing.expectApproxEqAbs(v1[0], 130, 1);
    try testing.expectApproxEqAbs(v1[1], 100 + base_offset, 1);

    // v2 = bottom-left
    try testing.expectApproxEqAbs(v2[0], 70, 1);
    try testing.expectApproxEqAbs(v2[1], 100 + base_offset, 1);
}
