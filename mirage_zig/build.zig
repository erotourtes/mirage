const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("mirage_lib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

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

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    addDiscoveredTests(b, test_step, mod, target, optimize);
}

fn addDiscoveredTests(
    b: *std.Build,
    test_step: *std.Build.Step,
    mod: *std.Build.Module,
    target: anytype,
    optimize: anytype,
) void {
    const io = b.graph.io;
    var dir = b.build_root.handle.openDir(io, "tests", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => @panic("failed to open tests directory"),
    };
    defer dir.close(io);

    var iter = dir.iterate();
    while (iter.next(io) catch @panic("failed to iterate tests directory")) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, "_test.zig")) continue;

        const test_path = std.fs.path.join(b.allocator, &.{ "tests", entry.name }) catch @panic("failed to allocate test path");
        const test_artifact = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "mirage_lib", .module = mod },
                },
            }),
        });
        const run_test = b.addRunArtifact(test_artifact);
        test_step.dependOn(&run_test.step);
    }
}
