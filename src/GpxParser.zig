const std = @import("std");
const XmlParser = @import("XmlParser.zig");
const Allocator = std.mem.Allocator;

const desctiptors: [3][]const u8 = .{
    "name",
    "ele",
    "time",
};

pub fn parse(alloc: Allocator, gpx_path: []const u8) !GpxData {
    var data = GpxData.create(alloc);
    
    try runParser(alloc, gpx_path, .{
        .ctx = &data,
        .startElement = startElement,
        .endElement = endElement,
        .charData = charData,
    });
    return data;
}

fn runParser(alloc: Allocator, gpx_path: []const u8, callbacks: XmlParser.Callbacks) !void {
    const f = try std.fs.cwd().openFile(gpx_path, .{});
    defer f.close();

    var buffered_reader = std.io.bufferedReader(f.reader());

    var parser = try XmlParser.init(alloc, callbacks);
    defer parser.deinit();

    while (true) {
        var buf: [4096]u8 = undefined;
        const read_data_len = try buffered_reader.read(&buf);
        if (read_data_len == 0) {
            try parser.finish();
            break;
        }

        try parser.feed(buf[0..read_data_len]);
    }
}

pub const Trkpt = struct {
    lat: f32,
    lon: f32,
    ele: ?f32 = null,
    time: ?[]const u8 = null,
};

const Trk = struct {
    name: ?[]const u8,
    trksegs: std.ArrayList(TrkSeg),
};

pub const TrkSeg = struct {
    start: usize,
    end: usize,
};

pub const GpxData = struct {
    trk: Trk,
    trkpts: std.ArrayList(Trkpt),
    in_tags: bool,
    data_buf: ?[]const u8,

    pub fn create(alloc: Allocator) GpxData {
        return .{
            .trk = .{
                .name = null,
                .trksegs = std.ArrayList(TrkSeg).init(alloc),
            },
            .trkpts = std.ArrayList(Trkpt).init(alloc),
            .in_tags = false,
            .data_buf = null,
        };
    }

    pub fn deinit(self: *GpxData) void {
        self.trk.trksegs.deinit();
        self.trkpts.deinit();
    }

    fn handleTrkpt(data: *GpxData, attrs: *XmlParser.XmlAttrIter) !void {
        var lat_opt: ?[]const u8 = null;
        var lon_opt: ?[]const u8 = null;

        while (attrs.next()) |attr| {
            if (std.mem.eql(u8, attr.key, "lat")) {
                lat_opt = attr.val;
            } else if (std.mem.eql(u8, attr.key, "lon")) {
                lon_opt = attr.val;
            } else {
                return error.InvalidAttr;
            }
        }

        const lat_s = lat_opt orelse return error.MissingLat;
        const lon_s = lon_opt orelse return error.MissingLon;
        const lat = try std.fmt.parseFloat(f32, lat_s);
        const lon = try std.fmt.parseFloat(f32, lon_s);
        data.trkpts.append(.{ .lat = lat, .lon = lon }) catch unreachable;
        data.trk.trksegs.items[data.trk.trksegs.items.len - 1].end += 1;
    }

    pub fn format(
        self: GpxData,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) @TypeOf(out_stream).Error!void {
        _ = options;
        _ = fmt;
        try out_stream.writeAll("Track: ");
        try std.fmt.format(out_stream, "{?s}\n", .{self.trk.name});
        try std.fmt.format(out_stream, "Number of points: {d}\n", .{self.trkpts.items.len});
        for (self.trk.trksegs.items) |seg| {
            try out_stream.writeAll("Begin Segment\n");
            for (seg.start..seg.end) |i| {
                try out_stream.writeAll("  ");
                try std.fmt.format(out_stream, "Lat: {d:.2}, Lon: {d:.2}\n", .{ self.trkpts.items[i].lat, self.trkpts.items[i].lon });
                if (self.trkpts.items[i].ele != null) {
                    try out_stream.writeAll("  ");
                    try std.fmt.format(out_stream, "Ele: {d:.2}\n", .{self.trkpts.items[i].ele.?});
                }
                if (self.trkpts.items[i].time != null) {
                    try out_stream.writeAll("  ");
                    try std.fmt.format(out_stream, "Time: {s}\n", .{self.trkpts.items[i].time.?});
                }
            }
            try out_stream.writeAll("End Segment\n");
        }
        try out_stream.writeAll("End Track\n");
    }
};

fn startElement(ctx: ?*anyopaque, name: []const u8, attrs: *XmlParser.XmlAttrIter) anyerror!void {
    const data: *GpxData = @ptrCast(@alignCast(ctx));

    if (std.mem.eql(u8, name, "trkseg")) {
        data.trk.trksegs.append(.{
            .start = data.trkpts.items.len,
            .end = data.trkpts.items.len,
        }) catch unreachable;
    } else if (std.mem.eql(u8, name, "trkpt")) {
        try data.handleTrkpt(attrs);
    }

    data.in_tags = false;
    for (desctiptors) |desc| {
        if (std.mem.eql(u8, name, desc)) {
            data.in_tags = true;
            break;
        }
    }
}

fn endElement(ctx: ?*anyopaque, name: []const u8) anyerror!void {
    const data: *GpxData = @ptrCast(@alignCast(ctx));

    if (!data.in_tags) {
        return;
    }
    if (data.trkpts.items.len == 0) {
        if (std.mem.eql(u8, name, "name")) {
            data.trk.name = data.data_buf;
        }
        return;
    }

    if (std.mem.eql(u8, name, "ele")) {
        data.in_tags = false;
        data.trkpts.items[data.trkpts.items.len - 1].ele = try std.fmt.parseFloat(f32, data.data_buf.?);
    } else if (std.mem.eql(u8, name, "time")) {
        data.in_tags = false;
        data.trkpts.items[data.trkpts.items.len - 1].time = data.data_buf;
    }
}

fn charData(ctx: ?*anyopaque, s: []const u8) anyerror!void {
    const data: *GpxData = @ptrCast(@alignCast(ctx));
    if (!data.in_tags) {
        return;
    }
    var is_empty = true;
    for (s) |c| {
        if (!std.ascii.isWhitespace(c)) {
            is_empty = false;
            break;
        }
    }
    if (!is_empty) {
        data.data_buf = s;
    } else {
        data.data_buf = null;
    }
}
