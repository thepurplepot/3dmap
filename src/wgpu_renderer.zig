const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");
const zm = @import("zmath");
const Allocator = std.mem.Allocator;
const MeshGenerator = @import("mesh_generator.zig");
const Bounds = MeshGenerator.Bounds;
const TextureLoader = @import("TextureLoader.zig");
const AppState = @import("AppState.zig");

const vs = @embedFile("shaders/vertex.wgsl");
const fs = @embedFile("shaders/fragment.wgsl");

window: *zglfw.Window,
gctx: *zgpu.GraphicsContext,

render_pipe: zgpu.RenderPipelineHandle = .{},
frame_bg: zgpu.BindGroupHandle,
draw_bg: zgpu.BindGroupHandle,

vertex_buf: zgpu.BufferHandle,
index_buf: zgpu.BufferHandle,

depth_tex: zgpu.TextureHandle,
depth_texv: zgpu.TextureViewHandle,
tex: zgpu.TextureHandle,
texv: zgpu.TextureViewHandle,
sampler: zgpu.SamplerHandle,

const Self = @This();

const FrameUniforms = struct {
    world_to_clip: zm.Mat,
    camera_position: [3]f32,
};

const DrawUniforms = struct {
    object_to_world: zm.Mat,
    basecolor_roughness: [4]f32,
    texture: u32,
};

const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    tex_index: u32,
};

pub fn create(alloc: Allocator, window: *zglfw.Window, bounds: Bounds, geotiff: []const u8) !*Self {
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

    // Setup graphics
    const gctx = try zgpu.GraphicsContext.create(
        alloc,
        .{
            .window = window,
            .fn_getTime = @ptrCast(&zglfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
            .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
            .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
            .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
            .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
        },
        .{},
    );
    errdefer gctx.destroy(alloc);

    // Textures
    var textureLoader = try TextureLoader.create(arena, "output/", "output/meta_data.json");
    defer textureLoader.deinit();
    const tex = try textureLoader.loadTextures(gctx);
    std.debug.print("Loaded textures\n", .{});
    const sampler = gctx.createSampler(.{ .mag_filter = .linear, .min_filter = .linear });
    var mesh_uvs = std.ArrayList([2]f32).init(arena);
    try mesh_uvs.resize(mesh_positions.items.len);
    var mesh_tex_index = std.ArrayList(u32).init(arena);
    try mesh_tex_index.resize(mesh_positions.items.len);
    try textureLoader.calculateTexCooords(bounds, mesh_positions, &mesh_uvs, &mesh_tex_index);

    // Uniform buffer and layout
    const frame_bgl = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, true, 0),
    });
    defer gctx.releaseResource(frame_bgl);

    const draw_bgl = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, true, 0),
        zgpu.textureEntry(1, .{ .fragment = true }, .float, .tvdim_2d_array, false),
        zgpu.samplerEntry(2, .{ .fragment = true }, .filtering),
    });
    defer gctx.releaseResource(draw_bgl);

    const frame_bg = gctx.createBindGroup(frame_bgl, &.{
        .{
            .binding = 0,
            .buffer_handle = gctx.uniforms.buffer,
            .offset = 0,
            .size = @sizeOf(FrameUniforms),
        },
    });

    const draw_bg = gctx.createBindGroup(draw_bgl, &.{
        .{
            .binding = 0,
            .buffer_handle = gctx.uniforms.buffer,
            .offset = 0,
            .size = @sizeOf(DrawUniforms),
        },
        .{
            .binding = 1,
            .texture_view_handle = tex.texv,
        },
        .{
            .binding = 2,
            .sampler_handle = sampler,
        },
    });

    // Vertex buffer
    const vertex_buf = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = vertices_count * @sizeOf(Vertex),
    });
    {
        var vertex_data = try arena.alloc(Vertex, vertices_count);
        defer arena.free(vertex_data);

        for (mesh_positions.items, 0..) |_, i| {
            vertex_data[i].position = mesh_positions.items[i];
            vertex_data[i].normal = mesh_normals.items[i];
            vertex_data[i].uv = mesh_uvs.items[i];
            vertex_data[i].tex_index = mesh_tex_index.items[i];
        }
        gctx.queue.writeBuffer(gctx.lookupResource(vertex_buf).?, 0, Vertex, vertex_data);
    }

    // Index buffer
    const index_buf = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = indices_count * @sizeOf(MeshGenerator.IndexType),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(index_buf).?, 0, MeshGenerator.IndexType, mesh_indices.items);

    // Depth texture
    const depth_tex = createDepthTexture(gctx);

    // Pipeline
    const renderer = try alloc.create(Self);
    renderer.* = .{
        .window = window,
        .gctx = gctx,
        .frame_bg = frame_bg,
        .draw_bg = draw_bg,
        .vertex_buf = vertex_buf,
        .index_buf = index_buf,
        .depth_tex = depth_tex.tex,
        .depth_texv = depth_tex.texv,
        .tex = tex.tex,
        .texv = tex.texv,
        .sampler = sampler,
    };

    zgpu.createRenderPipelineSimple(
        alloc,
        gctx,
        &.{ frame_bgl, draw_bgl },
        vs,
        fs,
        @sizeOf(Vertex),
        &.{
            .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "normal"), .shader_location = 1 },
            .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 2 },
            .{ .format = .uint32, .offset = @offsetOf(Vertex, "tex_index"), .shader_location = 3 },
        },
        .{ .topology = .triangle_list },
        zgpu.GraphicsContext.swapchain_format,
        .{
            .format = .depth32_float,
            .depth_write_enabled = true,
            .depth_compare = .less,
        },
        &renderer.render_pipe,
    );

    return renderer;
}

