const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {

    const opt_gui: ?bool = b.option(bool, "GUI", "launch with GUI");

    const opts = b.addOptions();

    opts.addOption(bool, "GUI", opt_gui orelse false);
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "pbrain-gomoku-ai",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("build_options", opts.createModule());

    if (opt_gui orelse false) {
        const capy_dep = b.dependency("capy", .{
            .target = target,
            .optimize = optimize,
            .app_name = @as([]const u8, "pbrain-gomoku-ai"),
        });
        const capy = capy_dep.module("capy");
        exe.root_module.addImport("capy", capy);

        const build_capy = @import("capy");

        const run_cmd = try build_capy.runStep(exe, .{ .args = b.args });
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(run_cmd);
    } else {
        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);



    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_unit_tests.root_module.addImport("build_options", opts.createModule());

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);



    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const kcov_unit = b.addSystemCommand(&.{ "kcov", "--include-path=src" });
    kcov_unit.addDirectoryArg(b.path("coverage"));
    kcov_unit.addArtifactArg(exe_unit_tests);

    const coverage_step = b.step("coverage", "Generate test coverage (kcov)");
    coverage_step.dependOn(&kcov_unit.step);

    const clean_step = b.step("clean", "Clean up project directory");
    clean_step.dependOn(&b.addRemoveDirTree(b.path("zig-out")).step);
    clean_step.dependOn(&b.addRemoveDirTree(b.path(".zig-cache")).step);
}
