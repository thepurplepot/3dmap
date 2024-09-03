const std = @import("std");
const Allocator = std.mem.Allocator;
const zgui = @import("zgui");
const zglfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const AppState = @import("AppState.zig");
const MeshGenerator = @import("mesh_generator.zig");
const Bounds = MeshGenerator.Bounds;
const zm = @import("zmath");
const TextureLoader = @import("TextureLoader.zig");

const vs_src = @embedFile("shaders/vertex.glsl");
const fs_src = @embedFile("shaders/fragment.glsl");

window: *zglfw.Window,
vbo: gl.Uint,
ebo: gl.Uint,
vao: gl.Uint,
tex: gl.Uint,
program: gl.Uint,
indicies_length: usize,


const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
};


const Self = @This();

pub fn create(alloc: Allocator, bounds: Bounds, geotiff: []const u8) !Self {
    try zglfw.init();
    errdefer zglfw.terminate();

    const gl_major = 4;
    const gl_minor = 0;
    zglfw.windowHintTyped(.context_version_major, gl_major);
    zglfw.windowHintTyped(.context_version_minor, gl_minor);
    zglfw.windowHintTyped(.opengl_profile, .opengl_core_profile);
    zglfw.windowHintTyped(.opengl_forward_compat, true);
    zglfw.windowHintTyped(.client_api, .opengl_api);
    zglfw.windowHintTyped(.doublebuffer, true);

    const window = try zglfw.Window.create(1600, 800, "TEST", null);
    errdefer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    zglfw.makeContextCurrent(window);
    zglfw.swapInterval(1);

    try zopengl.loadCoreProfile(zglfw.getProcAddress, gl_major, gl_minor);

    zgui.init(alloc);
    errdefer zgui.deinit();

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    _ = zgui.io.addFontFromFile("res/Roboto-Medium.ttf", std.math.floor(16.0 * scale_factor));

    zgui.getStyle().scaleAllSizes(scale_factor);

    zgui.backend.init(window);
    errdefer zgui.backend.deinit();

    var texture_loader = try TextureLoader.create(alloc, "output/", "output/meta_data.json");
    defer texture_loader.deinit();

    var ret = Self{
        .window = window,
        .vbo = 0,
        .ebo = 0,
        .vao = 0,
        .tex = 0,
        .program = 0,
        .indicies_length = 0,
    };

    try ret.bindMesh(alloc, bounds, geotiff, &texture_loader);
    ret.program = try compileLinkProgram(vs_src.ptr, vs_src.len, fs_src.ptr, fs_src.len);

    return ret;
}

pub fn destroy(self: *Self, alloc: Allocator) void {
    _ = alloc;
    zgui.backend.deinit();
    zgui.deinit();
    self.window.destroy();
    zglfw.terminate();
}

fn bindMesh(self: *Self, alloc: Allocator, bounds: Bounds, geotiff: []const u8, texture_loader: *TextureLoader) !void {
    var areana_state = std.heap.ArenaAllocator.init(alloc);
    defer areana_state.deinit();
    const arena = areana_state.allocator();

    // Generate mesh from GeoTiff data
    var mesh_indices = std.ArrayList(MeshGenerator.IndexType).init(arena);
    var mesh_positions = std.ArrayList([3]f32).init(arena);
    var mesh_normals = std.ArrayList([3]f32).init(arena);
    try MeshGenerator.generateMesh(alloc, bounds, geotiff, &mesh_indices, &mesh_positions, &mesh_normals);

    const vertices_count = @as(u32, @intCast(mesh_positions.items.len));
    const indices_count = @as(u32, @intCast(mesh_indices.items.len));
    self.indicies_length = @intCast(indices_count);

    // Create UVs
    var mesh_uvs = std.ArrayList([2]f32).init(arena);
    try mesh_uvs.resize(mesh_positions.items.len);
    texture_loader.calculateTexCooordsGl(bounds, mesh_positions, &mesh_uvs);

    var mesh_verticies = try std.ArrayList(Vertex).initCapacity(arena, vertices_count);
    for(0..vertices_count) |i| {
        try mesh_verticies.append(.{
            .position = mesh_positions.items[i],
            .normal = mesh_normals.items[i],
            .uv = mesh_uvs.items[i],
        });
    }

    // create buffers/arrays
    gl.genVertexArrays(1, &self.vao);
    gl.genBuffers(1, &self.vbo);
    gl.genBuffers(1, &self.ebo);

    gl.bindVertexArray(self.vao);
    // load data into vertex buffers
    gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
    gl.bufferData(gl.ARRAY_BUFFER, vertices_count * @sizeOf(Vertex), mesh_verticies.items.ptr, gl.STATIC_DRAW);

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.ebo);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices_count * @sizeOf(u32), mesh_indices.items.ptr, gl.STATIC_DRAW);

    // set the vertex attribute pointers
    // vertex Positions
    gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(@as(usize, @intCast(0))));
    gl.enableVertexAttribArray(0);
    // vertex normals
    gl.vertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(@as(usize, @intCast(3 * @sizeOf(f32)))));
    gl.enableVertexAttribArray(1);
    // vertex texture coords
    gl.enableVertexAttribArray(2);
    gl.vertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(@as(usize, @intCast(6 * @sizeOf(f32)))));

    self.tex = try texture_loader.loadTexturesGl();

    gl.bindVertexArray(0);
}


