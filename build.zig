const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const check_step = b.step("check", "Check Zig code for errors (used by ZLS)");

    b.default_step.dependOn(check_step);
    b.default_step.dependOn(buildWasmModule(b, check_step));

    buildPngBinary(b, target, optimize, check_step);
    buildTests(b, target, optimize);
    checkToolCompiles(b, target, optimize, check_step);
}

// The blue-noise generator is an offline tool, not installed; compile-check it so a std
// API change can't silently break the only way to regenerate lib/blue_noise.bin.
fn checkToolCompiles(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    check_step: *std.Build.Step,
) void {
    const check = b.addExecutable(.{
        .name = "blue_noise_generator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/blue_noise_generator.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    check_step.dependOn(&check.step);
}

fn buildWasmModule(b: *std.Build, check_step: *std.Build.Step) *std.Build.Step {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_features_add = std.Target.wasm.featureSet(&.{ .bulk_memory, .simd128 }),
    });

    const optimize: std.builtin.OptimizeMode = .ReleaseSmall;

    const exe = b.addExecutable(.{
        .name = "index",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/wasm/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = true,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = target,
                    .optimize = optimize,
                    .strip = true,
                }) },
            },
        }),
    });

    exe.entry = .disabled;
    exe.rdynamic = true;
    exe.import_memory = true;
    exe.lto = .full;

    const exe_install = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "../public" } },
    });

    const step = b.step("wasm", "Build the WASM module");

    step.dependOn(&exe_install.step);

    const check = b.addExecutable(.{
        .name = "index",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/wasm/main.zig"),
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

    check_step.dependOn(&check.step);

    return step;
}

fn buildPngBinary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    check_step: *std.Build.Step,
) void {
    const exe = b.addExecutable(.{
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

    const exe_install = b.addInstallArtifact(exe, .{});

    const step = b.step("png", "Build the PNG export binary");

    step.dependOn(&exe_install.step);

    const check = b.addExecutable(.{
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

    check_step.dependOn(&check.step);
}

fn buildTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const lib = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run = b.addRunArtifact(lib);

    const step = b.step("test", "Build and run all tests");

    step.dependOn(&run.step);
}
