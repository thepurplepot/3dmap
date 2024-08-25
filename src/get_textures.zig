const std = @import("std");
const Allocator = std.mem.Allocator;
const Client = std.http.Client;

//TODO request signing!
// const Hash = std.crypto.hash.Sha1;

const secret_file = @embedFile("secret.json");

const Secret = struct {
    api_key: []const u8,
};

fn readSecret(alloc: Allocator) !Secret {
    const parsed =  try std.json.parseFromSlice(Secret, alloc, secret_file, .{});
    defer parsed.deinit();

    return parsed.value;
}

const LatLon = struct {
    lat: f64,
    lon: f64,
};

const Point = struct {
    x: f64,
    y: f64,
};

const Bounds = struct {
    min: LatLon, // SW
    max: LatLon, // NE
};

const MetaData = struct {
    filename: []u8,
    center: LatLon,
    bounds: Bounds,
};

const MetaDataWriter = struct {
    file: std.fs.File,

    pub fn open(output_dir: []const u8, filename: []const u8) !MetaDataWriter {
        const dir = try std.fs.cwd().makeOpenPath(output_dir, .{});
        const file = try dir.createFile(filename, .{});

        _ = try file.writer().write("[");

        return .{ .file = file };
    }

    pub fn close(self: *MetaDataWriter) void {
        self.file.seekBy(-1) catch unreachable; // remove final ,
        _ = self.file.writer().write("]") catch unreachable;
        self.file.close();
    }

    pub fn write(self: MetaDataWriter, meta_data: MetaData) !void {
        try std.json.stringify(meta_data, .{}, self.file.writer());
        _ = try self.file.writer().write(",");
    }
};

const ImgWriter = struct {
    output_dir: std.fs.Dir,
    alloc: Allocator,

    pub fn init(alloc: Allocator, output_dir: []const u8) !ImgWriter {
        const dir = try std.fs.cwd().makeOpenPath(output_dir, .{.iterate = true});
        var it = dir.iterate();
        while (try it.next()) |entry| {
            switch(entry.kind) {
                .file => {
                    if (std.mem.endsWith(u8, entry.name, ".png") or std.mem.endsWith(u8, entry.name, ".jpg")) {
                        try dir.deleteFile(entry.name);
                    }
                },
                else => {},
            }
        }

        return .{ .output_dir = dir, .alloc = alloc };
    }

    pub fn write(self: ImgWriter, filename: []const u8, img: []const u8) !void {
        const file = try self.output_dir.createFile(filename, .{});
        defer file.close();

        try file.writeAll(img);
    }

    pub fn imgFilenameFromTile(self: ImgWriter, col: usize, row: usize, format: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.alloc, "{d}_{d}.{s}", .{col, row, format});
    }

    pub fn freeFilename(self: ImgWriter, filename: []u8) void {
        self.alloc.free(filename);
    }
};


const Api = struct {
    const Self = @This();

    const api_url = "https://maps.googleapis.com/maps/api/staticmap";

    pub const ReqParams = struct {
        center: LatLon,
        zoom: u32,
        img_width: u32,
        img_height: u32,
        scale: ?u32 = null, // *1* or 2
        format: ?[]const u8 = null, // *png* or jpg
    };

    alloc: Allocator,
    client: Client,
    api_key: []const u8,

    pub fn create(alloc: Allocator) Self {
        const c = Client{ .allocator = alloc };
        const secret = readSecret(alloc) catch @panic("Failed to read secret api-key!");
        return .{
            .alloc = alloc,
            .client = c,
            .api_key = secret.api_key,
        };
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
    }

    pub fn get(self: *Self, params: ReqParams) ![]const u8 {
        var response = std.ArrayList(u8).init(self.alloc);
        defer response.deinit();

        const url = try self.buildUrl(params);
        defer self.alloc.free(url);

        const res = try self.client.fetch(.{ .location = .{ .url = url }, .response_storage = .{ .dynamic = &response } });
        if (res.status.class() != .success) {
            @panic("API request failed!");
        }

        return response.toOwnedSlice();
    }

    fn buildUrl(self: Self, params: ReqParams) ![]const u8 {
        const center = params.center;
        const zoom = params.zoom;
        const img_width = params.img_width;
        const img_height = params.img_height;
        const format = params.format;
        const scale = params.scale;

        var url = std.ArrayList(u8).init(self.alloc);
        var buf: [1028]u8 = undefined;

        try url.appendSlice(api_url);
        try url.appendSlice("?center=");
        const center_str = try std.fmt.bufPrint(&buf, "{d:.5},{d:.5}", .{center.lat, center.lon});
        try url.appendSlice(center_str);
        try url.appendSlice("&zoom=");
        const zoom_str = try std.fmt.bufPrint(&buf, "{d}", .{zoom});
        try url.appendSlice(zoom_str);
        try url.appendSlice("&maptype=satellite&size=");
        const size = try std.fmt.bufPrint(&buf, "{d}x{d}", .{img_width, img_height});
        try url.appendSlice(size);
        try url.appendSlice("&format=");
        if (format) |f| {
            try url.appendSlice(f);
        }
        if (scale) |s| {
            try url.appendSlice("&scale=");
            const scale_str = try std.fmt.bufPrint(&buf, "{d}", .{s});
            try url.appendSlice(scale_str);
        }
        try url.appendSlice("&key=");
        try url.appendSlice(self.api_key);

        return url.toOwnedSlice();
    }
};

