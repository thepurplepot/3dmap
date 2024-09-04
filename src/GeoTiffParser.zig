const std = @import("std");
const utils = @import("utils.zig");
const LatLon = utils.LatLon;
const Bounds = utils.Bounds;
const Allocator = std.mem.Allocator;
const gdal = @cImport({
    @cInclude("gdal.h");
});

const Inner = struct {
    dataset: gdal.GDALDatasetH,
    adfGeoTransform: [6]f64,
    err: ?anyerror = null,
    bounds: Bounds,
};

inner: *Inner,

const GeoTiffParser = @This();

const Error = error{
    OpenFileError,
    ParseError,
} || Allocator.Error;

pub fn create(alloc: Allocator, filename: []const u8) Error!GeoTiffParser {
    gdal.GDALAllRegister();

    const dataset = gdal.GDALOpen(@ptrCast(filename.ptr), gdal.GA_ReadOnly);
    if(dataset == null) {
        return Error.OpenFileError;
    }

    var adfGeoTransform: [6]f64 = undefined;
    if (gdal.GDALGetGeoTransform(dataset, &adfGeoTransform) != gdal.CE_None) {
        return Error.ParseError;
    }

    const min_lon = @as(f32, @floatCast(adfGeoTransform[0]));
    const max_lon = @as(f32, @floatCast(adfGeoTransform[0])) + @as(f32, @floatCast(adfGeoTransform[1])) * @as(f32, @floatFromInt(gdal.GDALGetRasterXSize(dataset)));
    const max_lat = @as(f32, @floatCast(adfGeoTransform[3]));
    const min_lat = @as(f32, @floatCast(adfGeoTransform[3])) + @as(f32, @floatCast(adfGeoTransform[5])) * @as(f32, @floatFromInt(gdal.GDALGetRasterYSize(dataset)));

    std.log.info("GeoTiff bounds: ({d:.4} W, {d:.4} S) -> ({d:.4} E, {d:.4} N)", .{min_lon, min_lat, max_lon, max_lat});

    const inner = try alloc.create(Inner);
    inner.* = .{
        .dataset = dataset,
        .adfGeoTransform = adfGeoTransform,
        .bounds = .{
            .sw = .{.lon = min_lon, .lat = min_lat},
            .ne = .{.lon = max_lon, .lat = max_lat},
        },
    };
    
    return .{
        .inner = inner,
    };
}

pub fn deinit(self: *GeoTiffParser, alloc: Allocator) void {
    alloc.destroy(self.inner);
}

pub fn getElevation(self: *GeoTiffParser, point: LatLon) Error!f32 {
    const x: c_int = @intFromFloat((@as(f64, @floatCast(point.lon)) - self.inner.adfGeoTransform[0]) / self.inner.adfGeoTransform[1]);
    const y: c_int = @intFromFloat((@as(f64, @floatCast(point.lat)) - self.inner.adfGeoTransform[3]) / self.inner.adfGeoTransform[5]);

    const band = gdal.GDALGetRasterBand(self.inner.dataset, 1);
    var elevation: f32 = undefined;
    if (gdal.GDALRasterIO(band, gdal.GF_Read, x, y, 1, 1, &elevation, 1, 1, gdal.GDT_Float32, 0, 0) != gdal.CE_None) {
        return Error.ParseError;
    }
    return elevation;
}

pub fn getWidthAndHeight(self: *GeoTiffParser) struct {
    width: usize,
    height: usize,
} {
    return .{ 
        .width = @intCast(gdal.GDALGetRasterXSize(self.inner.dataset)), 
        .height = @intCast(gdal.GDALGetRasterYSize(self.inner.dataset))
    };
}

//Samples a grid starting NW corner, indexed longitude major
pub fn sampleGrid(self: *GeoTiffParser, alloc: Allocator, bounds: Bounds, width: *usize, height: *usize) Error![]f32 {
    const sw_x: c_int = @intFromFloat((@as(f64, @floatCast(bounds.sw.lon)) - self.inner.adfGeoTransform[0]) / self.inner.adfGeoTransform[1]);
    const sw_y: c_int = @intFromFloat((@as(f64, @floatCast(bounds.sw.lat)) - self.inner.adfGeoTransform[3]) / self.inner.adfGeoTransform[5]);
    const ne_x: c_int = @intFromFloat((@as(f64, @floatCast(bounds.ne.lon)) - self.inner.adfGeoTransform[0]) / self.inner.adfGeoTransform[1]);
    const ne_y: c_int = @intFromFloat((@as(f64, @floatCast(bounds.ne.lat)) - self.inner.adfGeoTransform[3]) / self.inner.adfGeoTransform[5]);
    width.* = @intCast(@abs(ne_x - sw_x));
    height.* = @intCast(@abs(ne_y - sw_y));
    
    const band = gdal.GDALGetRasterBand(self.inner.dataset, 1);
    const elevations = try alloc.alloc(f32, width.* * height.*);
    if (gdal.GDALRasterIO(band, gdal.GF_Read, sw_x, ne_y, @intCast(width.*), @intCast(height.*), elevations.ptr, @intCast(width.*), @intCast(height.*), gdal.GDT_Float32, 0, 0) != gdal.CE_None) {
        return Error.ParseError;
    }
    return elevations;
}