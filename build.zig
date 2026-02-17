const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const check_step = b.step("check", "Check Zig code for errors (used by ZLS)");

    b.default_step.dependOn(check_step);
    b.default_step.dependOn(buildWasmModule(b, check_step));

    buildProfileBinary(b, target, optimize, check_step);
    buildPngBinary(b, target, optimize, check_step);
    buildInkyZeroBinary(b, target, optimize, check_step);
    buildInkyPicoBinary(b, optimize, check_step);
    buildTests(b, target, optimize);
}

fn buildWasmModule(b: *std.Build, check_step: *std.Build.Step) *std.Build.Step {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_features_add = std.Target.wasm.featureSet(&.{ .bulk_memory, .simd128 }),
    });

    const exe = b.addExecutable(.{
        .name = "index",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/wasm/main.zig"),
            .target = target,
            .optimize = .ReleaseSmall,
            .strip = true,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = target,
                    .optimize = .ReleaseSmall,
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
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = target,
                    .optimize = .ReleaseSmall,
                }) },
            },
        }),
    });

    check.entry = .disabled;
    check.rdynamic = true;
    check.import_memory = true;
    check.lto = .full;

    check_step.dependOn(&check.step);

    return step;
}

fn buildProfileBinary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    check_step: *std.Build.Step,
) void {
    const exe = b.addExecutable(.{
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

    const exe_install = b.addInstallArtifact(exe, .{});

    const step = b.step("profile", "Build the Profile binary");

    step.dependOn(&exe_install.step);

    const check = b.addExecutable(.{
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

    check_step.dependOn(&check.step);
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

fn buildInkyZeroBinary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    check_step: *std.Build.Step,
) void {
    const exe = b.addExecutable(.{
        .name = "inky-zero",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/inky-zero/main.zig"),
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

    const step = b.step("inky-zero", "Build the Inky Zero binary");

    step.dependOn(&exe_install.step);

    const check = b.addExecutable(.{
        .name = "inky-zero",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/inky-zero/main.zig"),
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

fn buildInkyPicoBinary(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    check_step: *std.Build.Step,
) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m33 },
        .os_tag = .freestanding,
        .abi = .eabihf,
    });

    // Capture host system time + 90s buffer for the Pico's initial clock
    const initial_utc_time_ms: u64 = @intCast((std.time.timestamp() + 90) * 1000);

    const build_options = b.addOptions();

    build_options.addOption(u64, "initial_utc_time_ms", initial_utc_time_ms);
    build_options.addOption(i64, "utc_offset_ms", @as(i64, detectUtcOffset(b.allocator)) * 1000);

    const exe = b.addExecutable(.{
        .name = "inky-pico",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/inky-pico/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
                .{ .name = "build_options", .module = build_options.createModule() },
            },
        }),
    });

    exe.entry = .disabled;
    exe.setLinkerScript(b.path("bin/inky-pico/link.ld"));

    const exe_install = b.addInstallArtifact(exe, .{});

    // UF2 conversion (native build tool, runs as post-link step)
    const elf2uf2 = b.addExecutable(.{
        .name = "elf2uf2",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/elf2uf2.zig"),
            .target = b.graph.host,
        }),
    });

    const run_elf2uf2 = b.addRunArtifact(elf2uf2);

    run_elf2uf2.addArtifactArg(exe);

    const uf2_output_file = run_elf2uf2.addOutputFileArg("inky-pico.uf2");

    const uf2_install = b.addInstallFileWithDir(
        uf2_output_file,
        .prefix,
        "inky-pico.uf2",
    );

    const step = b.step("inky-pico", "Build the Inky Pico binary");

    step.dependOn(&exe_install.step);
    step.dependOn(&uf2_install.step);

    const check = b.addExecutable(.{
        .name = "inky-pico",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/inky-pico/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
                .{ .name = "build_options", .module = build_options.createModule() },
            },
        }),
    });

    check.entry = .disabled;
    check.setLinkerScript(b.path("bin/inky-pico/link.ld"));

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

fn detectUtcOffset(allocator: std.mem.Allocator) i32 {
    const file = std.fs.openFileAbsolute("/etc/localtime", .{}) catch return 0;

    defer file.close();

    const data = file.readToEndAlloc(allocator, 1 << 16) catch return 0;

    var stream = std.io.fixedBufferStream(data);

    const tz = std.Tz.parse(allocator, stream.reader()) catch return 0;
    const utc_seconds = std.time.timestamp();

    var offset: i32 = 0;

    for (tz.transitions) |transition| {
        if (transition.ts > utc_seconds) break;
        offset = transition.timetype.offset;
    }

    return offset;
}
