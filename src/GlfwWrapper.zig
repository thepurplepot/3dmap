const std = @import("std");
const Allocator = std.mem.Allocator;
const gl = @import("opengl_bindings.zig");
const Camera = @import("Camera.zig");

const GlfwWrapper = @This();
const GL_LOG_FILE = "gl.log";
const WINDOW_NAME = "3D Map";

window: *gl.c.GLFWwindow,
mouse_down: bool,
log: std.fs.File,

const MousePos = struct {
    x: f32,
    y: f32,
};

const InputAction = union(enum) {
    mouse_pressed: MousePos,
    mouse_released: void,
    mouse_moved: MousePos,
    move_forward: void,
    move_backward: void,
    move_left: void,
    move_right: void,
};

fn checkGLError() void {
    const error_ = gl.c.glGetError();
    if (error_ != gl.c.GL_NO_ERROR) {
        std.debug.print("OpenGL Error: {any}\n", .{error_});
    }
}

fn glDebugCallback(source: gl.GLenum, typ: gl.GLenum, id: gl.GLuint, severity: gl.GLenum, length: gl.GLsizei, message: [*c]const gl.GLchar, user_param: ?*const anyopaque) callconv(.C) void {
    _ = source;
    _ = typ;
    _ = id;
    _ = severity;
    _ = user_param;
    std.debug.print("{s}", .{message[0..@intCast(length)]});
}

fn errorCallback(err: c_int, desc: [*c]const u8) callconv(.C) void {
    std.debug.print("err: {d} {s}", .{ err, desc });
}

fn GLTypeToString(type_: gl.c.GLenum) []const u8 {
    switch (type_) {
        gl.c.GL_BOOL => return "bool",
        gl.c.GL_INT => return "int",
        gl.c.GL_FLOAT => return "float",
        gl.c.GL_FLOAT_VEC2 => return "vec2",
        gl.c.GL_FLOAT_VEC3 => return "vec3",
        gl.c.GL_FLOAT_VEC4 => return "vec4",
        gl.c.GL_FLOAT_MAT2 => return "mat2",
        gl.c.GL_FLOAT_MAT3 => return "mat3",
        gl.c.GL_FLOAT_MAT4 => return "mat4",
        gl.c.GL_SAMPLER_2D => return "sampler2D",
        gl.c.GL_SAMPLER_3D => return "sampler3D",
        gl.c.GL_SAMPLER_CUBE => return "samplerCube",
        gl.c.GL_SAMPLER_2D_SHADOW => return "sampler2DShadow",
        else => return "other",
    }
}

pub fn compileLinkProgram(log: std.fs.File, vs: [*]const u8, vs_len: usize, fs: [*]const u8, fs_len: usize) !u32 {
    const vertex_shader = gl.c.glCreateShader(gl.c.GL_VERTEX_SHADER);
    const vs_len_i: c_int = @intCast(vs_len);
    gl.c.glShaderSource(vertex_shader, 1, &vs, &vs_len_i);
    gl.c.glCompileShader(vertex_shader);
    var params: c_int = -1;
    gl.c.glGetShaderiv(vertex_shader, gl.c.GL_COMPILE_STATUS, &params);
    if (params != gl.c.GL_TRUE) {
        try glLogError(log, "ERROR: GL shader index {d} did not compile\n", .{vertex_shader});
        try printShaderInfoLog(log, vertex_shader);
        return error.ShaderCompile;
    }

    const fragment_shader = gl.c.glCreateShader(gl.c.GL_FRAGMENT_SHADER);
    const fs_len_i: c_int = @intCast(fs_len);
    gl.c.glShaderSource(fragment_shader, 1, &fs, &fs_len_i);
    gl.c.glCompileShader(fragment_shader);
    params = -1;
    gl.c.glGetShaderiv(fragment_shader, gl.c.GL_COMPILE_STATUS, &params);
    if (params != gl.c.GL_TRUE) {
        try glLogError(log, "ERROR: GL shader index {d} did not compile\n", .{fragment_shader});
        try printShaderInfoLog(log, fragment_shader);
        return error.ShaderCompile;
    }

    const program = gl.c.glCreateProgram();
    gl.c.glAttachShader(program, vertex_shader);
    gl.c.glAttachShader(program, fragment_shader);
    gl.c.glLinkProgram(program);
    params = -1;
    gl.c.glGetProgramiv(program, gl.c.GL_LINK_STATUS, &params);
    if (params != gl.c.GL_TRUE) {
        try glLogError(log, "ERROR: could not link shader programme GL index {d}\n", .{program});
        try printProgramInfoLog(log, program);
        return error.ProgramLink;
    }

    try printAll(log, program);
    return @bitCast(program);
}

