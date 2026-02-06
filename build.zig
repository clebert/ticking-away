const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // =========================================================================
    // WASM Target
    // =========================================================================

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_features_add = std.Target.wasm.featureSet(&.{ .bulk_memory, .simd128 }),
    });

    const wasm = b.addExecutable(.{
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
                .{ .name = "lib2", .module = b.createModule(.{
                    .root_source_file = b.path("lib2/root.zig"),
                    .target = wasm_target,
                    .optimize = .ReleaseSmall,
                    .strip = true,
                }) },
            },
        }),
    });

    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.import_memory = true;
    wasm.lto = .full;

    const wasm_install = b.addInstallArtifact(wasm, .{
        .dest_dir = .{ .override = .{ .custom = "../public" } },
    });

    const wasm_step = b.step("wasm", "Build the WASM module");

    wasm_step.dependOn(&wasm_install.step);

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
                .{ .name = "lib2", .module = b.createModule(.{
                    .root_source_file = b.path("lib2/root.zig"),
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

    const lib2_check = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib2/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const check_step = b.step("check", "Check Zig code for errors (used by ZLS)");

    check_step.dependOn(&wasm_check.step);
    check_step.dependOn(&lib2_check.step);

    // =========================================================================
    // Tests
    // =========================================================================

    const test_step = b.step("test", "Build and run all tests");

    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/root.zig"),
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

    const run_lib_tests = b.addRunArtifact(lib_tests);

    test_step.dependOn(&run_lib_tests.step);

    const lib2_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib2/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_lib2_tests = b.addRunArtifact(lib2_tests);

    test_step.dependOn(&run_lib2_tests.step);

    // =========================================================================
    // Native Performance Benchmark
    // =========================================================================

    const perf = b.addExecutable(.{
        .name = "perf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/perf/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "lib",
                    .module = b.createModule(.{
                        .root_source_file = b.path("lib/root.zig"),
                        .target = target,
                        .optimize = optimize,
                    }),
                },
            },
        }),
    });

    const perf_install = b.addInstallArtifact(perf, .{});
    const perf_step = b.step("perf", "Build the performance benchmark");

    perf_step.dependOn(&perf_install.step);

    const run_perf = b.addRunArtifact(perf);
    const run_perf_step = b.step("run-perf", "Run the performance benchmark");

    run_perf_step.dependOn(&run_perf.step);

    // =========================================================================
    // Native Performance Benchmark (lib2)
    // =========================================================================

    const perf_lib2 = b.addExecutable(.{
        .name = "perf-lib2",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/perf/lib2.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "lib2",
                    .module = b.createModule(.{
                        .root_source_file = b.path("lib2/root.zig"),
                        .target = target,
                        .optimize = optimize,
                    }),
                },
            },
        }),
    });

    const perf_lib2_install = b.addInstallArtifact(perf_lib2, .{});
    const perf_lib2_step = b.step("perf-lib2", "Build the lib2 performance benchmark");

    perf_lib2_step.dependOn(&perf_lib2_install.step);

    const run_perf_lib2 = b.addRunArtifact(perf_lib2);

    if (b.args) |args| {
        run_perf_lib2.addArgs(args);
    }

    const run_perf_lib2_step = b.step("run-perf-lib2", "Run the lib2 performance benchmark");

    run_perf_lib2_step.dependOn(&run_perf_lib2.step);

    // =========================================================================
    // Default step builds WASM
    // =========================================================================

    b.default_step.dependOn(wasm_step);
}
