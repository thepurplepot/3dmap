const std = @import("std");

const Builder = struct {
    b: *std.Build,
    opt: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
    check_step: *std.Build.Step,
    run_step: *std.Build.Step,
    get_step: *std.Build.Step,
    test_step: *std.Build.Step,
    backend: BackendType,

    const BackendType = enum {
        glfw_opengl3,
        glfw_wgpu,
    };

    fn init(b: *std.Build) Builder {
        const check_step = b.step("check", "check");
        const run_step = b.step("run", "Run the application");
        const get_step = b.step("get", "Get textures from the google maps API");
        const test_step = b.step("test", "Run tests");
        const backend = b.option(BackendType, "backend", "") orelse BackendType.glfw_opengl3;

        return .{
            .b = b,
            .opt = b.standardOptimizeOption(.{}),
            .target = b.standardTargetOptions(.{}),
            .check_step = check_step,
            .run_step = run_step,
            .get_step = get_step,
            .test_step = test_step,
            .backend = backend,
        };
    }

    fn installAndCheck(self: *Builder, elem: *std.Build.Step.Compile) struct { install_artifact: *std.Build.Step.InstallArtifact, run_artifact: *std.Build.Step.Run } {
        const duped = self.b.allocator.create(std.Build.Step.Compile) catch unreachable;
        duped.* = elem.*;
        self.b.installArtifact(elem);
        const install_artifact = self.b.addInstallArtifact(elem, .{});
        const run_artifact = self.b.addRunArtifact(elem);
        if (self.b.args) |args| {
            run_artifact.addArgs(args);
        }
        self.b.getInstallStep().dependOn(&install_artifact.step);
        self.check_step.dependOn(&duped.step);
        return .{ .install_artifact = install_artifact, .run_artifact = run_artifact };
    }

    fn buildTexGen(self: *Builder) void {
        const gen_tex = self.b.addExecutable(.{
            .name = "gen_tex",
            .root_source_file = self.b.path("src/get_textures.zig"),
            .target = self.target,
            .optimize = self.opt,
        });

        const zstbi = self.b.dependency("zstbi", .{
            .target = self.target,
        });
        gen_tex.root_module.addImport("zstbi", zstbi.module("root"));
        gen_tex.linkLibrary(zstbi.artifact("zstbi"));

        const installed = self.installAndCheck(gen_tex);
        self.get_step.dependOn(&installed.run_artifact.step);
    }

    fn buildApp(self: *Builder) void {
        const root_path = blk: {
            switch (self.backend) {
                .glfw_opengl3 => break :blk "src/main_gl.zig",
                .glfw_wgpu => break :blk "src/main_wgpu.zig",
            }
        };
        const exe = self.b.addExecutable(.{
            .name = "3dmap",
            .root_source_file = self.b.path(root_path),
            .target = self.target,
            .optimize = self.opt,
        });

        @import("system_sdk").addLibraryPathsTo(exe);

        const zglfw = self.b.dependency("zglfw", .{
            .target = self.target,
        });
        exe.root_module.addImport("zglfw", zglfw.module("root"));
        exe.linkLibrary(zglfw.artifact("glfw"));

        switch (self.backend) {
            .glfw_opengl3 => {
                const zopengl = self.b.dependency("zopengl", .{});
                exe.root_module.addImport("zopengl", zopengl.module("root"));
            },
            .glfw_wgpu => {
                @import("zgpu").addLibraryPathsTo(exe);
                const zgpu = self.b.dependency("zgpu", .{
                    .target = self.target,
                });
                exe.root_module.addImport("zgpu", zgpu.module("root"));
                exe.linkLibrary(zgpu.artifact("zdawn"));
            },
        }

        const zgui = self.b.dependency("zgui", .{ .target = self.target, .backend = self.backend });
        exe.root_module.addImport("zgui", zgui.module("root"));
        exe.linkLibrary(zgui.artifact("imgui"));

        const zmath = self.b.dependency("zmath", .{
            .target = self.target,
        });
        exe.root_module.addImport("zmath", zmath.module("root"));

        const zstbi = self.b.dependency("zstbi", .{
            .target = self.target,
        });
        exe.root_module.addImport("zstbi", zstbi.module("root"));
        exe.linkLibrary(zstbi.artifact("zstbi"));

        exe.linkSystemLibrary("gdal"); // GeoTIFF
        exe.linkSystemLibrary("expat"); // XML (GPX parser)

        if (self.target.query.os_tag == .windows) {
            exe.want_lto = false;
        }

        const installed = self.installAndCheck(exe);
        self.run_step.dependOn(&installed.run_artifact.step);
    }

    fn buildTests(self: *Builder) void {
        const tests = self.b.addTest(.{
            .root_source_file = self.b.path("src/GpxParser.zig"),
            .target = self.target,
            .optimize = self.opt,
        });
        tests.linkSystemLibrary("expat");

        const run_tests = self.b.addRunArtifact(tests);
        self.test_step.dependOn(&run_tests.step);
    }
};

pub fn build(b: *std.Build) void {
    var builder = Builder.init(b);
    builder.buildTexGen();
    builder.buildApp();
    builder.buildTests();
}
