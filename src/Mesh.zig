const std = @import("std");
const Allocator = std.mem.Allocator;
const gl = @import("opengl_bindings.zig");
const zstbi = @import("zstbi");
const LatLon = @import("GeoTiffParser.zig").Position;

//TODO allow selection between texture and solid colour
//TODO improve lighting


pub const Bounds = struct {
    min: LatLon, // SW
    max: LatLon, // NE
};

const Point = struct {
    x: f32,
    y: f32,
};

const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    texCoords: [2]f32,
};

const Error = error{
    OpenGLError,
} || Allocator.Error;

vertices: []Vertex,
indices: []u32,
vao: u32,
vbo: u32,
ebo: u32,
model: [16]f32,
texLoader: TextureLoader,

const Self = @This();

fn findDataBounds(positions: []LatLon) Bounds {
    var ret = Bounds{
        .min = .{ .lat = 90.0, .lon = 180.0 },
        .max = .{ .lat = -90.0, .lon = -180.0 },
    };
    for (positions) |position| {
        if (position.lon < ret.min.lon) {
            ret.min.lon = position.lon;
        }
        if (position.lon > ret.max.lon) {
            ret.max.lon = position.lon;
        }
        if (position.lat < ret.min.lat) {
            ret.min.lat = position.lat;
        }
        if (position.lat > ret.max.lat) {
            ret.max.lat = position.lat;
        }
    }
    return ret;
}

//Top left of bounds is (0, 0) m
fn positionToMSpace(position: LatLon, bounds: Bounds) Point {
    const lon_diff = position.lon - bounds.min.lon;
    const lat_diff = position.lat - bounds.min.lat; //TODO check this is the right reference point

    // Convert longitude and latitude differences to meters
    const earth_radius = 6371000.0;
    const x = lon_diff * (std.math.cos(bounds.min.lat * std.math.pi / 180.0) * std.math.pi / 180.0) * earth_radius;
    const y = lat_diff * (std.math.pi / 180.0) * earth_radius;

    return .{
        .x = @floatCast(x),
        .y = @floatCast(y),
    };
}

fn positionWithinBounds(position: LatLon, bounds: Bounds) bool {
    return position.lon >= bounds.min.lon and position.lon <= bounds.max.lon and position.lat >= bounds.min.lat and position.lat <= bounds.max.lat;
}

fn createModelMatrix(max_x: f32, max_y: f32, window_width: f32, window_height: f32, elevation_scale: f32) [16]f32 {
    const scale_x = window_width / max_x;
    const scale_y = window_height / max_y;
    const scale = @max(scale_x, scale_y);
    std.log.debug("Mesh x/y scale: {d}", .{scale});
    const scale_z = elevation_scale * scale;
    std.log.debug("Mesh z scale: {d}", .{scale_z});

    const translate_x = window_width / 2.0;
    const translate_y = window_height / 2.0;

    return [16]f32{
        scale,        0.0,          0.0,     0.0,
        0.0,          scale,        0.0,     0.0,
        0.0,          0.0,          scale_z, 0.0,
        -translate_x, -translate_y, 0.0,     1.0,
    };
}

//FIXME ugly
pub fn updateElevationScale(self: *Self, elevation_scale: f32) void {
    self.model[10] = self.model[0] * elevation_scale;
}

