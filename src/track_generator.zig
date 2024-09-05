const std = @import("std");
const utils = @import("utils.zig");
const Bounds = utils.Bounds;
const GpxParser = @import("GpxParser.zig");
const Allocator = std.mem.Allocator;

pub fn generateTrack(arena: std.mem.Allocator, bounds: Bounds, filename: []const u8) ![][2]f32 {
   var data = try GpxParser.parse(arena, filename);
   defer data.deinit();

    const gpx_points = data.trkpts.items;
    const points_m = try arena.alloc([2]f32, gpx_points.len);

    for(gpx_points, 0..) |p, i| {
        const point = utils.latLonToMSpace(bounds, .{ .lat = p.lat, .lon = p.lon });
        points_m[i] = .{ point.x, point.y };
    }

    return points_m;
}