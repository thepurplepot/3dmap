const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const opt = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "3dmap",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = opt,
    });

    const strip = b.option(
        bool,
        "strip",
        "Strip debug info to reduce binary size, defaults to false",
    ) orelse false;
    exe.root_module.strip = strip;

    exe.addCSourceFiles(.{
        .files = &.{
            "cimgui/cimgui.cpp",
            "cimgui/imgui/imgui.cpp",
            "cimgui/imgui/imgui_draw.cpp",
            "cimgui/imgui/imgui_demo.cpp",
            "cimgui/imgui/imgui_tables.cpp",
            "cimgui/imgui/imgui_widgets.cpp",
            "cimgui/imgui/backends/imgui_impl_glfw.cpp",
            "cimgui/imgui/backends/imgui_impl_opengl3.cpp",
            "glad/src/glad.c",
        },
    });
    exe.addIncludePath(b.path("cimgui"));
    exe.addIncludePath(b.path("cimgui/generator/output"));
    exe.addIncludePath(b.path("cimgui/imgui/backends"));
    exe.addIncludePath(b.path("cimgui/imgui"));
    exe.addIncludePath(b.path("glad/include"));
    exe.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    exe.linkSystemLibrary("glfw3");
    exe.linkSystemLibrary("gdal");
    exe.linkLibC();
    exe.linkLibCpp();

    const zstbi = b.dependency("zstbi", .{});
    exe.root_module.addImport("zstbi", zstbi.module("root"));
    exe.linkLibrary(zstbi.artifact("zstbi"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/Mesh.zig"),
        .target = target,
        .optimize = opt,
    });
    tests.linkSystemLibrary("gdal");

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    //get textures
    const get_textures = b.addExecutable(.{
        .name = "get_textures",
        .root_source_file = b.path("src/get_textures.zig"),
        .target = target,
        .optimize = opt,
    });

    get_textures.root_module.addImport("zstbi", zstbi.module("root"));
    get_textures.linkLibrary(zstbi.artifact("zstbi"));

    b.installArtifact(get_textures);

    const get_tex_run_cmd = b.addRunArtifact(get_textures);

    if (b.args) |args| {
        get_tex_run_cmd.addArgs(args);
    }

    const get_tex_run_step = b.step("get", "Get textures from the google maps API");
    get_tex_run_step.dependOn(&get_tex_run_cmd.step);
}
