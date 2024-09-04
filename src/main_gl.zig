const std = @import("std");
const zglfw = @import("zglfw");
const AppState = @import("AppState.zig");
const Renderer = @import("opengl_renderer.zig");

pub const std_options = std.Options{
    .log_level = .info,
};

//TODO handle arguments for bounds, img_dir, geotiff, etc.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer = try Renderer.create(allocator, .{ .sw = .{ .lon = -3.1, .lat = 54.4 }, .ne = .{ .lon = -2.8, .lat = 54.7 } }, "res/geo.tif");
    defer renderer.destroy(allocator);

    var app = try AppState.create(allocator);
    defer app.destroy(allocator);


    while (!renderer.window.shouldClose() and renderer.window.getKey(.escape) != .press) {
        zglfw.pollEvents();

        app.update(renderer.window);
        renderer.draw(app);
    }
}