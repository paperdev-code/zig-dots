pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dots = b.addModule("dots", .{
        .root_source_file = b.path("src/dots.zig"),
        .target = target,
        .optimize = optimize,
    });
    dots.addImport("dots", dots);

    const dots_lib = b.addLibrary(.{
        .name = "dots",
        .root_module = dots,
    });

    const dots_lib_install = b.addInstallArtifact(dots_lib, .{});
    b.getInstallStep().dependOn(&dots_lib_install.step);

    const test_filter = b.option(
        []const u8,
        "test-filter",
        "Filter which unit tests to run",
    ) orelse "";

    const dots_unit_tests = b.addTest(.{
        .root_module = dots,
        .filters = &.{test_filter},
    });

    const dots_unit_tests_run = b.addRunArtifact(dots_unit_tests);

    const unit_tests = b.step("test", "Run unit tests");
    unit_tests.dependOn(&dots_unit_tests_run.step);

    const demo = b.addExecutable(.{
        .name = "demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("demo/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "dots", .module = dots },
            },
        }),
    });

    const demo_install = b.addInstallArtifact(demo, .{});

    const demo_run = b.addRunArtifact(demo);
    demo_run.step.dependOn(&demo_install.step);

    const run = b.step("run", "Run demo");
    run.dependOn(&demo_run.step);
}

const std = @import("std");
const Build = std.Build;