fn latLonToPoint(map_width: u32, map_height: u32, lat_lon: LatLon) Point {
    const x = (lat_lon.lon + 180.0) * @as(f64, @floatFromInt(map_width)) / 360.0;
    const y = (1.0 - std.math.log(f64, std.math.e, std.math.tan(lat_lon.lat / std.math.deg_per_rad) + 1.0 / std.math.cos(lat_lon.lat / std.math.deg_per_rad)) / std.math.pi) * @as(f64, @floatFromInt(map_height)) / 2.0;

    return .{ .x = x, .y = y };
}

fn pointToLatLon(map_width: u32, map_height: u32, point: Point) LatLon {
    const lon = point.x / @as(f64, @floatFromInt(map_width)) * 360.0 - 180.0;
    const n = std.math.pi - 2.0 * std.math.pi * point.y / @as(f64, @floatFromInt(map_height));
    const lat = std.math.deg_per_rad * std.math.atan(0.5 * (std.math.exp(n) - std.math.exp(-n)));

    return .{ .lat = lat, .lon = lon };
}

fn getImageBounds(map_width: u32, map_height: u32, x_scale: f64, y_scale: f64, center: LatLon) Bounds {
    const center_point = latLonToPoint(map_width, map_height, center);

    const sw_x = center_point.x - @as(f64, @floatFromInt(map_width)) / (2.0 * x_scale);
    const sw_y = center_point.y + @as(f64, @floatFromInt(map_height)) / (2.0 * y_scale);
    //TODO remove 45px from the bottom
    const sw = pointToLatLon(map_width, map_height, .{ .x = sw_x, .y = sw_y });

    const ne_x = center_point.x + @as(f64, @floatFromInt(map_width)) / (2.0 * x_scale);
    const ne_y = center_point.y - @as(f64, @floatFromInt(map_height)) / (2.0 * y_scale);
    const ne = pointToLatLon(map_width, map_height, .{ .x = ne_x, .y = ne_y });

    return .{ .min = sw, .max = ne };
}

fn getLatStep(map_width: u32, map_height: u32, y_scale: f64, center: LatLon) f64 {
    const center_point = latLonToPoint(map_width, map_height, center);

    const step_y = center_point.y - @as(f64, @floatFromInt(map_height)) / y_scale;
    const step = pointToLatLon(map_width, map_height, .{ .x = center_point.x, .y = step_y });

    return center.lat - step.lat;
}

fn sampleBounds(bounds: Bounds, zoom: u32, img_width: u32, img_height: u32, format: []const u8, api: *Api, img_writer: ImgWriter, meta_data_writer: MetaDataWriter) !void {
    const mercator_range = 256.0;

    const x_scale = std.math.pow(f64, 2.0, @floatFromInt(zoom)) * mercator_range / @as(f64, @floatFromInt(img_width));
    const y_scale = std.math.pow(f64, 2.0, @floatFromInt(zoom)) * mercator_range / @as(f64, @floatFromInt(img_height));
    // start SW
    const start: LatLon = .{ .lat = bounds.min.lat, .lon = bounds.min.lon };
    const start_bounds = getImageBounds(mercator_range, mercator_range, x_scale, y_scale, start);
    const lon_step = start_bounds.max.lon - start_bounds.min.lon;

    var row: usize = 0;
    var lat: f64 = start.lat;
    while(lat <= bounds.max.lat) {
        var col: usize = 0;
        var lon: f64 = start.lon;
        while(lon <= bounds.max.lon) {
            const center: LatLon = .{ .lat = lat, .lon = lon };

            const img = try api.get(.{
                .center = center,
                .zoom = zoom,
                .img_width = img_width,
                .img_height = img_height,
                .scale = 2,
                .format = format,
            });
            defer api.alloc.free(img);

            const img_bounds = getImageBounds(mercator_range, mercator_range, x_scale, y_scale, center);
            const img_filename = try img_writer.imgFilenameFromTile(col, row, format);
            defer img_writer.freeFilename(img_filename);
            try img_writer.write(img_filename, img);
            //TODO need to remove 45 px from the bottom of the image! and redo the lat step
            //use stbimg
            const meta_data = MetaData{
                .filename = img_filename,
                .center = center,
                .bounds = img_bounds,
            };
            try meta_data_writer.write(meta_data);

            col += 1;
            lon += lon_step; // step right E
        }
        row += 1;
        // step up N
        lat -= getLatStep(mercator_range, mercator_range, y_scale, .{ .lat = lat, .lon = lon });
    }
}

