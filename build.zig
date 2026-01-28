const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // Library source files (shared across targets)
    const lib_sources: []const []const u8 = &.{
        "lib/draw/line.c",
        "lib/draw/pixel.c",
        "lib/effects/gamma.c",
        "lib/effects/grain.c",
        "lib/effects/vignette.c",
        "lib/geometry/intersect.c",
        "lib/geometry/prism.c",
        "lib/geometry/segment.c",
        "lib/layers/background.c",
        "lib/layers/gradient.c",
        "lib/layers/markers.c",
        "lib/layers/prism_glow.c",
        "lib/layers/rays.c",
        "lib/pipeline.c",
        "lib/quantize/direct.c",
        "lib/quantize/dither_error.c",
        "lib/quantize/dither_ordered.c",
        "lib/quantize/dither.c",
        "lib/scene.c",
    };

    const c_flags: []const []const u8 = &.{
        "-std=c23",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-fwrapv", // Allow signed integer wrapping (matches Clang default)
    };

    // =========================================================================
    // WASM Target (stdlib-free)
    // =========================================================================
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const wasm = b.addExecutable(.{
        .name = "index",
        .root_module = b.createModule(.{
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .link_libc = false,
            .red_zone = false,
            .strip = true,
        }),
    });

    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.import_memory = true;
    wasm.want_lto = true;

    const wasm_flags: []const []const u8 = &.{
        "-std=c23",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-fwrapv", // Allow signed integer wrapping (matches Clang default)
        "-flto",
        "-mbulk-memory",
        "-msimd128",
    };

    wasm.root_module.addCSourceFile(.{ .file = b.path("bin/wasm/main.c"), .flags = wasm_flags });
    for (lib_sources) |src| {
        wasm.root_module.addCSourceFile(.{ .file = b.path(src), .flags = wasm_flags });
    }
    wasm.root_module.addIncludePath(b.path("lib"));

    const wasm_install = b.addInstallArtifact(wasm, .{
        .dest_dir = .{ .override = .{ .custom = "../public" } },
    });

    const wasm_step = b.step("wasm", "Build the WASM module");
    wasm_step.dependOn(&wasm_install.step);

    // =========================================================================
    // Zig WASM Target (alternative renderer in pure Zig)
    // =========================================================================
    const zig_wasm = b.addExecutable(.{
        .name = "zig-renderer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/wasm-zig/main.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .strip = true,
            .imports = &.{
                .{ .name = "watchface", .module = b.createModule(.{
                    .root_source_file = b.path("lib/zig/root.zig"),
                    .target = wasm_target,
                    .optimize = .ReleaseSmall,
                }) },
            },
        }),
    });

    zig_wasm.entry = .disabled;
    zig_wasm.rdynamic = true;
    zig_wasm.import_memory = true;
    zig_wasm.want_lto = true;

    const zig_wasm_install = b.addInstallArtifact(zig_wasm, .{
        .dest_dir = .{ .override = .{ .custom = "../public" } },
    });

    const zig_wasm_step = b.step("zig-wasm", "Build the Zig WASM module");
    zig_wasm_step.dependOn(&zig_wasm_install.step);

    // =========================================================================
    // Inky Target (native, links libm)
    // =========================================================================
    const inky = b.addExecutable(.{
        .name = "watchface",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const inky_sources: []const []const u8 = &.{
        "bin/inky/display.c",
        "bin/inky/gpio.c",
        "bin/inky/main.c",
        "bin/inky/pack.c",
        "bin/inky/spi.c",
    };

    for (inky_sources) |src| {
        inky.root_module.addCSourceFile(.{ .file = b.path(src), .flags = c_flags });
    }
    // Inky doesn't need grain/vignette/dither_ordered
    const inky_lib_sources: []const []const u8 = &.{
        "lib/draw/line.c",
        "lib/draw/pixel.c",
        "lib/effects/gamma.c",
        "lib/geometry/intersect.c",
        "lib/geometry/prism.c",
        "lib/geometry/segment.c",
        "lib/layers/background.c",
        "lib/layers/gradient.c",
        "lib/layers/markers.c",
        "lib/layers/prism_glow.c",
        "lib/layers/rays.c",
        "lib/pipeline.c",
        "lib/quantize/direct.c",
        "lib/quantize/dither_error.c",
        "lib/quantize/dither.c",
        "lib/scene.c",
    };
    for (inky_lib_sources) |src| {
        inky.root_module.addCSourceFile(.{ .file = b.path(src), .flags = c_flags });
    }
    inky.root_module.addIncludePath(b.path("lib"));
    inky.root_module.linkSystemLibrary("m", .{});

    const inky_install = b.addInstallArtifact(inky, .{
        .dest_dir = .{ .override = .{ .custom = "../bin/inky" } },
    });

    const inky_step = b.step("inky", "Build the Inky e-ink binary");
    inky_step.dependOn(&inky_install.step);

    // =========================================================================
    // Tests
    // =========================================================================
    const Test = struct {
        name: []const u8,
        deps: []const []const u8,
    };

    const tests: []const Test = &.{
        .{ .name = "gamma", .deps = &.{"lib/effects/gamma.c"} },
        .{ .name = "grain", .deps = &.{"lib/effects/grain.c"} },
        .{ .name = "dither", .deps = &.{ "lib/quantize/dither.c", "lib/quantize/dither_error.c", "lib/quantize/dither_ordered.c" } },
        .{ .name = "vignette", .deps = &.{"lib/effects/vignette.c"} },
        .{ .name = "pipeline", .deps = &.{ "lib/pipeline.c", "lib/effects/gamma.c", "lib/effects/grain.c", "lib/effects/vignette.c" } },
        .{ .name = "prism", .deps = &.{"lib/geometry/prism.c"} },
        .{ .name = "intersect", .deps = &.{ "lib/geometry/intersect.c", "lib/geometry/prism.c" } },
        .{ .name = "segment", .deps = &.{"lib/geometry/segment.c"} },
        .{ .name = "pixel", .deps = &.{"lib/draw/pixel.c"} },
        .{ .name = "line", .deps = &.{ "lib/draw/line.c", "lib/draw/pixel.c", "lib/geometry/segment.c", "lib/geometry/prism.c" } },
        .{ .name = "background", .deps = &.{"lib/layers/background.c"} },
        .{ .name = "rays", .deps = &.{ "lib/layers/rays.c", "lib/geometry/prism.c", "lib/geometry/intersect.c", "lib/geometry/segment.c", "lib/draw/line.c", "lib/draw/pixel.c" } },
        .{ .name = "gradient", .deps = &.{ "lib/layers/gradient.c", "lib/geometry/prism.c" } },
        .{ .name = "prism_glow", .deps = &.{ "lib/layers/prism_glow.c", "lib/geometry/prism.c", "lib/geometry/segment.c", "lib/draw/pixel.c" } },
        .{ .name = "markers", .deps = &.{ "lib/layers/markers.c", "lib/draw/line.c", "lib/draw/pixel.c", "lib/geometry/segment.c", "lib/geometry/prism.c" } },
        .{ .name = "scene", .deps = &.{ "lib/scene.c", "lib/layers/background.c", "lib/layers/rays.c", "lib/layers/gradient.c", "lib/layers/prism_glow.c", "lib/layers/markers.c", "lib/geometry/prism.c", "lib/geometry/intersect.c", "lib/geometry/segment.c", "lib/draw/line.c", "lib/draw/pixel.c", "lib/effects/gamma.c" } },
    };

    const test_step = b.step("test", "Build and run all tests");

    // -------------------------------------------------------------------------
    // Zig tests (native Zig library)
    // -------------------------------------------------------------------------
    // const zig_lib = b.createModule(.{
    //     .root_source_file = b.path("lib/zig/root.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const band_test = b.addTest(.{
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("tests/band_test.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         .imports = &.{
    //             .{ .name = "watchface", .module = zig_lib },
    //         },
    //     }),
    // });

    // const run_band_test = b.addRunArtifact(band_test);
    // test_step.dependOn(&run_band_test.step);

    // -------------------------------------------------------------------------
    // C tests
    // -------------------------------------------------------------------------
    for (tests) |t| {
        const test_exe = b.addExecutable(.{
            .name = b.fmt("{s}_test", .{t.name}),
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });

        const test_file = b.fmt("tests/{s}_test.c", .{t.name});
        test_exe.root_module.addCSourceFile(.{ .file = b.path(test_file), .flags = c_flags });

        for (t.deps) |dep| {
            test_exe.root_module.addCSourceFile(.{ .file = b.path(dep), .flags = c_flags });
        }
        test_exe.root_module.addIncludePath(b.path("lib"));
        test_exe.root_module.linkSystemLibrary("m", .{});

        const run_test = b.addRunArtifact(test_exe);
        test_step.dependOn(&run_test.step);
    }

    // =========================================================================
    // Default step builds everything
    // =========================================================================
    b.default_step.dependOn(wasm_step);
    b.default_step.dependOn(inky_step);
}
