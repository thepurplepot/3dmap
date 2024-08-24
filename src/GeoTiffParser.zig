const std = @import("std");
const Allocator = std.mem.Allocator;
const gdal = @cImport({
    @cInclude("gdal.h");
});

const Inner = struct {
    dataset: gdal.GDALDatasetH,
    adfGeoTransform: [6]f64,
    err: ?anyerror = null,
};

pub const Position = struct {
    lon: f64,
    lat: f64,
};

pub const ElevationMap = struct {
    positions: []Position,
    elevations: []f64,
    stride: usize,
};

alloc: Allocator,
inner: *Inner,

const GeoTiffParser = @This();

const Error = error{
    OpenFileError,
    ParseError,
} || Allocator.Error;

pub fn init(alloc: Allocator, filename: []const u8) Error!GeoTiffParser {
    gdal.GDALAllRegister();

    const dataset = gdal.GDALOpen(@ptrCast(filename.ptr), gdal.GA_ReadOnly);
    if(dataset == null) {
        return Error.OpenFileError;
    }

    var adfGeoTransform: [6]f64 = undefined;
    if (gdal.GDALGetGeoTransform(dataset, &adfGeoTransform) != gdal.CE_None) {
        return Error.ParseError;
    }

    const min_lon = adfGeoTransform[0];
    const max_lon = adfGeoTransform[0] + adfGeoTransform[1] * @as(f64, @floatFromInt(gdal.GDALGetRasterXSize(dataset)));
    const max_lat = adfGeoTransform[3];
    const min_lat = adfGeoTransform[3] + adfGeoTransform[5] * @as(f64, @floatFromInt(gdal.GDALGetRasterYSize(dataset)));

    std.log.info("GeoTiff bounds: ({d:.4}, {d:.4}) -> ({d:.4},{d:.4})", .{min_lon, min_lat, max_lon, max_lat});

    const inner = try alloc.create(Inner);
    errdefer alloc.destroy(inner);
    inner.* = .{
        .dataset = dataset,
        .adfGeoTransform = adfGeoTransform,
    };
    
    return .{
        .alloc = alloc,
        .inner = inner,
    };
}

pub fn deinit(self: *GeoTiffParser) void {
    self.alloc.destroy(self.inner);
}

pub fn getElevation(self: *GeoTiffParser, lat: f64, lon: f64) Error!f64 {
    const x: c_int = @intFromFloat((lon - self.inner.adfGeoTransform[0]) / self.inner.adfGeoTransform[1]);
    const y: c_int = @intFromFloat((lat - self.inner.adfGeoTransform[3]) / self.inner.adfGeoTransform[5]);

    const band = gdal.GDALGetRasterBand(self.inner.dataset, 1);
    var elevation: f64 = undefined;
    if (gdal.GDALRasterIO(band, gdal.GF_Read, x, y, 1, 1, &elevation, 1, 1, gdal.GDT_Float64, 0, 0) != gdal.CE_None) {
        return Error.ParseError;
    }
    return elevation;
}

pub fn sampleGrid(self: *GeoTiffParser, lat: f64, lon: f64, width: c_int, height: c_int) Error![]f64 {
    const x: c_int = @intFromFloat((lon - self.inner.adfGeoTransform[0]) / self.inner.adfGeoTransform[1]);
    const y: c_int = @intFromFloat((lat - self.inner.adfGeoTransform[3]) / self.inner.adfGeoTransform[5]);

    const band = gdal.GDALGetRasterBand(self.inner.dataset, 1);
    const elevations = try self.alloc.alloc(f64, @intCast(width * height));
    if (gdal.GDALRasterIO(band, gdal.GF_Read, x, y, width, height, elevations.ptr, width, height, gdal.GDT_Float64, 0, 0) != gdal.CE_None) {
        return Error.ParseError;
    }
    return elevations;
}

pub fn getGridPositions(self: *GeoTiffParser, lat: f64, lon: f64, width: c_int, height: c_int) Error![]Position {
    const positions = try self.alloc.alloc(Position, @intCast(width * height));
    for (positions, 0..) |*pos, i| {
        const x = i % @as(usize, @intCast(width));
        const y = i / @as(usize, @intCast(width));
        pos.* = .{
            .lon = lon + @as(f64, @floatFromInt(x)) * self.inner.adfGeoTransform[1],
            .lat = lat + @as(f64, @floatFromInt(y)) * self.inner.adfGeoTransform[5],
        };
    }
    return positions;
}

pub fn fullSample(self: *GeoTiffParser) !ElevationMap {
    const width = gdal.GDALGetRasterXSize(self.inner.dataset);
    const height = gdal.GDALGetRasterYSize(self.inner.dataset);
    const elevations = try self.sampleGrid(self.inner.adfGeoTransform[3], self.inner.adfGeoTransform[0], width, height);
    const positions = try self.getGridPositions(self.inner.adfGeoTransform[3], self.inner.adfGeoTransform[0], width, height);
    return .{
        .positions = positions,
        .elevations = elevations,
        .stride = @intCast(width),
    };
}

const testing = std.testing;
test "fullSample" {
    const alloc = testing.allocator;
    const data = "res/geo.tif";

    var parser = try GeoTiffParser.init(alloc, data);
    defer parser.deinit();

    const map = try parser.fullSample();
    defer alloc.free(map.elevations);
    defer alloc.free(map.positions);

    std.debug.print("Stride: {d}\n", .{map.stride});

    // Test grid sample is giving correct elevations
    for(map.positions, 0..) |pos, i| {
        if(i > 10) break;
        const ele = map.elevations[i];
        std.debug.print("Position: ({d:.5}, {d:.5}) Elevation: {d} m\n", .{pos.lon, pos.lat, ele});
        const ele2 = try parser.getElevation(pos.lat, pos.lon);
        std.debug.print("   Elevation: {d} m\n", .{ele2});
        try testing.expectEqual(ele2, ele);
    }
}