const Args = struct {
    output_dir: []const u8 = undefined,
    bounds: Bounds = undefined,
    zoom: u32 = undefined,
    img_width: u32 = 640,
    img_height: u32 = 640,
    img_format: []const u8 = "png",
    it: std.process.ArgIterator = undefined,

    const Option = enum {
        @"--output-dir",
        @"--bounds",
        @"--zoom",
        @"--img-width",
        @"--img-height",
        @"--img-format",
    };

    fn deinit(self: *Args) void {
        self.it.deinit();
    }

    fn parse(alloc: Allocator) !Args {
        var it = try std.process.ArgIterator.initWithAllocator(alloc);
        _ = it.next();

        var ret = Args{};

        var output_dir_opt: ?[]const u8 = null;
        var bounds_opt: ?[]const u8 = null;
        var zoom_opt: ?[]const u8 = null;
        var img_width_opt: ?[]const u8 = null;
        var img_height_opt: ?[]const u8 = null;
        var img_format_opt: ?[]const u8 = null;

        while (it.next()) |arg| {
            const opt = std.meta.stringToEnum(Option, arg) orelse {
                std.debug.print("{s}", .{arg});
                return error.InvalidOption;
            };

            switch (opt) {
                .@"--output-dir" => output_dir_opt = it.next(),
                .@"--bounds" => bounds_opt = it.next(),
                .@"--zoom" => zoom_opt = it.next(),
                .@"--img-width" => img_width_opt = it.next(),
                .@"--img-height" => img_height_opt = it.next(),
                .@"--img-format" => img_format_opt = it.next(),
            }
        }

        ret.output_dir = output_dir_opt orelse return error.MissingOutputDir;

        if(bounds_opt) |b| {
            ret.bounds = try parseBounds(b);
        } else {
            return error.MissingBounds;
        }

        if(zoom_opt) |z| {
            const parsed = try std.fmt.parseInt(u32, z, 10);
            ret.zoom = parsed;
        } else {
            return error.MissingZoom;
        }

        if(img_width_opt) |w| {
            const parsed = try std.fmt.parseInt(u32, w, 10);
            ret.img_width = parsed;
        }

        if(img_height_opt) |h| {
            const parsed = try std.fmt.parseInt(u32, h, 10);
            ret.img_height = parsed;
        }

        if(img_format_opt) |f| {
            ret.img_format = f;
        }

        ret.it = it;

        return ret;
    }

    fn parseBounds(bounds: []const u8) !Bounds {
        var it = std.mem.tokenizeAny(u8, bounds, " ,");
        
        var lat_lon: [4]f64 = undefined;
        var i: usize = 0;
        while (it.next()) |token| {
            const parsed = try std.fmt.parseFloat(f64, token);
            lat_lon[i] = parsed;
            i += 1;
        }

        if (i != 4) {
            return error.InvalidBounds;
        }

        return .{
            .min = .{ .lat = lat_lon[0], .lon = lat_lon[1] },
            .max = .{ .lat = lat_lon[2], .lon = lat_lon[3] },
        };
    }
};

pub fn main () !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var args = try Args.parse(alloc);
    defer args.deinit();

    var api = Api.create(alloc);
    defer api.deinit();

    var meta_data_writer = try MetaDataWriter.open(args.output_dir, "meta_data.json");
    defer meta_data_writer.close();
    
    const img_writer = try ImgWriter.init(alloc, args.output_dir);

    try sampleBounds(args.bounds, args.zoom, args.img_width, args.img_height, args.img_format, &api, img_writer, meta_data_writer);
}