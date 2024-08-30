const std = @import("std");
const zstbi = @import("zstbi");
const Bounds = @import("GeoTiffParser.zig").Bounds;
const LatLon = @import("GeoTiffParser.zig").LatLon;
const MeshGenerator = @import("mesh_generator.zig");
const Allocator = std.mem.Allocator;
const zgpu = @import("zgpu");

alloc: Allocator,
meta_data: std.json.Parsed(MetaDataList),
texture: u32,
img_dir: []const u8,
bounds: Bounds,

const TextureLoader = @This();

const MetaData = struct {
    filename: []u8,
    center: LatLon,
    bounds: Bounds,
};

const MetaDataList = []MetaData;

pub fn create(alloc: Allocator, img_dir: []const u8, meta_path: []const u8) !TextureLoader {
    const meta_data = try parseMetaData(alloc, meta_path);
    var bounds = meta_data.value[0].bounds;
    for (meta_data.value) |meta| {
        std.log.debug("Texture: {s}, bounds: ({d} W, {d} S) -> ({d} E, {d} N)", .{ meta.filename, meta.bounds.sw.lon, meta.bounds.sw.lat, meta.bounds.ne.lon, meta.bounds.ne.lat });
        if (meta.bounds.ne.lon > bounds.ne.lon) {
            bounds.ne.lon = meta.bounds.ne.lon;
        }
        if (meta.bounds.ne.lat > bounds.ne.lat) {
            bounds.ne.lat = meta.bounds.ne.lat;
        }
    }
    std.log.info("Full Texture bounds: ({d} W, {d} S) -> ({d} E, {d} N)", .{ bounds.sw.lon, bounds.sw.lat, bounds.ne.lon, bounds.ne.lat });
    zstbi.init(alloc);

    return .{
        .alloc = alloc,
        .meta_data = meta_data,
        .texture = undefined,
        .img_dir = img_dir,
        .bounds = bounds,
    };
}

pub fn deinit(self: TextureLoader) void {
    self.meta_data.deinit();
    zstbi.deinit();
}

pub fn parseMetaData(alloc: Allocator, path: []const u8) !std.json.Parsed(MetaDataList) {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();

    const s = try f.readToEndAlloc(alloc, 1_000_000_000);
    defer alloc.free(s);

    return std.json.parseFromSlice(MetaDataList, alloc, s, .{});
}

pub fn calculateTexCooords(self: TextureLoader, bounds: Bounds, mesh_positions: std.ArrayList([3]f32), mesh_uvs: *std.ArrayList([2]f32)) !void {
    const lon_scale = (bounds.ne.lon - bounds.sw.lon) / (self.bounds.ne.lon - self.bounds.sw.lon);
    const lon_offset = (bounds.sw.lon - self.bounds.sw.lon) / (self.bounds.ne.lon - self.bounds.sw.lon);
    const lat_scale = (bounds.ne.lat - bounds.sw.lat) / (self.bounds.ne.lat - self.bounds.sw.lat);
    const lat_offset = (self.bounds.ne.lat - bounds.ne.lat) / (self.bounds.ne.lat - self.bounds.sw.lat);
    const aspect = MeshGenerator.boundsAspect(bounds);

    for (mesh_positions.items, 0..) |position, i| {
        const v = lat_offset + ((position[0] / 1) + 0.5) * lat_scale;
        const u = lon_offset + ((position[2] / aspect) + 0.5) * lon_scale;
        mesh_uvs.items[i] = .{ u, v };
    }
}

fn parseFilename(filename: []const u8, col: *u32, row: *u32) !void {
    var parts = std.mem.splitAny(u8, filename, ".");
    const name = parts.first();
    var coords = std.mem.splitAny(u8, name, "_");
    var out: [2][]const u8 = undefined;
    var i: usize = 0;
    while (coords.next()) |part| {
        if (i >= 2) {
            return error.BadTexFilename;
        }
        out[i] = part;
        i += 1;
    }
    col.* = try std.fmt.parseInt(u32, out[0], 10);
    row.* = try std.fmt.parseInt(u32, out[1], 10);
}

