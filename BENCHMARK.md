# Performance Benchmark Analysis

## Summary

The Zig implementation is **~25% slower** than the C implementation, executing **~29% more
instructions**.

| Metric                  | Zig   | C     |
| ----------------------- | ----- | ----- |
| Average frame time      | 245ms | 196ms |
| Instructions (5 frames) | 31.5B | 24.4B |
| FPS                     | 4.1   | 5.1   |

## Reproduction

### Build Benchmarks

```bash
zig build perf-zig -Doptimize=ReleaseFast
zig build perf-c -Doptimize=ReleaseFast
```

### Run Benchmarks

```bash
./zig-out/bin/perf-zig 100    # Render 100 frames
./zig-out/bin/perf-c 100      # Render 100 frames
```

### Profile with Callgrind

```bash
# Install valgrind if needed
sudo apt-get install -y valgrind

# Profile Zig version (use small frame count, it's slow under valgrind)
valgrind --tool=callgrind --callgrind-out-file=/tmp/callgrind-zig.out ./zig-out/bin/perf-zig 5

# Profile C version
valgrind --tool=callgrind --callgrind-out-file=/tmp/callgrind-c.out ./zig-out/bin/perf-c 5

# Analyze results
callgrind_annotate --auto=no --threshold=99 /tmp/callgrind-zig.out
callgrind_annotate --auto=no --threshold=99 /tmp/callgrind-c.out
```

## Profiling Results (Zig)

| Rank | Function              | % Time | Location                                 | Description                 |
| ---- | --------------------- | ------ | ---------------------------------------- | --------------------------- |
| 1    | `std.math.atan2`      | 18.08% | stdlib                                   | Per-pixel angle calculation |
| 2    | `gamma.linearToSrgb`  | 13.78% | `lib/zig/color/gamma.zig:13-18`          | Gamma correction            |
| 3    | `std.math.atan`       | 11.77% | stdlib                                   | Internal to atan2           |
| 4    | `gradient.render`     | 11.66% | `lib/zig/rendering/gradient.zig:105-152` | Main render loop            |
| 5    | `output.writeRgba`    | 9.16%  | `lib/zig/pipeline/output.zig:10-18`      | Float to byte conversion    |
| 6    | `std.math.atan`       | 7.06%  | stdlib                                   | Secondary atan calls        |
| 7    | `prism.containsPoint` | 5.97%  | `lib/zig/geometry/prism.zig:66-79`       | Point-in-triangle test      |
| 8    | `sincos`              | 5.00%  | `lib/zig/rendering/band.zig`             | Trig for band rendering     |

## Profiling Results (C)

| Rank | Function                   | % Time | Location                  | Description            |
| ---- | -------------------------- | ------ | ------------------------- | ---------------------- |
| 1    | `point_in_triangle`        | 19.79% | `lib/c/geometry/prism.c`  | Point-in-triangle test |
| 2    | `draw_gradient_continuous` | 16.04% | `lib/c/layers/rays.c`     | Gradient rendering     |
| 3    | `effect_gamma_apply`       | 14.84% | `lib/c/effects/gamma.c`   | Gamma correction       |
| 4    | `fastmath (gradient)`      | 14.48% | `lib/c/fastmath.h`        | Fast math in gradient  |
| 5    | `fastmath (gamma)`         | 11.27% | `lib/c/fastmath.h`        | Fast math in gamma     |
| 6    | `quantize_direct_apply`    | 4.84%  | `lib/c/quantize/direct.h` | Float to byte          |

## Root Cause Analysis

### 1. `atan2` Implementation (37% of Zig time)

**Problem:** Zig uses `std.math.atan2` which implements a full-precision Taylor series expansion.

**C Solution:** Uses a fast polynomial approximation in `lib/c/fastmath.h:91-113`:

```c
static inline float atan2_approx(float y, float x) {
  // Handle edge cases...
  float abs_y = fabsf_impl(y);
  float angle;
  if (x >= 0.0f) {
    float r = (x - abs_y) / (x + abs_y);
    angle = 0.1963f * r * r * r - 0.9817f * r + PI / 4.0f;
  } else {
    float r = (x + abs_y) / (abs_y - x);
    angle = 0.1963f * r * r * r - 0.9817f * r + 3.0f * PI / 4.0f;
  }
  return y < 0.0f ? -angle : angle;
}
```