pub fn meshFromElevations(alloc: Allocator, bounds: Bounds, elevations: []f64, positions: []LatLon) !Self {
    const input_bounds = findDataBounds(positions);
    std.debug.assert(bounds.min.lon >= input_bounds.min.lon);
    std.debug.assert(bounds.max.lon <= input_bounds.max.lon);
    std.debug.assert(bounds.min.lat >= input_bounds.min.lat);
    std.debug.assert(bounds.max.lat <= input_bounds.max.lat);

    //TODO params
    const texLoader = try TextureLoader.init(alloc, "output/", "output/meta_data.json");

    var vertices = std.ArrayList(Vertex).init(alloc);

    var width: usize = 0;
    var max_elevation: f32 = 0.0;
    var max_x: f32 = 0.0;
    var max_y: f32 = 0.0;
    var skiped_last = false;
    var flag = false;
    for (positions, 0..) |position, i| {
        if (!positionWithinBounds(position, bounds)) {
            skiped_last = true;
            continue;
        }
        const m_position = positionToMSpace(position, bounds);

        if (skiped_last and vertices.items.len > 1 and !flag) {
            width = vertices.items.len;
            std.log.debug("Mesh width: {} elements", .{width});
            flag = true;
        }

        const x: f32 = m_position.x;
        if (x > max_x) {
            max_x = x;
        }
        const y: f32 = m_position.y;
        if (y > max_y) {
            max_y = y;
        }
        const z: f32 = @floatCast(elevations[i]);
        if (z > max_elevation) {
            max_elevation = z;
        }

        const texCoords = texLoader.calculateTexCooords(position);
        const vertex = Vertex{
            .position = [_]f32{ x, y, z },
            .normal = [_]f32{ 0.0, 0.0, 0.0 },
            .texCoords = [_]f32{ texCoords.x, texCoords.y },
        };
        try vertices.append(vertex);

        skiped_last = false;
    }
    const height = vertices.items.len / width;
    std.log.debug("Mesh height: {} elements", .{height});
    std.log.debug("Mesh verticies: {}", .{vertices.items.len});
    std.log.debug("Max elevation: {d} m", .{max_elevation});
    std.log.debug("Max x: {d:.2} m", .{max_x});
    std.log.debug("Max y: {d:.2} m", .{max_y});

    var indices = try alloc.alloc(u32, (width - 1) * (height - 1) * 6);

    var count: usize = 0;
    for (0..height - 1) |y| {
        for (0..width - 1) |x| {
            const i: u32 = @intCast(y * width + x);
            indices[count] = i;
            indices[count + 1] = i + 1;
            indices[count + 2] = i + @as(u32, @intCast(width));

            indices[count + 3] = i + 1;
            indices[count + 4] = i + @as(u32, @intCast(width)) + 1;
            indices[count + 5] = i + @as(u32, @intCast(width));
            count += 6;
        }
    }

    // Calculate normals
    var i: usize = 0;
    while (i + 2 < indices.len) {
        const @"i0" = indices[i];
        const @"i1" = indices[i + 1];
        const @"i2" = indices[i + 2];

        const v0 = vertices.items[@"i0"].position;
        const v1 = vertices.items[@"i1"].position;
        const v2 = vertices.items[@"i2"].position;

        const edge1 = [_]f32{ v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2] };
        const edge2 = [_]f32{ v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2] };
        const normal = [_]f32{
            edge1[1] * edge2[2] - edge1[2] * edge2[1],
            edge1[2] * edge2[0] - edge1[0] * edge2[2],
            edge1[0] * edge2[1] - edge1[1] * edge2[0],
        };

        for ([_]u32{ @"i0", @"i1", @"i2" }) |index| {
            vertices.items[index].normal[0] += normal[0];
            vertices.items[index].normal[1] += normal[1];
            vertices.items[index].normal[2] += normal[2];
        }
        i += 3;
    }

    // Normalize the normals
    for (vertices.items) |*vertex| {
        const length = std.math.sqrt(vertex.normal[0] * vertex.normal[0] + vertex.normal[1] * vertex.normal[1] + vertex.normal[2] * vertex.normal[2]);
        vertex.normal[0] /= length;
        vertex.normal[1] /= length;
        vertex.normal[2] /= length;
    }

    const model = createModelMatrix(max_x, max_y, 2.0, 2.0, 1.0);

    return init(try vertices.toOwnedSlice(), indices, model, texLoader);
}

pub fn init(vertices: []Vertex, indices: []u32, model: [16]f32, texLoader: TextureLoader) !Self {
    var mesh = Self{
        .vertices = vertices,
        .indices = indices,
        .vao = 0,
        .vbo = 0,
        .ebo = 0,
        .model = model,
        .texLoader = texLoader,
    };
    try mesh.setupMesh();

    return mesh;
}

pub fn deinit(self: Self, alloc: Allocator) void {
    // gl.glDeleteVertexArray(self.VAO);
    gl.glDeleteBuffer(self.vbo);
    gl.glDeleteBuffer(self.ebo);
    alloc.free(self.vertices);
    alloc.free(self.indices);
    self.texLoader.deinit();
}

