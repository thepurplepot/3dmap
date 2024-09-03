const std = @import("std");

// Note can switch back to opengl?
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const opt = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "test",
        .root_source_file = b.path("src/main_gl.zig"),
        .target = target,
        .optimize = opt,
    });

    @import("system_sdk").addLibraryPathsTo(exe);

    const zglfw = b.dependency("zglfw", .{
        .target = target,
    });
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.linkLibrary(zglfw.artifact("glfw"));

    const zopengl = b.dependency("zopengl", .{});
    exe.root_module.addImport("zopengl", zopengl.module("root"));

    @import("zgpu").addLibraryPathsTo(exe);
    const zgpu = b.dependency("zgpu", .{
        .target = target,
    });
    exe.root_module.addImport("zgpu", zgpu.module("root"));
    exe.linkLibrary(zgpu.artifact("zdawn"));

    const zgui = b.dependency("zgui", .{
        .target = target,
        .backend = .glfw_opengl3, //.glfw_wgpu,
    });
    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.linkLibrary(zgui.artifact("imgui"));

    const zmath = b.dependency("zmath", .{
        .target = target,
    });
    exe.root_module.addImport("zmath", zmath.module("root"));

    const zstbi = b.dependency("zstbi", .{});
    exe.root_module.addImport("zstbi", zstbi.module("root"));
    exe.linkLibrary(zstbi.artifact("zstbi"));

    exe.linkSystemLibrary("gdal");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    buildTexGen(b, target, opt);
}

fn buildTexGen(b: *std.Build, target: std.Build.ResolvedTarget, opt: std.builtin.OptimizeMode) void {
    const gen_tex = b.addExecutable(.{
        .name = "gen_tex",
        .root_source_file = b.path("src/get_textures.zig"),
        .target = target,
        .optimize = opt,
    });

    const zstbi = b.dependency("zstbi", .{});
    gen_tex.root_module.addImport("zstbi", zstbi.module("root"));
    gen_tex.linkLibrary(zstbi.artifact("zstbi"));

    b.installArtifact(gen_tex);

    const run_cmd = b.addRunArtifact(gen_tex);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("get", "Get textures from the google maps API");
    run_step.dependOn(&run_cmd.step);
}


// const std = @import("std");

// const Builder = struct {
//     b: *std.Build,
//     opt: std.builtin.OptimizeMode,
//     target: std.Build.ResolvedTarget,
//     wasm_target: std.Build.ResolvedTarget,
//     check_step: *std.Build.Step,
//     wasm_step: *std.Build.Step,
//     pp_step: *std.Build.Step,
//     lto: ?bool,

//     fn init(b: *std.Build) Builder {
//         const check_step = b.step("check", "check");
//         const wasm_step = b.step("wasm", "wasm");
//         const lto = b.option(bool, "lto", "");
//         const pp_step = b.step("pp_benchmark", "");

//         return .{
//             .b = b,
//             .opt = b.standardOptimizeOption(.{}),
//             .target = b.standardTargetOptions(.{}),
//             .wasm_target = b.resolveTargetQuery(std.zig.CrossTarget.parse(
//                 .{ .arch_os_abi = "wasm32-freestanding" },
//             ) catch unreachable),
//             .check_step = check_step,
//             .wasm_step = wasm_step,
//             .pp_step = pp_step,
//             .lto = lto,
//         };
//     }

//     fn installAndCheck(self: *Builder, elem: *std.Build.Step.Compile) *std.Build.Step.InstallArtifact {
//         const duped = self.b.allocator.create(std.Build.Step.Compile) catch unreachable;
//         duped.* = elem.*;
//         self.b.installArtifact(elem);
//         const install_artifact = self.b.addInstallArtifact(elem, .{});
//         self.b.getInstallStep().dependOn(&install_artifact.step);
//         self.check_step.dependOn(&duped.step);
//         return install_artifact;
//     }

//     fn generateMapData(self: *Builder) void {
//         const exe = self.b.addExecutable(.{
//             .name = "make_site",
//             .root_source_file = self.b.path("src/make_site.zig"),
//             .target = self.target,
//             .optimize = self.opt,
//         });
//         exe.linkSystemLibrary("sqlite3");
//         exe.linkSystemLibrary("expat");
//         exe.linkLibC();
//         _ = self.installAndCheck(exe);
//     }

//     fn buildApp(self: *Builder) void {
//         const wasm = self.b.addExecutable(.{
//             .name = "index",
//             .root_source_file = self.b.path("src/index.zig"),
//             .target = self.wasm_target,
//             .optimize = self.opt,
//         });
//         wasm.entry = .disabled;
//         wasm.rdynamic = true;
//         const installed = self.installAndCheck(wasm);
//         self.wasm_step.dependOn(&installed.step);
//     }

//     fn buildLinterApp(self: *Builder) void {
//         const exe = self.b.addExecutable(.{
//             .name = "sphmap_nogui",
//             .root_source_file = self.b.path("src/native_nogui.zig"),
//             .target = self.target,
//             .optimize = self.opt,
//         });
//         _ = self.installAndCheck(exe);
//     }

//     fn buildLocalApp(self: *Builder) void {
//         const exe = self.b.addExecutable(.{
//             .name = "sphmap",
//             .root_source_file = self.b.path("src/native_glfw.zig"),
//             .target = self.target,
//             .optimize = self.opt,
//         });
//         exe.want_lto = false;
//         exe.addCSourceFiles(.{
//             .files = &.{
//                 "cimgui/cimgui.cpp",
//                 "cimgui/imgui/imgui.cpp",
//                 "cimgui/imgui/imgui_draw.cpp",
//                 "cimgui/imgui/imgui_demo.cpp",
//                 "cimgui/imgui/imgui_tables.cpp",
//                 "cimgui/imgui/imgui_widgets.cpp",
//                 "cimgui/imgui/backends/imgui_impl_glfw.cpp",
//                 "cimgui/imgui/backends/imgui_impl_opengl3.cpp",
//                 "glad/src/glad.c",
//                 "src/stb_image.c",
//             },
//         });
//         exe.addIncludePath(self.b.path("cimgui"));
//         exe.addIncludePath(self.b.path("cimgui/generator/output"));
//         exe.addIncludePath(self.b.path("cimgui/imgui/backends"));
//         exe.addIncludePath(self.b.path("cimgui/imgui"));
//         exe.addIncludePath(self.b.path("stb_image"));
//         exe.addIncludePath(self.b.path("glad/include"));
//         exe.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
//         exe.linkSystemLibrary("glfw");
//         exe.linkLibC();
//         exe.linkLibCpp();

//         if (self.lto) |val| {
//             exe.want_lto = val;
//         }

//         _ = self.installAndCheck(exe);
//     }

//     fn buildPathPlannerBenchmark(self: *Builder) void {
//         const exe = self.b.addExecutable(.{
//             .name = "pp_benchmark",
//             .root_source_file = self.b.path("src/pp_benchmark.zig"),
//             .target = self.target,
//             .optimize = self.opt,
//         });
//         const artifact = self.installAndCheck(exe);
//         self.pp_step.dependOn(&artifact.step);
//     }
// };

// pub fn build(b: *std.Build) void {
//     var builder = Builder.init(b);
//     builder.generateMapData();
//     builder.buildApp();
//     builder.buildPathPlannerBenchmark();
//     builder.buildLinterApp();
//     builder.buildLocalApp();
// }