pub fn draw(self: Self, state: *AppState) void {
    gl.useProgram(self.program);
    gl.enable(gl.DEPTH_TEST); 
    gl.clearColor(0.2, 0.4, 0.8, 1.0);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

    const fb_size = self.window.getFramebufferSize();
    state.size.width = @intCast(fb_size[0]);
    state.size.height = @intCast(fb_size[1]);

    const cam_world_to_view = zm.lookToLh(
        zm.loadArr3(state.camera.position),
        zm.loadArr3(state.camera.forward),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );
    const cam_view_to_clip = zm.perspectiveFovLh(
        0.25 * std.math.pi,
        @as(f32, @floatFromInt(state.size.width)) / @as(f32, @floatFromInt(state.size.height)),
        0.01,
        200.0,
    );
    const cam_world_to_clip = zm.mul(cam_world_to_view, cam_view_to_clip);

    const mesh_obj_to_world = zm.mul(zm.scaling(128.0, 128 * state.options.elevation_scale, 128.0), zm.rotationY(-90.0 / std.math.deg_per_rad));

    // Frame uniforms
    const world_to_clip_loc = gl.getUniformLocation(self.program, "world_to_clip");
    gl.uniformMatrix4fv(world_to_clip_loc, 1, gl.TRUE, @ptrCast(&cam_world_to_clip));
    const camera_position_loc = gl.getUniformLocation(self.program, "camera_position");
    gl.uniform3fv(camera_position_loc, 1, &state.camera.position);

    // Draw Uniforms
    const object_to_world_loc = gl.getUniformLocation(self.program, "object_to_world");
    gl.uniformMatrix4fv(object_to_world_loc, 1, gl.FALSE, @ptrCast(&mesh_obj_to_world));
    const basecolor_roughness_loc = gl.getUniformLocation(self.program, "basecolor_roughness");
    gl.uniform4f(basecolor_roughness_loc, 0.2, 0.2, 0.2, 1.0);
    const texture_loc = gl.getUniformLocation(self.program, "tex");
    gl.uniform1ui(texture_loc, @intFromBool(state.options.texture));
    const flat_shading_loc = gl.getUniformLocation(self.program, "flat_shading");
    gl.uniform1ui(flat_shading_loc, @intFromBool(state.options.flat_shading));
    const follow_camera_light_loc = gl.getUniformLocation(self.program, "follow_camera_light");
    gl.uniform1ui(follow_camera_light_loc, @intFromBool(state.options.follow_camera_light));
    const ambient_light_loc = gl.getUniformLocation(self.program, "ambient_light");
    gl.uniform1f(ambient_light_loc, state.options.ambient_light);
    const specular_strength_loc = gl.getUniformLocation(self.program, "specular_strength");
    gl.uniform1f(specular_strength_loc, state.options.specular_strength);

    // draw mesh
    gl.bindVertexArray(self.vao);
    gl.drawElements(gl.TRIANGLES, @intCast(self.indicies_length), gl.UNSIGNED_INT, @ptrFromInt(@as(usize, @intCast(0))));
    gl.bindVertexArray(0);

    zgui.backend.draw();

    self.window.swapBuffers(); 
}


fn compileLinkProgram(vs: [*]const u8, vs_len: usize, fs: [*]const u8, fs_len: usize) !gl.Uint {
    const vertex_shader = gl.createShader(gl.VERTEX_SHADER);
    const vs_len_i: c_int = @intCast(vs_len);
    gl.shaderSource(vertex_shader, 1, &vs, &vs_len_i);
    gl.compileShader(vertex_shader);
    
    var params: c_int = -1;
    gl.getShaderiv(vertex_shader, gl.COMPILE_STATUS, &params);
    if (params != gl.TRUE) {
        printShaderInfoLog(vertex_shader);
        return error.ShaderCompile;
    }

    const fragment_shader = gl.createShader(gl.FRAGMENT_SHADER);
    const fs_len_i: c_int = @intCast(fs_len);
    gl.shaderSource(fragment_shader, 1, &fs, &fs_len_i);
    gl.compileShader(fragment_shader);
    
    params = -1;
    gl.getShaderiv(fragment_shader, gl.COMPILE_STATUS, &params);
    if (params != gl.TRUE) {
        printShaderInfoLog(fragment_shader);
        return error.ShaderCompile;
    }

    const program = gl.createProgram();
    gl.attachShader(program, vertex_shader);
    gl.attachShader(program, fragment_shader);
    gl.linkProgram(program);

    params = -1;
    gl.getProgramiv(program, gl.LINK_STATUS, &params);
    if (params != gl.TRUE) {
        printProgramInfoLog(program);
        return error.ProgramLink;
    }

    return @bitCast(program);
}

fn printShaderInfoLog(shader: u32) void {
    const max_length: c_int = 2048;
    var actual_length: c_int = 0;
    var log: [2048]u8 = undefined;
    gl.getShaderInfoLog(shader, max_length, &actual_length, &log);
    std.debug.print("Shader info log for GL index {d}:\n{s}\n", .{ shader, log[0..@intCast(actual_length)] });
}

fn printProgramInfoLog(program: u32) void {
    const max_length: c_int = 2048;
    var actual_length: c_int = 0;
    var log: [2048]u8 = undefined;
    gl.getProgramInfoLog(program, max_length, &actual_length, &log);
    std.debug.print("Program info log for GL index {d}:\n{s}\n", .{ program, log[0..@intCast(actual_length)] });
}