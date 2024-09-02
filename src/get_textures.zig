const std = @import("std");
const zstbi = @import("zstbi"); // For cropping copywrite marking
const Allocator = std.mem.Allocator;
const Client = std.http.Client;

// const Hash = std.crypto.hash.Sha1; // TODO For signing api requests

const secret_file = @embedFile("secret.json");

const Secret = struct {
    api_key: []const u8,
};

fn readSecret(alloc: Allocator) !std.json.Parsed(Secret) {
    return std.json.parseFromSlice(Secret, alloc, secret_file, .{});
}

const Point = struct {
    x: f32,
    y: f32,
};

const LatLon = struct {
    lat: f32,
    lon: f32,
};

const Bounds = struct {
    sw: LatLon,
    ne: LatLon,
};

const MetaData = struct {
    filename: [:0]const u8,
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
    output_dir_path: []const u8,
    alloc: Allocator,

    const jpg_quality = 80;

    pub fn init(alloc: Allocator, output_dir: []const u8) !ImgWriter {
        const dir = try std.fs.cwd().makeOpenPath(output_dir, .{ .iterate = true });
        var it = dir.iterate();
        while (try it.next()) |entry| {
            switch (entry.kind) {
                .file => {
                    if (std.mem.endsWith(u8, entry.name, ".png") or std.mem.endsWith(u8, entry.name, ".jpg")) {
                        try dir.deleteFile(entry.name);
                    }
                },
                else => {},
            }
        }

        return .{ .output_dir = dir, .output_dir_path = output_dir, .alloc = alloc };
    }

    pub fn deinit(self: ImgWriter) void {
        self.output_dir.close();
    }

    pub fn write(self: ImgWriter, filename: []const u8, img: []const u8) !void {
        const file = try self.output_dir.createFile(filename, .{});
        defer file.close();

        try file.writeAll(img);
    }

    pub fn imgFilenameFromTile(self: ImgWriter, col: usize, row: usize, format: []const u8) ![:0]const u8 {
        return std.fmt.allocPrintZ(self.alloc, "{d}_{d}.{s}", .{ col, row, format });
    }

    pub fn freeFilename(self: ImgWriter, filename: [:0]const u8) void {
        self.alloc.free(filename);
    }

    pub fn writeCropped(self: ImgWriter, filename: [:0]const u8, img: []const u8, crop_px: u32) !void {
        zstbi.init(self.alloc);
        defer zstbi.deinit();

        var image = try zstbi.Image.loadFromMemory(img, 0);
        defer zstbi.Image.deinit(&image);

        const new_height = image.height - crop_px;
        if (new_height <= 0) {
            return error.InvalidImageDimensions;
        }
        const cropped_size = image.width * new_height * image.num_components;

        image.data = image.data[0..cropped_size];
        image.height = new_height;

        const path = try std.fs.path.joinZ(self.alloc, &.{ self.output_dir_path, filename });
        defer self.alloc.free(path);

        if(std.mem.endsWith(u8, filename, ".png")) {
            try zstbi.Image.writeToFile(image, path, .png);
        } else if (std.mem.endsWith(u8, filename, ".jpg")) {
            try zstbi.Image.writeToFile(image, path, .{.jpg = .{ .quality = jpg_quality }});
        } else {
            return error.InvalidImageFormat;
        }
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
        defer secret.deinit();

        return .{
            .alloc = alloc,
            .client = c,
            .api_key = secret.value.api_key,
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
        const center_str = try std.fmt.bufPrint(&buf, "{d:.5},{d:.5}", .{ center.lat, center.lon });
        try url.appendSlice(center_str);
        try url.appendSlice("&zoom=");
        const zoom_str = try std.fmt.bufPrint(&buf, "{d}", .{zoom});
        try url.appendSlice(zoom_str);
        try url.appendSlice("&maptype=satellite&size=");
        const size = try std.fmt.bufPrint(&buf, "{d}x{d}", .{ img_width, img_height });
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
    const x = (lat_lon.lon + 180.0) * @as(f32, @floatFromInt(map_width)) / 360.0;
    const y = (1.0 - std.math.log(f32, std.math.e, std.math.tan(lat_lon.lat / std.math.deg_per_rad) + 1.0 / std.math.cos(lat_lon.lat / std.math.deg_per_rad)) / std.math.pi) * @as(f32, @floatFromInt(map_height)) / 2.0;

    return .{ .x = x, .y = y };
}

fn pointToLatLon(map_width: u32, map_height: u32, point: Point) LatLon {
    const lon = point.x / @as(f32, @floatFromInt(map_width)) * 360.0 - 180.0;
    const n = std.math.pi - 2.0 * std.math.pi * point.y / @as(f32, @floatFromInt(map_height));
    const lat = std.math.deg_per_rad * std.math.atan(0.5 * (std.math.exp(n) - std.math.exp(-n)));

    return .{ .lat = lat, .lon = lon };
}

fn getImageBounds(map_width: u32, map_height: u32, x_scale: f32, y_scale: f32, center: LatLon, crop_y_scale: ?f32) Bounds {
    const center_point = latLonToPoint(map_width, map_height, center);

    const sw_x = center_point.x - 1 / (2.0 * x_scale);
    var sw_y: f32 = undefined;
    if (crop_y_scale) |s| {
        sw_y = center_point.y + 1 / (2.0 * s);
    } else {
        sw_y = center_point.y + 1 / (2.0 * y_scale);
    }
    const sw = pointToLatLon(map_width, map_height, .{ .x = sw_x, .y = sw_y });

    const ne_x = center_point.x + 1 / (2.0 * x_scale);
    const ne_y = center_point.y - 1 / (2.0 * y_scale);
    const ne = pointToLatLon(map_width, map_height, .{ .x = ne_x, .y = ne_y });

    return .{ .sw = sw, .ne = ne };
}

fn getLatStep(map_width: u32, map_height: u32, y_scale: f32, center: LatLon) f32 {
    const center_point = latLonToPoint(map_width, map_height, center);
    
    const step_y = center_point.y - 1 / y_scale;
    const step = pointToLatLon(map_width, map_height, .{ .x = center_point.x, .y = step_y });

    return step.lat - center.lat;
}

fn sampleBounds(bounds: Bounds, zoom: u32, img_width: u32, img_height: u32, format: []const u8, crop: bool, api: *Api, img_writer: ImgWriter, meta_data_writer: MetaDataWriter) !void {
    const mercator_range = 256.0;
    const crop_px = 45; // crop 45px from the bottom (Google watermark)

    const scale = std.math.pow(f32, 2.0, @floatFromInt(zoom)); 
    const x_scale = scale / @as(f32, @floatFromInt(img_width));
    const y_scale = scale / @as(f32, @floatFromInt(img_height));
    const crop_step_y_scale: f32 = blk: { 
        if (crop) {
            // Div 45 by 2 as scale is 2
            break :blk (scale / (@as(f32, @floatFromInt(img_height)) - @as(f32, @floatFromInt(crop_px)) / 2)); 
        } else {
            break :blk y_scale;
        }
    };
    const crop_bounds_y_scale: f32 = blk: {
        if (crop) {
            break :blk (scale / (@as(f32, @floatFromInt(img_height)) - @as(f32, @floatFromInt(crop_px)))); 
        } else {
            break :blk y_scale;
        }
    };
    // start SW
    const start: LatLon = .{ .lat = bounds.sw.lat, .lon = bounds.sw.lon };
    const start_bounds = getImageBounds(mercator_range, mercator_range, x_scale, y_scale, start, crop_bounds_y_scale);
    const lon_step = start_bounds.ne.lon - start_bounds.sw.lon;
    var lat_step = getLatStep(mercator_range, mercator_range, crop_step_y_scale, start);
    var final_bounds = start_bounds;

    var row: usize = 0;
    var lat: f32 = start.lat;
    while (lat <= bounds.ne.lat + lat_step / 2) {
        var col: usize = 0;
        var lon: f32 = start.lon;
        while (lon <= bounds.ne.lon + lon_step / 2) {
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

            const img_bounds = getImageBounds(mercator_range, mercator_range, x_scale, y_scale, center, crop_bounds_y_scale);
            if(bounds.ne.lat > final_bounds.ne.lat) {
                final_bounds.ne.lat = img_bounds.ne.lat;
            }
            if(bounds.ne.lon > final_bounds.ne.lon) {
                final_bounds.ne.lon = img_bounds.ne.lon;
            }
            const img_filename = try img_writer.imgFilenameFromTile(col, row, format);
            defer img_writer.freeFilename(img_filename);
            if (crop) {
                try img_writer.writeCropped(img_filename, img, crop_px); // crop 45px from the bottom
            } else {
                try img_writer.write(img_filename, img);
            }

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
        lat_step = getLatStep(mercator_range, mercator_range, crop_step_y_scale, .{ .lat = lat, .lon = lon });
        lat += lat_step;
    }
    std.log.info("Final bounds: ({d:.3} S, {d:.3} W) -> ({d:.3} N, {d:.3} E)", .{ final_bounds.sw.lat, final_bounds.sw.lon, final_bounds.ne.lat, final_bounds.ne.lon });
}



const Args = struct {
    output_dir: []const u8 = undefined,
    bounds: Bounds = undefined,
    zoom: u32 = undefined,
    img_width: u32 = 640,
    img_height: u32 = 640,
    img_format: []const u8 = "png",
    crop: bool = true,
    it: std.process.ArgIterator = undefined,

    const Option = enum {
        @"--output-dir",
        @"--bounds",
        @"--zoom",
        @"--img-width",
        @"--img-height",
        @"--img-format",
        @"-no-crop",
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
        var crop_opt: ?bool = null;

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
                .@"-no-crop" => crop_opt = false,
            }
        }

        ret.output_dir = output_dir_opt orelse return error.MissingOutputDir;

        if (bounds_opt) |b| {
            ret.bounds = try parseBounds(b);
        } else {
            return error.MissingBounds;
        }

        if (zoom_opt) |z| {
            const parsed = try std.fmt.parseInt(u32, z, 10);
            ret.zoom = parsed;
            if (ret.zoom > 21) {
                @panic("Zoom level must be between 0 and 21!");
            }
        } else {
            return error.MissingZoom;
        }

        if (img_width_opt) |w| {
            const parsed = try std.fmt.parseInt(u32, w, 10);
            ret.img_width = parsed;
            if(ret.img_width > 640) {
                @panic("Image width must be less than or equal to 640!");
            }
        }

        if (img_height_opt) |h| {
            const parsed = try std.fmt.parseInt(u32, h, 10);
            ret.img_height = parsed;
            if(ret.img_height > 640) {
                @panic("Image height must be less than or equal to 640!");
            }
        }

        if (img_format_opt) |f| {
            ret.img_format = f;
            if(!std.mem.eql(u8, f, "png") and !std.mem.eql(u8, f, "jpg")) {
                @panic("Image format must be either png or jpg!");
            }
        }

        ret.crop = crop_opt orelse true;

        ret.it = it;

        return ret;
    }

    fn parseBounds(bounds: []const u8) !Bounds {
        var it = std.mem.tokenizeAny(u8, bounds, " ,");

        var lat_lon: [4]f32 = undefined;
        var i: usize = 0;
        while (it.next()) |token| {
            const parsed = try std.fmt.parseFloat(f32, token);
            lat_lon[i] = parsed;
            i += 1;
        }

        if (i != 4) {
            return error.InvalidBounds;
        }

        return .{
            .sw = .{ .lat = lat_lon[0], .lon = lat_lon[1] },
            .ne = .{ .lat = lat_lon[2], .lon = lat_lon[3] },
        };
    }
};

pub fn main() !void {
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

    try sampleBounds(args.bounds, args.zoom, args.img_width, args.img_height, args.img_format, args.crop, &api, img_writer, meta_data_writer);
}
