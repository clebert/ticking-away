const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // =========================================================================
    // WASM module
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

    const wasm_exe_install = b.addInstallArtifact(wasm_exe, .{
        .dest_dir = .{ .override = .{ .custom = "../public" } },
    });

    const wasm_step = b.step("wasm", "Build the WASM module");

    wasm_step.dependOn(&wasm_exe_install.step);

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

    const profile_exe_install = b.addInstallArtifact(profile_exe, .{});

    const profile_step = b.step("profile", "Build the Profile binary");

    profile_step.dependOn(&profile_exe_install.step);

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

    const png_exe_install = b.addInstallArtifact(png_exe, .{});

    const png_step = b.step("png", "Build the PNG export binary");

    png_step.dependOn(&png_exe_install.step);

    // =========================================================================
    // Inky Zero binary (Raspberry Pi Zero 2 W)
    // =========================================================================

    const inky_zero_exe = b.addExecutable(.{
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

    const inky_zero_exe_install = b.addInstallArtifact(inky_zero_exe, .{});

    const inky_zero_step = b.step("inky-zero", "Build the Inky Zero binary");

    inky_zero_step.dependOn(&inky_zero_exe_install.step);

    // =========================================================================
    // Inky Pico binary (Raspberry Pi Pico 2, bare-metal RP2350)
    // =========================================================================

    const pico_target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m33 },
        .os_tag = .freestanding,
        .abi = .eabihf,
    });

    // Capture host system time + 90s buffer for the Pico's initial clock
    const initial_utc_time_ms: u64 = @intCast((std.time.timestamp() + 90) * 1000);

    const pico_options = b.addOptions();

    pico_options.addOption(u64, "initial_utc_time_ms", initial_utc_time_ms);
    pico_options.addOption(i64, "utc_offset_ms", @as(i64, detectUtcOffset(b.allocator)) * 1000);

    const inky_pico_exe = b.addExecutable(.{
        .name = "inky-pico",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/inky-pico/main.zig"),
            .target = pico_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = pico_target,
                    .optimize = optimize,
                }) },
                .{ .name = "build_options", .module = pico_options.createModule() },
            },
        }),
    });

    inky_pico_exe.entry = .disabled;
    inky_pico_exe.setLinkerScript(b.path("bin/inky-pico/link.ld"));

    const inky_pico_exe_install = b.addInstallArtifact(inky_pico_exe, .{});

    // UF2 conversion (native build tool, runs as post-link step)
    const elf2uf2_exe = b.addExecutable(.{
        .name = "elf2uf2",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/elf2uf2.zig"),
            .target = b.graph.host,
        }),
    });

    const run_inky_pico_elf2uf2_exe = b.addRunArtifact(elf2uf2_exe);

    run_inky_pico_elf2uf2_exe.addArtifactArg(inky_pico_exe);

    const inky_pico_uf2_output_file = run_inky_pico_elf2uf2_exe.addOutputFileArg("inky-pico.uf2");

    const inky_pico_uf2_install = b.addInstallFileWithDir(
        inky_pico_uf2_output_file,
        .prefix,
        "inky-pico.uf2",
    );

    const inky_pico_step = b.step("inky-pico", "Build the Inky Pico binary");

    inky_pico_step.dependOn(&inky_pico_exe_install.step);
    inky_pico_step.dependOn(&inky_pico_uf2_install.step);

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

    const inky_zero_check = b.addExecutable(.{
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

    const inky_pico_check = b.addExecutable(.{
        .name = "inky-pico",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/inky-pico/main.zig"),
            .target = pico_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lib", .module = b.createModule(.{
                    .root_source_file = b.path("lib/root.zig"),
                    .target = pico_target,
                    .optimize = optimize,
                }) },
                .{ .name = "build_options", .module = pico_options.createModule() },
            },
        }),
    });

    inky_pico_check.entry = .disabled;
    inky_pico_check.setLinkerScript(b.path("bin/inky-pico/link.ld"));

    const check_step = b.step("check", "Check Zig code for errors (used by ZLS)");

    check_step.dependOn(&wasm_check.step);
    check_step.dependOn(&profile_check.step);
    check_step.dependOn(&png_check.step);
    check_step.dependOn(&inky_zero_check.step);
    check_step.dependOn(&inky_pico_check.step);

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