fn printShaderInfoLog(file: std.fs.File, shader: u32) !void {
    const max_length: c_int = 2048;
    var actual_length: c_int = 0;
    var log: [2048]u8 = undefined;
    gl.c.glGetShaderInfoLog(shader, max_length, &actual_length, &log);
    try file.writer().print("Shader info log for GL index {d}:\n{s}\n", .{ shader, log[0..@intCast(actual_length)] });
}

fn printProgramInfoLog(file: std.fs.File, program: u32) !void {
    const max_length: c_int = 2048;
    var actual_length: c_int = 0;
    var log: [2048]u8 = undefined;
    gl.c.glGetProgramInfoLog(program, max_length, &actual_length, &log);
    try file.writer().print("Program info log for GL index {d}:\n{s}\n", .{ program, log[0..@intCast(actual_length)] });
}

fn logGlParams(file: std.fs.File) !void {
    const params = [_]gl.c.GLenum{
        gl.c.GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS,
        gl.c.GL_MAX_CUBE_MAP_TEXTURE_SIZE,
        gl.c.GL_MAX_DRAW_BUFFERS,
        gl.c.GL_MAX_FRAGMENT_UNIFORM_COMPONENTS,
        gl.c.GL_MAX_TEXTURE_IMAGE_UNITS,
        gl.c.GL_MAX_TEXTURE_SIZE,
        gl.c.GL_MAX_VARYING_FLOATS,
        gl.c.GL_MAX_VERTEX_ATTRIBS,
        gl.c.GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS,
        gl.c.GL_MAX_VERTEX_UNIFORM_COMPONENTS,
        gl.c.GL_MAX_VIEWPORT_DIMS,
        gl.c.GL_STEREO,
    };
    const names = [_][]const u8{
        "GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS",
        "GL_MAX_CUBE_MAP_TEXTURE_SIZE",
        "GL_MAX_DRAW_BUFFERS",
        "GL_MAX_FRAGMENT_UNIFORM_COMPONENTS",
        "GL_MAX_TEXTURE_IMAGE_UNITS",
        "GL_MAX_TEXTURE_SIZE",
        "GL_MAX_VARYING_FLOATS",
        "GL_MAX_VERTEX_ATTRIBS",
        "GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS",
        "GL_MAX_VERTEX_UNIFORM_COMPONENTS",
        "GL_MAX_VIEWPORT_DIMS",
        "GL_STEREO",
    };
    try glLog(file, "GL Context Params:\n", .{});
    // integers - only works if the order is 0-10 integer return types
    for (0..10) |i| {
        var v: i32 = 0;
        gl.c.glGetIntegerv(params[i], &v);
        try glLog(file, "{s} {d}\n", .{ names[i], v });
    }
    // others
    var v = [_]c_int{ 0, 0 };
    gl.c.glGetIntegerv(params[10], &v);
    try glLog(file, "{s} {d} {d}\n", .{ names[10], v[0], v[1] });
    var s: u8 = 0;
    gl.c.glGetBooleanv(params[11], &s);
    try glLog(file, "{s} {d}\n", .{ names[11], s });
    try glLog(file, "-----------------------------\n", .{});
}

