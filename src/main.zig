const std = @import("std");
const Allocator = std.mem.Allocator;
const GlfwWrapper = @import("GlfwWrapper.zig");
const GeoTiffParser = @import("GeoTiffParser.zig");
const Ui = @import("Ui.zig");
const Mesh = @import("Mesh.zig");
const gl = @import("opengl_bindings.zig");
const Camera = @import("Camera.zig");

const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <filename>\n", .{args[0]});
        return error.InvalidArgs;
    }

    var parser = try GeoTiffParser.init(alloc, args[1]);
    defer parser.deinit();

    const map = try parser.fullSample();
    defer alloc.free(map.elevations);
    defer alloc.free(map.positions);

    var glfw = try GlfwWrapper.init();
    defer glfw.deinit();

    // GlfwWrapper.enableGLDebug();

    var ui = try Ui.init(glfw.window);
    defer ui.deinit();
    const bounds: Mesh.PositionsMetaData = .{.min_lon = -3.244, .min_lat = 54.418, .max_lon = -3.007, .max_lat = 54.5175}; 
    var mesh = try Mesh.meshFromElevations(alloc, bounds, map.elevations, map.positions);
    // mesh.printMesh();
    //const mesh = try Mesh.testMesh();
    defer mesh.deinit(alloc);
    const vs_source = @embedFile("shaders/vertex.glsl");
    const fs_source = @embedFile("shaders/fragment.glsl");
    const program = try GlfwWrapper.compileLinkProgram(glfw.log, vs_source, vs_source.len, fs_source, fs_source.len);

    var cam = Camera{};
    cam.setupView(program);

    var width: c_int = 0;
    var height: c_int = 0;
    while (gl.c.glfwWindowShouldClose(glfw.window) == 0) {
        gl.c.glfwPollEvents();
        gl.c.glClearColor(0.2, 0.3, 0.3, 1.0);
        glfw.updateFpsCounter();
        gl.glClear(gl.c.GL_COLOR_BUFFER_BIT | gl.c.GL_DEPTH_BUFFER_BIT);

        gl.c.glfwGetWindowSize(glfw.window, &width, &height);
        //gl.c.glViewport(0, 0, width, height); //Giving half window size?
        const aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

        cam.update(program, aspect);
        Mesh.setupLighting(program);
        mesh.draw(program);

        const ui_actions = ui.render(width, height);

        try Ui.handleUiActions(ui_actions, &mesh);

        if (!ui_actions.consumed_mouse_input) {
            try GlfwWrapper.handleGlfwActions(alloc, &glfw, &cam);
        }

        gl.c.glfwSwapBuffers(glfw.window);
    }
}
