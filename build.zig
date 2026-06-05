const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const check_step = b.step("check", "Check Zig code for errors (used by ZLS)");

    b.default_step.dependOn(check_step);
    b.default_step.dependOn(buildWasmModule(b, check_step));

    buildPngBinary(b, target, optimize, check_step);
    buildPebbleLibrary(b, check_step);
    buildTrmnlBinary(b, check_step);
    buildTests(b, target, optimize);
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

/// Builds the render core plus its C-ABI wrapper as a freestanding Thumb static
/// library that bin/pebble/wscript links into the Pebble app. The Pebble app ABI
/// is soft-float, so the target is `eabi` (not `eabihf`) and the `@Vector` math
/// scalarizes; PIC matches the app loader's relocatable model. compiler_rt is
/// left out so the `__aeabi_*` soft-float helpers resolve from the SDK's libgcc
/// at the final link rather than clashing with it.
///
/// The SDK compiles app objects for the ARMv7-M baseline (`-mcpu=cortex-m3`, the
/// FPU-less floor across all Pebble platforms), so this archive must match it or
/// the ELF architecture attributes conflict at link time.
fn buildPebbleLibrary(b: *std.Build, check_step: *std.Build.Step) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .abi = .eabi,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m3 },
    });

    const optimize: std.builtin.OptimizeMode = .ReleaseSmall;

    const lib = b.addLibrary(.{
        .name = "watchface",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/pebble/render.zig"),
            .target = target,
            .optimize = optimize,
            .strip = true,
            .pic = true,
            .unwind_tables = .none,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = target,
                    .optimize = optimize,
                    .strip = true,
                    .pic = true,
                    .unwind_tables = .none,
                }) },
            },
        }),
    });

    lib.bundle_compiler_rt = false;

    const lib_install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "../bin/pebble" } },
    });

    const step = b.step("pebble-lib", "Build the Pebble watchface static library");

    step.dependOn(&lib_install.step);

    check_step.dependOn(&lib.step);
}

/// Builds bin/trmnl/main.zig as a freestanding RV32IMC firmware ELF for the
/// TRMNL's ESP32-C3 — no libc, no ESP-IDF. bin/trmnl/link.ld lays the image into
/// the chip's SRAM (code via the IRAM alias, data via the DRAM alias) with
/// `_start` as the bare entry point; the program bit-bangs the UC8179 e-ink panel
/// directly. ReleaseSmall keeps the image inside SRAM and strip drops the symbol
/// table. `entry = .disabled` defers the entry address to the linker script's
/// `ENTRY(_start)` instead of letting Zig synthesize a libc-style start.
fn buildTrmnlBinary(b: *std.Build, check_step: *std.Build.Step) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv32,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
        .cpu_features_add = std.Target.riscv.featureSet(&.{ .m, .c }),
    });

    const optimize: std.builtin.OptimizeMode = .ReleaseSmall;

    const exe = b.addExecutable(.{
        .name = "trmnl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/trmnl/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = true,
            .unwind_tables = .none,
        }),
    });

    exe.entry = .disabled;
    exe.setLinkerScript(b.path("bin/trmnl/link.ld"));

    const exe_install = b.addInstallArtifact(exe, .{});

    const step = b.step("trmnl", "Build the TRMNL firmware image");

    step.dependOn(&exe_install.step);

    check_step.dependOn(&exe.step);
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
