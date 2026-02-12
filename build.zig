const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // =========================================================================
    // WASM
    // =========================================================================

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_features_add = std.Target.wasm.featureSet(&.{ .bulk_memory, .simd128 }),
    });

    const wasm_exe = b.addExecutable(.{
        .name = "index",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/wasm/main.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .strip = true,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = wasm_target,
                    .optimize = .ReleaseSmall,
                    .strip = true,
                }) },
            },
        }),
    });

    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;
    wasm_exe.import_memory = true;
    wasm_exe.lto = .full;

    const wasm_install = b.addInstallArtifact(wasm_exe, .{
        .dest_dir = .{ .override = .{ .custom = "../public" } },
    });

    const wasm_step = b.step("wasm", "Build the WASM module");

    wasm_step.dependOn(&wasm_install.step);

    // =========================================================================
    // Profile binary (native, for valgrind/callgrind)
    // =========================================================================

    const profile_exe = b.addExecutable(.{
        .name = "profile",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/profile/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
            },
        }),
    });

    const profile_install = b.addInstallArtifact(profile_exe, .{});

    const profile_step = b.step("profile", "Build the profiling binary");

    profile_step.dependOn(&profile_install.step);

    // =========================================================================
    // PNG export binary (native, renders to PNG file)
    // =========================================================================

    const png_exe = b.addExecutable(.{
        .name = "png",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/png/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
            },
        }),
    });

    const png_install = b.addInstallArtifact(png_exe, .{});

    const png_step = b.step("png", "Build the PNG export binary");

    png_step.dependOn(&png_install.step);

    // =========================================================================
    // Inky display binary (native, drives Inky Impression 13.3" over SPI)
    // =========================================================================

    const inky_exe = b.addExecutable(.{
        .name = "inky",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/inky/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
            },
        }),
    });

    const inky_install = b.addInstallArtifact(inky_exe, .{});

    const inky_step = b.step("inky", "Build the Inky display binary");

    inky_step.dependOn(&inky_install.step);

    // =========================================================================
    // Check step for ZLS (uses native target for analysis)
    // =========================================================================

    const wasm_check = b.addExecutable(.{
        .name = "index",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/wasm/main.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = wasm_target,
                    .optimize = .ReleaseSmall,
                }) },
            },
        }),
    });

    wasm_check.entry = .disabled;
    wasm_check.rdynamic = true;
    wasm_check.import_memory = true;
    wasm_check.lto = .full;

    const profile_check = b.addExecutable(.{
        .name = "profile",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/profile/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
            },
        }),
    });

    const png_check = b.addExecutable(.{
        .name = "png",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/png/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
            },
        }),
    });

    const inky_check = b.addExecutable(.{
        .name = "inky",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/inky/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
            },
        }),
    });

    const check_step = b.step("check", "Check Zig code for errors (used by ZLS)");

    check_step.dependOn(&wasm_check.step);
    check_step.dependOn(&profile_check.step);
    check_step.dependOn(&png_check.step);
    check_step.dependOn(&inky_check.step);

    // =========================================================================
    // Tests
    // =========================================================================

    const test_step = b.step("test", "Build and run all tests");

    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);

    test_step.dependOn(&run_lib_tests.step);

    // =========================================================================
    // Default step builds WASM
    // =========================================================================

    b.default_step.dependOn(wasm_step);
    b.default_step.dependOn(check_step);
}