pub fn setupMesh(self: *Self) !void {
    // create buffers/arrays
    self.vao = gl.glCreateVertexArray();
    self.vbo = gl.glCreateBuffer();
    self.ebo = gl.glCreateBuffer();

    gl.glBindVertexArray(self.vao);
    // load data into vertex buffers
    gl.glBindBuffer(gl.c.GL_ARRAY_BUFFER, self.vbo);
    gl.glBufferData(gl.c.GL_ARRAY_BUFFER, @ptrCast(self.vertices.ptr), self.vertices.len * @sizeOf(Vertex), gl.c.GL_STATIC_DRAW);

    gl.glBindBuffer(gl.c.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
    gl.glBufferData(gl.c.GL_ELEMENT_ARRAY_BUFFER, @ptrCast(self.indices.ptr), self.indices.len * @sizeOf(u32), gl.c.GL_STATIC_DRAW);

    // set the vertex attribute pointers
    // vertex Positions
    gl.glVertexAttribPointer(0, 3, gl.c.GL_FLOAT, false, @sizeOf(Vertex), 0);
    gl.glEnableVertexAttribArray(0);
    // vertex normals
    gl.glVertexAttribPointer(1, 3, gl.c.GL_FLOAT, false, @sizeOf(Vertex), 3 * @sizeOf(f32));
    gl.glEnableVertexAttribArray(1);
    // vertex texture coords
    gl.glEnableVertexAttribArray(2);
    gl.glVertexAttribPointer(2, 2, gl.c.GL_FLOAT, false, @sizeOf(Vertex), 6 * @sizeOf(f32));

    try self.texLoader.loadTextures();

    gl.glBindVertexArray(0);
}

pub fn draw(self: Self, program: u32) void {
    gl.glUseProgram(program);

    // const objectColorLocation = gl.glGetUniformLoc(program, "objectColor", 11);
    // gl.glUniform3f(objectColorLocation, 0.5, 0.5, 0.31); // Example color

    const modelLoc = gl.glGetUniformLoc(program, "model", 5);
    gl.c.glUniformMatrix4fv(@bitCast(modelLoc), 1, gl.c.GL_FALSE, &self.model);

    // draw mesh
    gl.glBindVertexArray(self.vao);
    gl.glDrawElements(gl.c.GL_TRIANGLES, @intCast(self.indices.len), gl.c.GL_UNSIGNED_INT, 0);
    gl.glBindVertexArray(0);
}

//TODO move lighting to separate file
pub fn setupLighting(program: u32) void {
    gl.glUseProgram(program);

    const lightColorLocation = gl.glGetUniformLoc(program, "lightColor", 10);
    gl.glUniform3f(lightColorLocation, 1.0, 1.0, 1.0); //White light

    const lightPosLocation = gl.glGetUniformLoc(program, "lightPos", 8);
    gl.glUniform3f(lightPosLocation, 2.2, 2.0, 4.0); // Off to the right
}

//Tiled textures

const TextureLoader = struct {
    alloc: Allocator,
    meta_data: std.json.Parsed(MetaDataList),
    texture: u32,
    img_dir: []const u8,
    bounds: Bounds,

    const MetaData = struct {
        filename: []u8,
        center: LatLon,
        bounds: Bounds,
    };

    const MetaDataList = []MetaData;

    pub fn init(alloc: Allocator, img_dir: []const u8, meta_path: []const u8) !TextureLoader {
        const meta_data = try parseMetaData(alloc, meta_path);
        var bounds = meta_data.value[0].bounds;
        for(meta_data.value) |meta| {
            std.log.debug("Texture: {s}, bounds: {d}, {d} -> {d}, {d}", .{meta.filename, meta.bounds.min.lon, meta.bounds.min.lat, meta.bounds.max.lon, meta.bounds.max.lat});
            if(meta.bounds.max.lon > bounds.max.lon) {
                bounds.max.lon = meta.bounds.max.lon;
            }
            if(meta.bounds.max.lat > bounds.max.lat) {
                bounds.max.lat = meta.bounds.max.lat;
            }
        }
        std.log.debug("Full Texture bounds: {d}, {d} -> {d}, {d}", .{bounds.min.lon, bounds.min.lat, bounds.max.lon, bounds.max.lat});
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
        gl.c.glDeleteTextures(1, &self.texture);
    }

    pub fn parseMetaData(alloc: Allocator, path: []const u8) !std.json.Parsed(MetaDataList) {
        const f = try std.fs.cwd().openFile(path, .{});
        defer f.close();

        const s = try f.readToEndAlloc(alloc, 1_000_000_000);
        defer alloc.free(s);

        return std.json.parseFromSlice(MetaDataList, alloc, s, .{});
    }

    fn posInBounds(position: LatLon, bounds: Bounds) bool {
        return position.lon >= bounds.min.lon and position.lon <= bounds.max.lon and position.lat >= bounds.min.lat and position.lat <= bounds.max.lat;
    }

    pub fn calculateTexCooords(self: TextureLoader, position: LatLon) Point {
        if(position.lon < self.bounds.min.lon or position.lon > self.bounds.max.lon or position.lat < self.bounds.min.lat or position.lat > self.bounds.max.lat) {
            std.log.warn("Vertex out of bounds: {d}, {d}", .{position.lon, position.lat});
        }
        const lon_diff = position.lon - self.bounds.min.lon;
        const lat_diff = position.lat - self.bounds.min.lat;

        const u = lon_diff / (self.bounds.max.lon - self.bounds.min.lon);
        const v = lat_diff / (self.bounds.max.lat - self.bounds.min.lat);

        return .{
            .x = @floatCast(u),
            .y = @floatCast(v),
        };
    }

    fn parseFilename(filename: []const u8, col: *u32, row: *u32) !void {
        var parts = std.mem.split(u8, filename, ".");
        const name = parts.first();
        var coords = std.mem.split(u8, name, "_");
        var out: [2][]const u8 = undefined;
        var i: usize = 0;
        while(coords.next()) |part| {
            if(i >= 2) {
                return error.BadTexFilename;
            }
            out[i] = part;
            i += 1;
        }
        col.* = try std.fmt.parseInt(u32, out[0], 10);
        row.* = try std.fmt.parseInt(u32, out[1], 10);
    }

    fn findMaxRowCol(self: TextureLoader, max_col: *u32, max_row:*u32) !void {
        max_col.* = 0;
        max_row.* = 0;
        for(self.meta_data.value) |meta| {
            var col: u32 = undefined;
            var row: u32 = undefined;
            try parseFilename(meta.filename, &col, &row);
            if(col > max_col.*) {
                max_col.* = col;
            }
            if(row > max_row.*) {
                max_row.* = row;
            }
        }
    }

    pub fn loadTextures(self: *TextureLoader) !void {
        const img_width = 1280; //FIXME
        const img_height = 1235;
        self.texture = gl.glCreateTexture();
        gl.glBindTexture(gl.c.GL_TEXTURE_2D, self.texture);
        gl.glTexParameteri(
            gl.c.GL_TEXTURE_2D_ARRAY,
            gl.c.GL_TEXTURE_WRAP_S,
            gl.c.GL_REPEAT,
        );
        gl.glTexParameteri(
            gl.c.GL_TEXTURE_2D_ARRAY,
            gl.c.GL_TEXTURE_WRAP_T,
            gl.c.GL_REPEAT,
        );
        gl.glTexParameteri(
            gl.c.GL_TEXTURE_2D_ARRAY,
            gl.c.GL_TEXTURE_MIN_FILTER,
            gl.c.GL_LINEAR,
        );
        gl.glTexParameteri(
            gl.c.GL_TEXTURE_2D_ARRAY,
            gl.c.GL_TEXTURE_MAG_FILTER,
            gl.c.GL_LINEAR,
        );

        var max_col: u32 = 0;
        var max_row: u32 = 0;
        try self.findMaxRowCol(&max_col, &max_row);
        max_col += 1;
        max_row += 1;

        const atlas_width = img_width * max_col; //FIXME
        const atlas_height = img_height * max_row;
        gl.c.glTexImage2D(
            gl.c.GL_TEXTURE_2D,
            0,
            gl.c.GL_RGB,
            @intCast(atlas_width),
            @intCast(atlas_height),
            0,
            gl.c.GL_RGB,
            gl.c.GL_UNSIGNED_BYTE,
            null,
        );
        std.log.debug("Loading texture tiles...", .{});

        for (self.meta_data.value) |meta| {
            const img_file: [:0]const u8 = try std.fs.path.joinZ(self.alloc, &.{self.img_dir, meta.filename});
            defer self.alloc.free(img_file);
            zstbi.setFlipVerticallyOnLoad(true); // Images flipped by openGL
            var img = try zstbi.Image.loadFromFile(img_file, 0);
            defer img.deinit();

            var x_offset: u32 = 0;
            var y_offset: u32 = 0;
            try parseFilename(meta.filename, &x_offset, &y_offset);
            x_offset *= 1280; //FIXME
            y_offset *= 1235;
            gl.c.glTexSubImage2D(
                gl.c.GL_TEXTURE_2D,
                0,
                @intCast(x_offset),
                @intCast(y_offset),
                @intCast(img.width),
                @intCast(img.height),
                gl.c.GL_RGB,
                gl.c.GL_UNSIGNED_BYTE,
                img.data.ptr,
            );
        }
        gl.c.glGenerateMipmap(gl.c.GL_TEXTURE_2D);
    }
};