fn findMaxRowCol(self: TextureLoader, max_col: *u32, max_row: *u32) !void {
    max_col.* = 0;
    max_row.* = 0;
    for (self.meta_data.value) |meta| {
        var col: u32 = undefined;
        var row: u32 = undefined;
        try parseFilename(meta.filename, &col, &row);
        if (col > max_col.*) {
            max_col.* = col;
        }
        if (row > max_row.*) {
            max_row.* = row;
        }
    }
}

// Cleanup
//TODO we could actually have an atlas stored as an array of 2D textures, then different mip levels for each tile (what is in focus)
pub fn loadTextures(self: *TextureLoader, gctx: *zgpu.GraphicsContext) !struct {
    tex: zgpu.TextureHandle,
    texv: zgpu.TextureViewHandle,
} {
    // Load first image to get width and height
    const img_info = blk: {
        const meta = self.meta_data.value[0];
        const img_file: [:0]const u8 = try std.fs.path.joinZ(self.alloc, &.{ self.img_dir, meta.filename });
        defer self.alloc.free(img_file);
        var img = try zstbi.Image.loadFromFile(img_file, 4); // rgba
        defer img.deinit();
        break :blk .{
            .width = img.width,
            .height = img.height,
            .num_components = img.num_components,
            .bytes_per_component = img.bytes_per_component,
            .is_hdr = img.is_hdr,
        };
    };

    var atlas_cols: u32 = 0;
    var atlas_rows: u32 = 0;
    try self.findMaxRowCol(&atlas_cols, &atlas_rows);
    atlas_cols += 1;
    atlas_rows += 1;

    const atalas_width = img_info.width * atlas_cols;
    const atlas_height = img_info.height * atlas_rows;
    var atlas = try self.alloc.alloc(u8, atalas_width * atlas_height * img_info.bytes_per_component * img_info.num_components);
    defer self.alloc.free(atlas);

    const tex = gctx.createTexture(.{
        .usage = .{ .texture_binding = true, .copy_dst = true },
        .dimension = .tdim_2d,
        .size = .{
            .width = atalas_width,
            .height = atlas_height,
            .depth_or_array_layers = 1,
        },
        .format = zgpu.imageInfoToTextureFormat(img_info.num_components, img_info.bytes_per_component, img_info.is_hdr),
    });

    const texv = gctx.createTextureView(tex, .{});

    for (self.meta_data.value) |meta| {
        const img_file: [:0]const u8 = try std.fs.path.joinZ(self.alloc, &.{ self.img_dir, meta.filename });
        defer self.alloc.free(img_file);
        var img = try zstbi.Image.loadFromFile(img_file, 4); // rgba
        defer img.deinit();

        var x_offset: u32 = 0;
        var y_offset: u32 = 0;
        try parseFilename(meta.filename, &x_offset, &y_offset);
        // Flip as we are loading texture from NW but images are indexed from SW
        y_offset = atlas_rows - y_offset - 1;
        x_offset *= img_info.width;
        y_offset *= img_info.height;
        const img_offset = x_offset * img_info.bytes_per_component * img_info.num_components + y_offset * img.bytes_per_row * atlas_cols;
        for (0..img.height) |row| {
            const row_offset = img_offset + row * atalas_width * img_info.bytes_per_component * img_info.num_components;
            const row_data = img.data[row * img.bytes_per_row .. (row + 1) * img.bytes_per_row];
            @memcpy(atlas[row_offset .. row_offset + img.bytes_per_row], row_data);
        }
    }

    gctx.queue.writeTexture(
        .{ .texture = gctx.lookupResource(tex).? },
        .{ .bytes_per_row = atalas_width * img_info.bytes_per_component * img_info.num_components, .rows_per_image = atlas_height },
        .{ .width = atalas_width, .height = atlas_height },
        u8,
        atlas,
    );

    return .{ .tex = tex, .texv = texv };
}