pub fn destroy(self: *Self, alloc: Allocator) void {
    self.gctx.destroy(alloc);
    alloc.destroy(self);
}

pub fn draw(self: *Self, state: *AppState) void {
    const gctx = self.gctx;
    state.size.width = gctx.swapchain_descriptor.width;
    state.size.height = gctx.swapchain_descriptor.height;

    const cam_world_to_view = zm.lookToLh(
        zm.loadArr3(state.camera.position),
        zm.loadArr3(state.camera.forward),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );
    const cam_view_to_clip = zm.perspectiveFovLh(
        0.25 * math.pi,
        @as(f32, @floatFromInt(state.size.width)) / @as(f32, @floatFromInt(state.size.height)),
        0.01,
        200.0,
    );
    const cam_world_to_clip = zm.mul(cam_world_to_view, cam_view_to_clip);

    const mesh_obj_to_world = zm.mul(zm.scaling(128.0, 128 * state.options.elevation_scale, 128.0), zm.rotationY(-90.0 / math.deg_per_rad));

    // Lookup common resources which may be needed for all the passes.
    const depth_texv = gctx.lookupResource(self.depth_texv) orelse return;
    const frame_bg = gctx.lookupResource(self.frame_bg) orelse return;
    const draw_bg = gctx.lookupResource(self.draw_bg) orelse return;
    const vertex_buf_info = gctx.lookupResourceInfo(self.vertex_buf) orelse return;
    const index_buf_info = gctx.lookupResourceInfo(self.index_buf) orelse return;
    std.debug.print("Got common resorces\n", .{});

    const swapchain_texv = gctx.swapchain.getCurrentTextureView();
    defer swapchain_texv.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        pass: {
            const render_pipe = gctx.lookupResource(self.render_pipe) orelse break :pass;

            const pass = zgpu.beginRenderPassSimple(
                encoder,
                .clear,
                swapchain_texv,
                .{ .r = 0.2, .g = 0.4, .b = 0.8, .a = 1.0 },
                depth_texv,
                1.0,
            );
            defer zgpu.endReleasePass(pass);

            pass.setVertexBuffer(0, vertex_buf_info.gpuobj.?, 0, vertex_buf_info.size);
            pass.setIndexBuffer(
                index_buf_info.gpuobj.?,
                if (MeshGenerator.IndexType == u16) .uint16 else .uint32,
                0,
                index_buf_info.size,
            );
            pass.setPipeline(render_pipe);

            // Update "world to clip" (camera) xform.
            {
                const mem = gctx.uniformsAllocate(FrameUniforms, 1);
                mem.slice[0] = .{
                    .world_to_clip = zm.transpose(cam_world_to_clip),
                    .camera_position = state.camera.position,
                };
                pass.setBindGroup(0, frame_bg, &.{mem.offset});
            }

            // Draw mesh
            {
                const mem = gctx.uniformsAllocate(DrawUniforms, 1);
                mem.slice[0] = .{
                    .object_to_world = mesh_obj_to_world,
                    .basecolor_roughness = .{ 0.2, 0.2, 0.2, 1.0 },
                    .texture = @intFromBool(state.options.texture),
                };
                pass.setBindGroup(1, draw_bg, &.{mem.offset});
                pass.drawIndexed(@intCast(index_buf_info.size / @sizeOf(MeshGenerator.IndexType)), 1, 0, 0, 0);
            }
        }
        {
            const pass = zgpu.beginRenderPassSimple(encoder, .load, swapchain_texv, null, null, null);
            defer zgpu.endReleasePass(pass);
            zgui.backend.draw(pass);
        }

        break :commands encoder.finish(null);
    };
    defer commands.release();

    gctx.submit(&.{commands});
}

pub fn createDepthTexture(gctx: *zgpu.GraphicsContext) struct {
    tex: zgpu.TextureHandle,
    texv: zgpu.TextureViewHandle,
} {
    const tex = gctx.createTexture(.{
        .usage = .{ .render_attachment = true },
        .dimension = .tdim_2d,
        .size = .{
            .width = gctx.swapchain_descriptor.width,
            .height = gctx.swapchain_descriptor.height,
            .depth_or_array_layers = 1,
        },
        .format = .depth32_float,
        .mip_level_count = 1,
        .sample_count = 1,
    });
    const texv = gctx.createTextureView(tex, .{});
    return .{ .tex = tex, .texv = texv };
}
