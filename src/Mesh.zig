const std = @import("std");
const Allocator = std.mem.Allocator;
const gl = @import("opengl_bindings.zig");
const GeoTiffParser = @import("GeoTiffParser.zig");

const Position = GeoTiffParser.Position;

const Vertex = struct {
    position: [3]f32,
    normal: [3]f32
    // texCoords: [2]f32,
};

const Texture = struct {
    id: u32,
    type: []const u8,
};

const Error = error{
    OpenGLError,
} || Allocator.Error;

vertices: []Vertex,
indices: []u32,
textures: []Texture,
vao: u32,
vbo: u32,
ebo: u32,
model: [16]f32,

const Self = @This();

pub const PositionsMetaData = struct {
    min_lon: f64,
    max_lon: f64,
    min_lat: f64,
    max_lat: f64,
};

fn findMinMaxPositions(positions: []Position) PositionsMetaData {
    var ret = PositionsMetaData{
        .min_lon = std.math.floatMax(f64),
        .max_lon = std.math.floatMin(f64),
        .min_lat = std.math.floatMax(f64),
        .max_lat = std.math.floatMin(f64),
    };
    for (positions) |position| {
        if (position.lon < ret.min_lon) {
            ret.min_lon = position.lon;
        }
        if (position.lon > ret.max_lon) {
            ret.max_lon = position.lon;
        }
        if (position.lat < ret.min_lat) {
            ret.min_lat = position.lat;
        }
        if (position.lat > ret.max_lat) {
            ret.max_lat = position.lat;
        }
    }
    return ret;
}

const PositionM = struct {
    x: f64,
    y: f64,
};
//Top left of bounds is (0, 0) m
fn positionToMSpace (position: Position, bounds: PositionsMetaData) PositionM {
    const lon_diff = position.lon - bounds.min_lon;
    const lat_diff = position.lat - bounds.min_lat; //TODO check this is the right reference point

    // Convert longitude and latitude differences to meters
    const earth_radius = 6371000.0;
    const x = lon_diff * (std.math.cos(bounds.min_lat * std.math.pi / 180.0) * std.math.pi / 180.0) * earth_radius;
    const y = lat_diff * (std.math.pi / 180.0) * earth_radius;

    return .{
        .x = x,
        .y = y,
    };
}

fn positionWithinBounds(position: Position, bounds: PositionsMetaData) bool {
    return position.lon >= bounds.min_lon and position.lon <= bounds.max_lon and position.lat >= bounds.min_lat and position.lat <= bounds.max_lat;
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
        scale, 0.0, 0.0, 0.0,
        0.0, scale, 0.0, 0.0,
        0.0, 0.0, scale_z, 0.0,
        -translate_x, -translate_y, 0.0, 1.0,
    };
}

//FIXME ugly
pub fn updateElevationScale(self: *Self, elevation_scale: f32) void {
    self.model[10] = self.model[0]*elevation_scale;
}

pub fn meshFromElevations(alloc: Allocator, bounds: PositionsMetaData, elevations: []f64, positions: []Position) Error!Self {

    const input_bounds = findMinMaxPositions(positions);
    std.debug.assert(bounds.min_lon >= input_bounds.min_lon);
    std.debug.assert(bounds.max_lon <= input_bounds.max_lon);
    std.debug.assert(bounds.min_lat >= input_bounds.min_lat);
    std.debug.assert(bounds.max_lat <= input_bounds.max_lat);

    var vertices = std.ArrayList(Vertex).init(alloc);

    var width: usize = 0;
    var max_elevation: f32 = 0.0;
    var max_x: f32 = 0.0;
    var max_y: f32 = 0.0;
    var skiped_last = false;
    var flag = false;
    for(positions, 0..) |position, i| {
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

        const x: f32 = @floatCast(m_position.x);
        if (x > max_x) {
            max_x = x;
        }
        const y: f32 = @floatCast(m_position.y);
        if (y > max_y) {
            max_y = y;
        }
        const z: f32 = @floatCast(elevations[i]);
        if(z > max_elevation) {
            max_elevation = z;
        }
        const vertex = Vertex{
            .position = [_]f32{x, y, z},
            .normal = [_]f32{0.0, 0.0, 0.0}, 
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
    for(0..height-1) |y| {
        for(0..width-1) |x| {
            const i: u32 = @intCast(y * width + x);
            indices[count] = i;
            indices[count+1] = i + 1;
            indices[count+2] = i + @as(u32, @intCast(width));

            indices[count+3] = i + 1;
            indices[count+4] = i + @as(u32, @intCast(width)) + 1;
            indices[count+5] = i + @as(u32, @intCast(width));
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

        const edge1 = [_]f32{v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2]};
        const edge2 = [_]f32{v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2]};
        const normal = [_]f32{
            edge1[1] * edge2[2] - edge1[2] * edge2[1],
            edge1[2] * edge2[0] - edge1[0] * edge2[2],
            edge1[0] * edge2[1] - edge1[1] * edge2[0],
        };

        for ([_]u32{@"i0", @"i1", @"i2"}) |index| {
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

    const textures = try alloc.alloc(Texture, 1); //TODO
    const model = createModelMatrix(max_x, max_y, 2.0, 2.0, 1.0);

    return init(try vertices.toOwnedSlice(), indices, textures, model);
}

pub fn testMesh() !Self {
    var vertices = [_]Vertex{
        Vertex{ .position = [_]f32{ -0.5, -0.5, 0.0 } },
        Vertex{ .position = [_]f32{ 0, 0.5, 0.0 } },
        Vertex{ .position = [_]f32{ 0.5, -0.5, 0.0 } },
        Vertex{ .position = [_]f32{ 0.5, 0.5, 1.0 } },
        Vertex{ .position = [_]f32{ 0.5, -0.5, 0.0 } },
        Vertex{ .position = [_]f32{ 0, 0.5, 0.0 } },
    };
    var indices = [_]u32{ 0, 1, 3, 1, 2, 3 };
    var textures = [_]Texture{Texture{ .id = 0, .type = "texture_diffuse" }};

    return init(&vertices, &indices, &textures);
}

pub fn init(vertices: []Vertex, indices: []u32, textures: []Texture, model: [16]f32) !Self {
    var mesh = Self{
        .vertices = vertices,
        .indices = indices,
        .textures = textures,
        .vao = 0,
        .vbo = 0,
        .ebo = 0,
        .model = model,
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
    alloc.free(self.textures);
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
    // // vertex texture coords
    // gl.glEnableVertexAttribArray(2);
    // gl.glVertexAttribPointer(2, 2, gl.c.GL_FLOAT, false, @sizeOf(Vertex), 6 * @sizeOf(f32));

    gl.glBindVertexArray(0);
}

pub fn draw(self: Self, program: u32) void {
    gl.glUseProgram(program);

    const objectColorLocation = gl.glGetUniformLoc(program, "objectColor", 11);
    gl.glUniform3f(objectColorLocation, 0.5, 0.5, 0.31); // Example color

    const modelLoc = gl.glGetUniformLoc(program, "model", 5);
    gl.c.glUniformMatrix4fv(@bitCast(modelLoc), 1, gl.c.GL_FALSE, &self.model);

    // draw mesh
    gl.glBindVertexArray(self.vao);
    //gl.glDrawArrays(gl.c.GL_TRIANGLES, 0, @intCast(self.vertices.len));
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
