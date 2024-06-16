const std = @import("std");
const mach = @import("mach");

pub const Platform = enum {
    glfw,
    x11,
    wayland,
    web,

    pub fn fromTarget(target: std.Target) Platform {
        if (target.cpu.arch == .wasm32) return .web;
        return .glfw;
    }
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mach_dep = b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
    });

    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "breakout",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // Add Mach dependency
    exe.root_module.addImport("mach", mach_dep.module("mach"));
    @import("mach").link(mach_dep.builder, exe);

    // Add zigimg dependency
    exe.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const sheet_exe = b.addExecutable(.{
        .name = "sheet",
        .root_source_file = b.path("src/SpriteSheet.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(sheet_exe);

    const sheet_run_cmd = b.addRunArtifact(sheet_exe);
    if (b.args) |args| sheet_run_cmd.addArgs(args);

    const sheet_run_step = b.step("run-sheet", "Run sheet");
    sheet_run_step.dependOn(&sheet_run_cmd.step);

    //Build step to generate docs:
    const install_docs = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate docs");
    docs_step.dependOn(&install_docs.step);
}
