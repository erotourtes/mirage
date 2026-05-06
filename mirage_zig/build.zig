const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("mirage_lib", .{
        .root_source_file = b.path("src/lib/root.zig"),
        .target = target,
    });

    const test_step = addTests(b, target, optimize, mod);
    addExeModule(b, target, optimize, mod, test_step);
    addWasmModule(b, optimize);
}

fn addExeModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    mod: *std.Build.Module,
    test_step: *std.Build.Step,
) void {
    const exe = b.addExecutable(.{
        .name = "mirage",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mirage_lib", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
        .use_llvm = true,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    test_step.dependOn(&run_exe_tests.step);
}

fn addWasmModule(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
) void {
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/lib/root.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });

    const wasm_root_module = b.createModule(.{
        .root_source_file = b.path("wasm/wasm.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mirage_lib", .module = wasm_mod },
        },
    });
    wasm_root_module.export_symbol_names = &.{
        "alloc",
        "free",
        "doc_create",
        "doc_destroy",
        "text_len",
        "text_insert",
        "text_insert_attr",
        "text_format",
        "text_delete",
        "text_to_string",
        "text_encode_state_vector",
        "text_encode_update",
        "text_apply_update",
    };
    const wasm_exe = b.addExecutable(.{
        .name = "mirage",
        .root_module = wasm_root_module,
    });
    wasm_exe.entry = .disabled;
    const install_wasm = b.addInstallArtifact(wasm_exe, .{});
    const wasm_step = b.step("wasm", "Build the WebAssembly artifact");
    wasm_step.dependOn(&install_wasm.step);
}

fn addTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    mod: *std.Build.Module,
) *std.Build.Step {
    const mod_tests = b.addTest(.{
        .root_module = mod,
        .use_llvm = true,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    addDiscoveredStandaloneTests(b, test_step, target, optimize, "src/lib", ".zig", &.{}) catch |err| {
        std.debug.print("failed to add discovered library tests: {}\n", .{err});
        @panic("Failed to add discovered library tests");
    };
    addDiscoveredStandaloneTests(b, test_step, target, optimize, "tests", "_test.zig", &.{
        .{ .name = "mirage_lib", .module = mod },
    }) catch |err| {
        std.debug.print("failed to add discovered tests: {}\n", .{err});
        @panic("Failed to add discovered tests");
    };

    return test_step;
}

fn addDiscoveredStandaloneTests(
    b: *std.Build,
    test_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    dir_path: []const u8,
    suffix: []const u8,
    imports: []const std.Build.Module.Import,
) !void {
    const io = b.graph.io;
    var dir = b.build_root.handle.openDir(io, dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, suffix)) continue;

        const test_path = std.fs.path.join(b.allocator, &.{ dir_path, entry.name }) catch @panic("failed to allocate test path");
        const test_artifact = b.addTest(.{
            .use_llvm = true,
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_path),
                .target = target,
                .optimize = optimize,
                .imports = imports,
            }),
        });
        const run_test = b.addRunArtifact(test_artifact);
        test_step.dependOn(&run_test.step);
    }
}
