const std = @import("std");
const lib = @import("lib");

const markers = lib.markers;

test "marker positions" {
    const geometry = markers.Geometry.init(100, 100, 50);
    const config = markers.Config{};
    const computed = markers.computeMarkers(geometry, config);

    // Get outer endpoints (start + dir gives the outer point)
    const m0_end = computed[0].segment.start + computed[0].segment.dir;
    const m3_end = computed[3].segment.start + computed[3].segment.dir;
    const m6_end = computed[6].segment.start + computed[6].segment.dir;
    const m9_end = computed[9].segment.start + computed[9].segment.dir;

    // 12 o'clock should be at top (y < center_y)
    try std.testing.expect(m0_end[1] < geometry.center_y);

    // 3 o'clock should be at right (x > center_x)
    try std.testing.expect(m3_end[0] > geometry.center_x);

    // 6 o'clock should be at bottom (y > center_y)
    try std.testing.expect(m6_end[1] > geometry.center_y);

    // 9 o'clock should be at left (x < center_x)
    try std.testing.expect(m9_end[0] < geometry.center_x);
}
