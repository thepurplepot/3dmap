const std = @import("std");
const zglfw = @import("zglfw");
const AppState = @import("AppState.zig");
const zgui = @import("zgui");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

pub const std_options = std.Options{
    .log_level = .info,
};

pub fn main() !void {
    try zglfw.init();
    defer zglfw.terminate();

    zglfw.windowHintTyped(.client_api, .no_api);

    const window = try zglfw.Window.create(800, 500, "3D Map", null);
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var app = try AppState.create(allocator, window, .{ .sw = .{ .lon = -3.3, .lat = 54.4 }, .ne = .{ .lon = -2.8, .lat = 54.7 } }, "res/geo.tif");
    defer app.destroy(allocator);

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    zgui.init(allocator);
    defer zgui.deinit();

    _ = zgui.io.addFontFromFile("res/Roboto-Medium.ttf", std.math.floor(16.0 * scale_factor));

    zgui.backend.init(
        window,
        app.gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
        @intFromEnum(wgpu.TextureFormat.undef),
    );
    defer zgui.backend.deinit();

    zgui.getStyle().scaleAllSizes(scale_factor);

    // var frame_timer = try std.time.Timer.start();
    // const frame_rate_target = 60;

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        // {
        //     // spin loop for frame limiter
        //     const target_ns = @divTrunc(std.time.ns_per_s, frame_rate_target);
        //     while (frame_timer.read() < target_ns) {
        //         std.atomic.spinLoopHint();
        //     }
        //     frame_timer.reset();
        // }

        zglfw.pollEvents();

        app.update();
        app.draw();

        if (app.gctx.present() == .swap_chain_resized) {
            // Release old depth texture.
            app.gctx.releaseResource(app.depth_texv);
            app.gctx.destroyResource(app.depth_tex);

            // Create a new depth texture to match the new window size.
            const depth = AppState.createDepthTexture(app.gctx);
            app.depth_tex = depth.tex;
            app.depth_texv = depth.texv;
        }
    }
}