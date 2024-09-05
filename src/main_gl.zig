const std = @import("std");
const zglfw = @import("zglfw");
const AppState = @import("AppState.zig");
const Renderer = @import("opengl_renderer.zig");

pub const std_options = std.Options{
    .log_level = .info,
};

//TODO handle arguments for bounds, img_dir, geotiff, route, etc.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bounds = .{ .sw = .{ .lon = -3.3, .lat = 54.4 }, .ne = .{ .lon = -2.9, .lat = 54.6 }};
    var renderer = try Renderer.create(allocator,  bounds, "res/geo.tif", "res/test.gpx");
    defer renderer.destroy(allocator);

    var app = try AppState.create(allocator);
    defer app.destroy(allocator);


    while (!renderer.window.shouldClose() and renderer.window.getKey(.escape) != .press) {
        zglfw.pollEvents();

        app.update(renderer.window);
        renderer.draw(app);
        renderer.drawLine(app.*);
    }
}