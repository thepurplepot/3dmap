const std = @import("std");
const GeoTiffParser = @import("GeoTiffParser.zig");
pub const Bounds = GeoTiffParser.Bounds;
const Allocator = std.mem.Allocator;
pub const IndexType = u32;
const zm = @import("zmath");

pub fn generateMesh(
    alloc: Allocator,
    bounds: Bounds,
    filename: []const u8,
    mesh_indices: *std.ArrayList(IndexType),
    mesh_positions: *std.ArrayList([3]f32),
    mesh_normals: *std.ArrayList([3]f32),
) !void {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var parser = try GeoTiffParser.create(arena, filename);
    defer parser.deinit(arena);

    // const data_bounds = parser.inner.bounds;
    var width: usize = undefined;
    var height: usize = undefined;
    const elevations = try parser.sampleGrid(arena, bounds, &width, &height);
    defer arena.free(elevations);
    const m_scale = (bounds.ne.lat - bounds.sw.lat) * 111111;
    const aspect = boundsAspect(bounds);
    std.log.info("Sampled grid - Width: {d}, Height: {d} - Scale: {d} m/uv", .{width, height, m_scale});
    std.log.info("Bounds aspect ratio: {d} lon/lat (in m space)", .{aspect});

    // try mesh_positions.resize(width * height);
    // try mesh_indices.resize((width - 1) * (height - 1) * 6);
    try generateVertices(mesh_indices, mesh_positions, width, height, elevations, aspect, m_scale);
    try generateNormals(mesh_normals, mesh_positions.*, mesh_indices.*);
    std.log.info("Generated mesh - Vertices: {d}, Indices: {d}", .{mesh_positions.items.len, mesh_indices.items.len});
}

pub fn boundsAspect(bounds: Bounds) f32 {
    const lon_diff = bounds.ne.lon - bounds.sw.lon;
    const lat_diff = bounds.ne.lat - bounds.sw.lat;

    // Convert longitude and latitude differences to meters
    const earth_radius = 6371000.0;
    const x = lon_diff * (std.math.cos(bounds.sw.lat * std.math.pi / 180.0) * std.math.pi / 180.0) * earth_radius;
    const y = lat_diff * (std.math.pi / 180.0) * earth_radius;

    return x / y;
}

// pub fn toMSpace(bounds: Bounds, lon: f32, lat: f32) [2]f32 {
//     const lon_diff = lon - bounds.sw.lon;
//     const lat_diff = lat - bounds.sw.lat;

//     // Convert longitude and latitude differences to meters
//     const earth_radius = 6371000.0;
//     const x = lon_diff * (std.math.cos(bounds.sw.lat * std.math.pi / 180.0) * std.math.pi / 180.0) * earth_radius;
//     const y = lat_diff * (std.math.pi / 180.0) * earth_radius;

//     return .{x, y};
// }

//TODO do this in M space
fn generateVertices(mesh_indices: *std.ArrayList(IndexType), mesh_positions: *std.ArrayList([3]f32), width: usize, height: usize, elevations: []f32, aspect: f32, m_scale: f32) !void {
    for (0..height) |y| {
        for (0..width) |x| {
            const ele = elevations[y * width + x] / m_scale;
            const u = (@as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(height - 1)) - 0.5);
            const v = (@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width - 1)) - 0.5) * aspect;
            
            try mesh_positions.append(.{u, ele, v});

            if (x < (width - 1) and y < (height - 1)) {
                const @"i0" = y * width + x;
                const @"i1" = @"i0" + 1;
                const @"i2" = @"i0" + width;
                const @"i3" = @"i2" + 1;
                try mesh_indices.append(@intCast(@"i0"));
                try mesh_indices.append(@intCast(@"i1"));
                try mesh_indices.append(@intCast(@"i2"));
                try mesh_indices.append(@intCast(@"i1"));
                try mesh_indices.append(@intCast(@"i3"));
                try mesh_indices.append(@intCast(@"i2"));
            }
        }
    }
}

fn generateNormals(mesh_normals: *std.ArrayList([3]f32), mesh_positions: std.ArrayList([3]f32), mesh_indices: std.ArrayList(IndexType)) !void {
    try mesh_normals.appendNTimes(.{0, 0, 0}, mesh_positions.items.len);
    for (0..mesh_indices.items.len / 3) |i| {
        const @"i0" = mesh_indices.items[i * 3];
        const @"i1" = mesh_indices.items[i * 3 + 1];
        const @"i2" = mesh_indices.items[i * 3 + 2];

        const v0 = zm.loadArr3(mesh_positions.items[@"i0"]);
        const v1 = zm.loadArr3(mesh_positions.items[@"i1"]);
        const v2 = zm.loadArr3(mesh_positions.items[@"i2"]);

        const e1 = v1 - v0;
        const e2 = v2 - v0;
        const normal = zm.cross3(e1, e2);
        for ([_]IndexType{@"i0", @"i1", @"i2"}) |index| {
            const n = mesh_normals.items[index];
            mesh_normals.items[index] = .{n[0] + normal[0], n[1] + normal[1], n[2] + normal[2]};
        }
    }
    // Normalize
    for (0..mesh_normals.items.len) |i| {
        const normal = mesh_normals.items[i];
        const length = std.math.sqrt(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2]);
        mesh_normals.items[i] = .{normal[0] / length, normal[1] / length, normal[2] / length};
    }
}