const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const lib_c_sources: []const []const u8 = &.{
        "lib/c/draw/line.c",
        "lib/c/draw/pixel.c",
        "lib/c/effects/gamma.c",
        "lib/c/effects/grain.c",
        "lib/c/effects/vignette.c",
        "lib/c/geometry/intersect.c",
        "lib/c/geometry/prism.c",
        "lib/c/geometry/segment.c",
        "lib/c/layers/background.c",
        "lib/c/layers/gradient.c",
        "lib/c/layers/markers.c",
        "lib/c/layers/prism_glow.c",
        "lib/c/layers/rays.c",
        "lib/c/pipeline.c",
        "lib/c/quantize/direct.c",
        "lib/c/quantize/dither_error.c",
        "lib/c/quantize/dither_ordered.c",
        "lib/c/quantize/dither.c",
        "lib/c/scene.c",
    };

    const c_flags: []const []const u8 = &.{
        "-std=c23",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-fwrapv", // Allow signed integer wrapping (matches Clang default)
    };

    // =========================================================================
    // WASM C Target (stdlib-free)
    // =========================================================================

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_features_add = std.Target.wasm.featureSet(&.{ .bulk_memory, .simd128 }),
    });

    const wasm_c = b.addExecutable(.{
        .name = "index-c",
        .root_module = b.createModule(.{
            .target = wasm_target,
            .optimize = .ReleaseFast,
            .link_libc = false,
            .red_zone = false,
            .strip = true,
        }),
    });

    wasm_c.entry = .disabled;
    wasm_c.rdynamic = true;
    wasm_c.import_memory = true;
    wasm_c.lto = .full;

    const wasm_c_flags = c_flags ++ .{
        "-flto",
        "-mbulk-memory",
        "-msimd128",
    };

    wasm_c.root_module.addCSourceFile(.{
        .file = b.path("bin/wasm-c/main.c"),
        .flags = wasm_c_flags,
    });

    for (lib_c_sources) |src| {
        wasm_c.root_module.addCSourceFile(.{ .file = b.path(src), .flags = wasm_c_flags });
    }

    wasm_c.root_module.addIncludePath(b.path("lib/c"));

    const wasm_c_install = b.addInstallArtifact(wasm_c, .{
        .dest_dir = .{ .override = .{ .custom = "../public" } },
    });

    const wasm_c_step = b.step("wasm", "Build the WASM C module");

    wasm_c_step.dependOn(&wasm_c_install.step);

    // =========================================================================
    // WASM Zig Target
    // =========================================================================

    const wasm_zig = b.addExecutable(.{
        .name = "index-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/wasm-zig/main.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .strip = true,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/zig/root.zig"),
                    .target = wasm_target,
                    .optimize = .ReleaseSmall,
                    .strip = true,
                }) },
            },
        }),
    });

    wasm_zig.entry = .disabled;
    wasm_zig.rdynamic = true;
    wasm_zig.import_memory = true;
    wasm_zig.lto = .full;

    const wasm_zig_install = b.addInstallArtifact(wasm_zig, .{
        .dest_dir = .{ .override = .{ .custom = "../public" } },
    });

    const wasm_zig_step = b.step("zig-wasm", "Build the WASM Zig module");

    wasm_zig_step.dependOn(&wasm_zig_install.step);

    // =========================================================================
    // Check step for ZLS (uses native target for analysis)
    // =========================================================================

    const wasm_zig_check = b.addExecutable(.{
        .name = "index-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/wasm-zig/main.zig"),
            .target = wasm_target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/zig/root.zig"),
                    .target = wasm_target,
                    .optimize = .ReleaseFast,
                }) },
            },
        }),
    });

    wasm_zig_check.entry = .disabled;
    wasm_zig_check.rdynamic = true;
    wasm_zig_check.import_memory = true;
    wasm_zig_check.lto = .full;

    const check_step = b.step("check", "Check Zig code for errors (used by ZLS)");

    check_step.dependOn(&wasm_zig_check.step);

    // =========================================================================
    // Tests
    // =========================================================================

    const test_step = b.step("test", "Build and run all tests");

    const zig_lib = b.createModule(.{
        .root_source_file = b.path("lib/zig/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zig_lib_tests = b.addTest(.{ .root_module = zig_lib });
    const run_zig_lib_tests = b.addRunArtifact(zig_lib_tests);

    test_step.dependOn(&run_zig_lib_tests.step);

    // =========================================================================
    // Default step builds everything
    // =========================================================================

    b.default_step.dependOn(wasm_c_step);
    b.default_step.dependOn(wasm_zig_step);
}