fn printAll(file: std.fs.File, program: u32) !void {
    try glLog(file, "-----------------------------\nshader program {d} info:\n", .{program});
    var params: i32 = -1;
    gl.c.glGetProgramiv(program, gl.c.GL_LINK_STATUS, &params);
    try glLog(file, "GL_LINK_STATUS = {d}\n", .{params});

    gl.c.glGetProgramiv(program, gl.c.GL_ATTACHED_SHADERS, &params);
    try glLog(file, "GL_ATTACHED_SHADERS = {d}\n", .{params});

    gl.c.glGetProgramiv(program, gl.c.GL_ACTIVE_ATTRIBUTES, &params);
    try glLog(file, "GL_ACTIVE_ATTRIBUTES = {d}\n", .{params});
    for (0..@intCast(params)) |i| {
        var name: [64]u8 = undefined;
        const max_length = 64;
        var actual_length: u32 = 0;
        var size: u32 = 0;
        var type_: gl.c.GLenum = 0;
        gl.c.glGetActiveAttrib(program, @intCast(i), max_length, @ptrCast(&actual_length), @ptrCast(&size), &type_, &name);
        if (size > 1) {
            for (0..size) |j| {
                var buf: [64]u8 = undefined;
                const long_name = try std.fmt.bufPrintZ(&buf, "{s}[{d}]", .{ name[0..actual_length], j });
                const location = gl.c.glGetAttribLocation(program, long_name.ptr);
                try glLog(file, "  {d}) type:{s} name:{s} location:{d}\n", .{ i, GLTypeToString(type_), long_name, location });
            }
        } else {
            const location = gl.c.glGetAttribLocation(program, &name);
            try glLog(file, "  {d}) type:{s} name:{s} location:{d}\n", .{ i, GLTypeToString(type_), name[0..actual_length], location });
        }
    }

    gl.c.glGetProgramiv(program, gl.c.GL_ACTIVE_UNIFORMS, &params);
    try glLog(file, "GL_ACTIVE_UNIFORMS = {d}\n", .{params});
    for (0..@intCast(params)) |i| {
        var name: [64]u8 = undefined;
        const max_length = 64;
        var actual_length: u32 = 0;
        var size: u32 = 0;
        var type_: gl.c.GLenum = 0;
        gl.c.glGetActiveUniform(program, @intCast(i), max_length, @ptrCast(&actual_length), @ptrCast(&size), &type_, &name);
        if (size > 1) {
            for (0..size) |j| {
                var buf: [64]u8 = undefined;
                const long_name = try std.fmt.bufPrintZ(&buf, "{s}[{d}]", .{ name[0..actual_length], j });
                const location = gl.c.glGetUniformLocation(program, long_name.ptr);
                try glLog(file, "  {d}) type:{s} name:{s} location:{d}\n", .{ i, GLTypeToString(type_), long_name, location });
            }
        } else {
            const location = gl.c.glGetUniformLocation(program, &name);
            try glLog(file, "  {d}) type:{s} name:{s} location:{d}\n", .{ i, GLTypeToString(type_), name[0..actual_length], location });
        }
    }

    try printProgramInfoLog(file, program);
}

pub fn updateFpsCounter(self: GlfwWrapper) void {
    const state = struct {
        var previous_seconds: f64 = 0.0;
        var frame_count: i32 = 0;
    };
    const current_seconds: f64 = gl.c.glfwGetTime();
    const elapsed_seconds: f64 = current_seconds - state.previous_seconds;
    if (elapsed_seconds > 0.25) {
        state.previous_seconds = current_seconds;
        const fps: f64 = @as(f64, @floatFromInt(state.frame_count)) / elapsed_seconds;
        var buf: [128]u8 = undefined;
        const title = std.fmt.bufPrintZ(&buf, WINDOW_NAME ++ " @ fps: {d:.2}", .{fps}) catch unreachable;
        gl.c.glfwSetWindowTitle(self.window, title.ptr);
        state.frame_count = 0;
    }
    state.frame_count += 1;
}

