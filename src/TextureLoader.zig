const std = @import("std");
const zstbi = @import("zstbi");
const MeshGenerator = @import("mesh_generator.zig");
const utils = @import("utils.zig");
const LatLon = utils.LatLon;
const Bounds = utils.Bounds;
const Allocator = std.mem.Allocator;
const zgpu = @import("zgpu");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;

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

pub fn calculateTexCooords(self: TextureLoader, bounds: Bounds, mesh_positions: std.ArrayList([3]f32), mesh_uvs: *std.ArrayList([2]f32), mesh_tex_index: *std.ArrayList(u32)) !void {
    // const lon_scale = (bounds.ne.lon - bounds.sw.lon) / (self.bounds.ne.lon - self.bounds.sw.lon);
    // const lon_offset = (bounds.sw.lon - self.bounds.sw.lon) / (self.bounds.ne.lon - self.bounds.sw.lon);
    // const lat_scale = (bounds.ne.lat - bounds.sw.lat) / (self.bounds.ne.lat - self.bounds.sw.lat);
    // const lat_offset = (self.bounds.ne.lat - bounds.ne.lat) / (self.bounds.ne.lat - self.bounds.sw.lat);
    const aspect = MeshGenerator.boundsAspect(bounds);

    for (mesh_positions.items, 0..) |position, i| {
        const lon = (position[2] / aspect + 0.5) * (bounds.ne.lon - bounds.sw.lon) + bounds.sw.lon;
        const lat = (position[0] + 0.5) * (bounds.ne.lat - bounds.sw.lat) + bounds.sw.lat;
        const tex_index = try self.getIndex(lon, lat);
        // const v = lat_offset + ((position[0] / 1) + 0.5) * lat_scale;
        // const u = lon_offset + ((position[2] / aspect) + 0.5) * lon_scale;
        const v = (lat - self.meta_data.value[tex_index].bounds.sw.lat) / (self.meta_data.value[tex_index].bounds.ne.lat - self.meta_data.value[tex_index].bounds.sw.lat);
        const u = (lon - self.meta_data.value[tex_index].bounds.sw.lon) / (self.meta_data.value[tex_index].bounds.ne.lon - self.meta_data.value[tex_index].bounds.sw.lon);
        mesh_uvs.items[i] = .{ u, v };
        mesh_tex_index.items[i] = tex_index;
    }
}

pub fn calculateTexCooordsGl(self: TextureLoader, bounds: Bounds, mesh_positions: [][3]f32, mesh_uvs: [][2]f32) void {
    const lon_scale = (self.bounds.ne.lon - self.bounds.sw.lon);
    const lat_scale = (self.bounds.ne.lat - self.bounds.sw.lat);

    for (mesh_positions, 0..) |position, i| {
        const pos = utils.mToLatLonSpace(bounds, .{ .x = position[0], .y = position[2] });
        const v = (self.bounds.ne.lat - pos.lat) / lat_scale; // So NW is 0,0
        const u = (pos.lon - self.bounds.sw.lon) / lon_scale;

        mesh_uvs[i] = .{ u, v };
    }
}

// fn getIndex(self: TextureLoader, lon: f64, lat: f64) !u32 {
//     for (self.meta_data.value, 0..) |meta, i| {
//         if(meta.bounds.sw.lon <= lon and lon <= meta.bounds.ne.lon and meta.bounds.sw.lat <= lat and lat <= meta.bounds.ne.lat) {
//             return @intCast(i);
//         }
//     }
//     return error.OutOfBounds;
// }

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

// TODO Cleanup
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

    const layers: u32 = @intCast(self.meta_data.value.len);

    const tex = gctx.createTexture(.{
        .usage = .{ .texture_binding = true, .copy_dst = true },
        .dimension = .tdim_2d,
        .size = .{
            .width = img_info.width,
            .height = img_info.height,
            .depth_or_array_layers = layers,
        },
        .format = zgpu.imageInfoToTextureFormat(img_info.num_components, img_info.bytes_per_component, img_info.is_hdr),
    });

    const texv = gctx.createTextureView(tex, .{ .dimension = .tvdim_2d_array });

    for (self.meta_data.value, 0..) |meta, i| {
        const img_file: [:0]const u8 = try std.fs.path.joinZ(self.alloc, &.{ self.img_dir, meta.filename });
        defer self.alloc.free(img_file);
        var img = try zstbi.Image.loadFromFile(img_file, 4); // rgba
        defer img.deinit();

        gctx.queue.writeTexture(
            .{ .texture = gctx.lookupResource(tex).?, .origin = .{.z = @intCast(i)} },
            .{ .bytes_per_row = img.bytes_per_row, .rows_per_image = img.height },
            .{ .width = img.width, .height = img.height },
            u8,
            img.data,
        );
        gctx.queue.submit(&.{});
    }

    return .{ .tex = tex, .texv = texv };
}


pub fn loadTexturesGl(self: *TextureLoader) !gl.Uint{
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

    var tex: c_uint = undefined;
    gl.genTextures(1, &tex);
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texParameteri(
        gl.TEXTURE_2D,
        gl.TEXTURE_WRAP_S,
        gl.REPEAT,
    );
    gl.texParameteri(
        gl.TEXTURE_2D,
        gl.TEXTURE_WRAP_T,
        gl.REPEAT,
    );
    gl.texParameteri(
        gl.TEXTURE_2D,
        gl.TEXTURE_MIN_FILTER,
        gl.LINEAR,
    );
    gl.texParameteri(
        gl.TEXTURE_2D,
        gl.TEXTURE_MAG_FILTER,
        gl.LINEAR,
    );

    var atlas_cols: u32 = 0;
    var atlas_rows: u32 = 0;
    try self.findMaxRowCol(&atlas_cols, &atlas_rows);
    atlas_cols += 1;
    atlas_rows += 1;
    gl.texImage2D(
        gl.TEXTURE_2D,
        0,
        gl.RGB,
        @intCast(atlas_cols * img_info.width),
        @intCast(atlas_rows * img_info.height),
        0,
        gl.RGB,
        gl.UNSIGNED_BYTE,
        null,
    );


    for (self.meta_data.value) |meta| {
        const img_file: [:0]const u8 = try std.fs.path.joinZ(self.alloc, &.{self.img_dir, meta.filename});
        defer self.alloc.free(img_file);
        var img = try zstbi.Image.loadFromFile(img_file, 0);
        defer img.deinit();

        var x_offset: u32 = 0;
        var y_offset: u32 = 0;
        try parseFilename(meta.filename, &x_offset, &y_offset);
        y_offset = atlas_rows - y_offset - 1; // Invert y axis
        x_offset *= img_info.width;
        y_offset *= img_info.height;
        gl.texSubImage2D(
            gl.TEXTURE_2D,
            0,
            @intCast(x_offset),
            @intCast(y_offset),
            @intCast(img.width),
            @intCast(img.height),
            gl.RGB,
            gl.UNSIGNED_BYTE,
            img.data.ptr,
        );
    }
    gl.generateMipmap(gl.TEXTURE_2D);

    return tex;
}