const std = @import("std");
const GeoTiffParser = @import("GeoTiffParser.zig");
const utils = @import("utils.zig");
const Bounds = utils.Bounds;
const Allocator = std.mem.Allocator;
pub const IndexType = u32;
const zm = @import("zmath");

pub fn generateMesh(
    arena: Allocator,
    bounds: Bounds,
    filename: []const u8,
) !struct {
    indices: []IndexType,
    positions: [][3]f32,
    normals: [][3]f32,
    width_m: f32,
    height_m: f32,
    ele_texture: c_uint,
}{
    var parser = try GeoTiffParser.create(arena, filename);
    defer parser.deinit(arena);

    const lat_scale: f32 = @floatCast(parser.inner.adfGeoTransform[5]);
    const lon_scale: f32 = @floatCast(parser.inner.adfGeoTransform[1]);
    var width: usize = undefined;
    var height: usize = undefined;
    const elevations = try parser.sampleGrid(arena, bounds, &width, &height);
    defer arena.free(elevations);
    std.log.info("Sampled grid - Width: {d}, Height: {d}", .{width, height});

    const mesh_indices = try arena.alloc(IndexType, (width - 1) * (height - 1) * 6);
    const mesh_positions = try arena.alloc([3]f32, width * height);
    const mesh_normals = try arena.alloc([3]f32, width * height);
    
    try generateVertices(mesh_indices, mesh_positions, width, height, elevations, bounds, lat_scale, lon_scale);
    try generateNormals(mesh_normals, mesh_positions, mesh_indices);
    std.log.info("Generated mesh - Vertices: {d}, Indices: {d}", .{mesh_positions.len, mesh_indices.len});
    const tex = try uploadElevationTexture(elevations, width, height);

    const size = utils.latLonToMSpace(bounds, bounds.ne);
    std.log.info("Bounds size: {d} x {d} m", .{size.x, size.y});
    return .{.indices = mesh_indices, .positions = mesh_positions, .normals = mesh_normals, .width_m = size.x, .height_m = size.y, .ele_texture = tex};
}

const gl = @import("zopengl").bindings; //FIXME
fn uploadElevationTexture(elevations: []const f32, width: usize, height: usize) !c_uint {
    var tex: c_uint = undefined;
    gl.genTextures(1, &tex);
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.R32F, @intCast(width), @intCast(height), 0, gl.RED, gl.FLOAT, elevations.ptr);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.bindTexture(gl.TEXTURE_2D, 0);

    return tex;
}

fn generateVertices(mesh_indicies: []IndexType, mesh_positions: [][3]f32, width: usize, height: usize, elevations: []f32, bounds: Bounds, lat_scale: f32, lon_scale: f32) !void {
    var index_count: usize = 0;
    // NW corner is 0,0
    for (0..height) |y| {
        for (0..width) |x| {
            const i = y * width + x;
            const lon = bounds.sw.lon + @as(f32, @floatFromInt(x)) * lon_scale;
            const lat = bounds.ne.lat + @as(f32, @floatFromInt(y)) * lat_scale; 
            const ele = elevations[i];
            const point = utils.latLonToMSpace(bounds, .{ .lat = lat, .lon = lon });
            
            mesh_positions[i] = .{point.x, ele, point.y};

            if (x < (width - 1) and y < (height - 1)) {
                const @"i0" = y * width + x;
                const @"i1" = @"i0" + 1;
                const @"i2" = @"i0" + width;
                const @"i3" = @"i2" + 1;
                mesh_indicies[index_count] = @intCast(@"i0");
                mesh_indicies[index_count + 1] = @intCast(@"i1");
                mesh_indicies[index_count + 2] = @intCast(@"i2");
                mesh_indicies[index_count + 3] = @intCast(@"i1");
                mesh_indicies[index_count + 4] = @intCast(@"i3");
                mesh_indicies[index_count + 5] = @intCast(@"i2");
                index_count += 6;
            }
        }
    }
}

fn generateNormals(mesh_normals: [][3]f32, mesh_positions: []const [3]f32, mesh_indices: []const IndexType) !void {
    for (0..mesh_normals.len) |i| {
        mesh_normals[i] = .{0.0, 0.0, 0.0};
    }
    for (0..mesh_indices.len / 3) |i| {
        const @"i0" = mesh_indices[i * 3];
        const @"i1" = mesh_indices[i * 3 + 1];
        const @"i2" = mesh_indices[i * 3 + 2];

        const v0 = zm.loadArr3(mesh_positions[@"i0"]);
        const v1 = zm.loadArr3(mesh_positions[@"i1"]);
        const v2 = zm.loadArr3(mesh_positions[@"i2"]);

        const e1 = v1 - v0;
        const e2 = v2 - v0;
        const normal = zm.cross3(e1, e2);
        for ([_]IndexType{@"i0", @"i1", @"i2"}) |index| {
            const n = mesh_normals[index];
            mesh_normals[index] = .{n[0] + normal[0], n[1] + normal[1], n[2] + normal[2]};
        }
    }
    // Normalize
    for (0..mesh_normals.len) |i| {
        const normal = mesh_normals[i];
        const length = std.math.sqrt(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2]);
        mesh_normals[i] = .{normal[0] / length, normal[1] / length, normal[2] / length};
    }
}