pub fn init() !GlfwWrapper {
    const file = try restartGlLog();
    try glLog(file, "Starting GLFW\n{s}\n", .{gl.c.glfwGetVersionString()});
    _ = gl.c.glfwSetErrorCallback(errorCallback);

    if (gl.c.glfwInit() != gl.c.GLFW_TRUE) {
        return error.GlfwInit;
    }
    errdefer gl.c.glfwTerminate();

    gl.c.glfwWindowHint(gl.c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    gl.c.glfwWindowHint(gl.c.GLFW_CONTEXT_VERSION_MINOR, 3);
    gl.c.glfwWindowHint(gl.c.GLFW_OPENGL_FORWARD_COMPAT, gl.c.GL_TRUE);
    gl.c.glfwWindowHint(gl.c.GLFW_OPENGL_PROFILE, gl.c.GLFW_OPENGL_CORE_PROFILE);
    gl.c.glfwWindowHint(gl.c.GLFW_SAMPLES, 4);

    const window = gl.c.glfwCreateWindow(800, 600, WINDOW_NAME, null, null) orelse return error.NoWindow;
    errdefer gl.c.glfwDestroyWindow(window);

    gl.c.glfwMakeContextCurrent(window);
    gl.c.glfwSwapInterval(1);

    _ = gl.c.gladLoadGL();

    try logGlParams(file);

    return .{ .window = window, .mouse_down = false, .log = file };
}

pub fn deinit(self: *GlfwWrapper) void {
    gl.c.glfwDestroyWindow(self.window);
    gl.c.glfwTerminate();
    self.log.close();
}

fn getInput(self: *GlfwWrapper, alloc: Allocator) ![]InputAction {
    var ret = std.ArrayList(InputAction).init(alloc);
    defer ret.deinit();

    const glfw_mouse_down = gl.c.glfwGetMouseButton(self.window, gl.c.GLFW_MOUSE_BUTTON_1) != 0;
    if (glfw_mouse_down != self.mouse_down) {
        if (glfw_mouse_down) {
            try ret.append(InputAction{ .mouse_pressed = self.getCursorPos() });
        } else {
            try ret.append(InputAction{ .mouse_released = void{} });
        }
    }
    self.mouse_down = glfw_mouse_down;

    if(gl.c.glfwGetKey(self.window, gl.c.GLFW_KEY_W) == gl.c.GLFW_PRESS) {
        try ret.append(InputAction{ .move_forward = void{} });
    } else if(gl.c.glfwGetKey(self.window, gl.c.GLFW_KEY_S) == gl.c.GLFW_PRESS) {
        try ret.append(InputAction{ .move_backward = void{} });
    } else if (gl.c.glfwGetKey(self.window, gl.c.GLFW_KEY_A) == gl.c.GLFW_PRESS) {
        try ret.append(InputAction{ .move_left = void{} });
    } else if (gl.c.glfwGetKey(self.window, gl.c.GLFW_KEY_D) == gl.c.GLFW_PRESS) {
        try ret.append(InputAction{ .move_right = void{} });
    }

    return try ret.toOwnedSlice();
}

fn getCursorPos(self: *GlfwWrapper) MousePos {
    var width: c_int = 0;
    var height: c_int = 0;
    gl.c.glfwGetWindowSize(self.window, &width, &height);
    var x: f64 = 0.5;
    var y: f64 = 0.5;
    gl.c.glfwGetCursorPos(self.window, &x, &y);
    x /= @floatFromInt(width);
    y /= @floatFromInt(height);

    return .{ .x = @floatCast(x), .y = @floatCast(y) };
}

pub fn enableGLDebug() void {
    gl.c.glDebugMessageCallback(glDebugCallback, null);
    gl.c.glEnable(gl.c.GL_DEBUG_OUTPUT_SYNCHRONOUS);
}

pub fn setGLParams() void {
    gl.c.glEnable(gl.c.GL_DEPTH_TEST);
    gl.c.glEnable(gl.c.GL_MULTISAMPLE);
}

fn restartGlLog() !std.fs.File {
    const file = try std.fs.cwd().createFile(GL_LOG_FILE, .{});

    const time = @cImport({
        @cInclude("time.h");
    });

    const now = time.time(null);
    const date = time.ctime(&now);

    try file.writer().print("GL_LOG_FILE log. Local time: {s}\n", .{date});

    return file;
}

fn glLog(file: std.fs.File, comptime message: []const u8, args: anytype) !void {
    try file.writer().print(message, args);
}

fn glLogError(file: std.fs.File, comptime message: []const u8, args: anytype) !void {
    try file.writer().print(message, args);
    std.log.err(message, args);
}

pub fn handleGlfwActions(alloc: Allocator, glfw: *GlfwWrapper, cam: *Camera) !void {
    const glfw_actions = try glfw.getInput(alloc);
    defer alloc.free(glfw_actions);

    for (glfw_actions) |action| {
        switch (action) {
            .mouse_pressed => |pos| {
                std.debug.print("Mouse pressed at {d:.2}, {d:.2}\n", .{ pos.x, pos.y });
                cam.setTarget(.{.x = pos.x, .y = pos.y, .z = 0.0});
            },
            .mouse_released => {
                //TODO: Implement
            },
            .mouse_moved => |pos| {
                // NOTE: This is called every frame anyways so do nothing
                _ = pos;
            },
            .move_forward => {
                cam.move(.Forward);
            },
            .move_backward => {
                cam.move(.Backward);
            },
            .move_left => {
                cam.move(.Left);
            },
            .move_right => {
                cam.move(.Right);
            },
        }
    }
}