**Zig Fix:** Implement equivalent `atan2Approx` function in `lib/zig/math/` and use it in
`gradient.zig:125`.

### 2. Gamma Correction (14% of Zig time)

**Problem:** Scalar per-channel processing without SIMD.

**Current Zig code** (`lib/zig/color/gamma.zig:20-26`):

```zig
pub fn applyToBuffer(buffer: []color.Color) void {
    for (buffer) |*c| {
        c.*[0] = linearToSrgb(std.math.clamp(c.*[0], 0.0, 1.0));
        c.*[1] = linearToSrgb(std.math.clamp(c.*[1], 0.0, 1.0));
        c.*[2] = linearToSrgb(std.math.clamp(c.*[2], 0.0, 1.0));
    }
}
```

**Zig Fix:** Since `color.Color` is already `@Vector(4, f32)`, implement vectorized gamma that
operates on all 4 channels simultaneously using SIMD intrinsics.

### 3. Output Conversion (9% of Zig time)

**Problem:** Per-pixel scalar conversion in `lib/zig/pipeline/output.zig:10-18`.

**Zig Fix:** Batch process using SIMD - convert 4 or 8 pixels at once using vector operations.

### 4. Point-in-Triangle Test (6% of Zig time)

**Problem:** Full barycentric calculation for every pixel.

**Current code** (`lib/zig/geometry/prism.zig:66-79`):

```zig
pub fn containsPoint(self: Prism, px: f32, py: f32) bool {
    // Full barycentric test every time
}
```

**Zig Fix:** Add bounding box early-out before barycentric test, or use scanline-based rejection
since the gradient loop iterates by row.

## Optimization Priority

| Priority | Optimization            | Expected Gain | Effort |
| -------- | ----------------------- | ------------- | ------ |
| 1        | Implement `atan2Approx` | ~30-35%       | Medium |
| 2        | SIMD gamma correction   | ~10-12%       | Medium |
| 3        | SIMD output conversion  | ~8-9%         | Low    |
| 4        | Bounding box early-out  | ~5%           | Low    |

## Implementation Plan

### Step 1: Fast atan2 approximation

Create `lib/zig/math/fastmath.zig`:

```zig
const std = @import("std");
const pi = std.math.pi;

pub fn atan2Approx(y: f32, x: f32) f32 {
    if (x == 0.0) {
        if (y > 0.0) return pi * 0.5;
        if (y < 0.0) return -pi * 0.5;
        return 0.0;
    }
    if (y == 0.0) {
        return if (x < 0.0) pi else 0.0;
    }

    const abs_y = @abs(y);
    const angle = if (x >= 0.0) blk: {
        const r = (x - abs_y) / (x + abs_y);
        break :blk 0.1963 * r * r * r - 0.9817 * r + pi / 4.0;
    } else blk: {
        const r = (x + abs_y) / (abs_y - x);
        break :blk 0.1963 * r * r * r - 0.9817 * r + 3.0 * pi / 4.0;
    };

    return if (y < 0.0) -angle else angle;
}
```

Then update `lib/zig/rendering/gradient.zig:125`:

```zig
// Before:
var pixel_angle = std.math.atan2(dy, dx);

// After:
var pixel_angle = fastmath.atan2Approx(dy, dx);
```

### Step 2: SIMD gamma

Update `lib/zig/color/gamma.zig` to process RGB channels as a vector:

```zig
pub fn linearToSrgbVec(linear: @Vector(4, f32)) @Vector(4, f32) {
    // Vectorized implementation
}
```

### Step 3: SIMD output

Update `lib/zig/pipeline/output.zig` to batch convert pixels.

## Files to Modify

1. `lib/zig/math/fastmath.zig` - Create new file with fast approximations
2. `lib/zig/rendering/gradient.zig:125` - Use `atan2Approx`
3. `lib/zig/color/gamma.zig` - SIMD vectorization
4. `lib/zig/pipeline/output.zig` - SIMD batch conversion
5. `lib/zig/geometry/prism.zig:66-79` - Add bounding box early-out

## Validation

After each optimization:

```bash
# Run tests to ensure correctness
npm test

# Compare performance
./zig-out/bin/perf-zig 100
./zig-out/bin/perf-c 100
```

Target: Zig performance within 5% of C implementation.
