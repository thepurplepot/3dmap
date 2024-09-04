const std = @import("std");

pub const LatLon = struct {
    lon: f32,
    lat: f32,
};

const Point = struct {
    x: f32,
    y: f32,
};

pub const Bounds = struct {
    sw: LatLon,
    ne: LatLon,
};

pub fn latLonToMSpace(bounds: Bounds, latlon: LatLon) Point {
    const lon_diff = latlon.lon - bounds.sw.lon;
    const lat_diff = latlon.lat - bounds.sw.lat;

    // Convert longitude and latitude differences to meters
    const earth_radius = 6371000.0;
    const x = lon_diff * (std.math.cos(bounds.sw.lat * std.math.pi / 180.0) * std.math.pi / 180.0) * earth_radius;
    const y = lat_diff * (std.math.pi / 180.0) * earth_radius;

    return .{ .x = x, .y = y };
}

pub fn mToLatLonSpace(bounds: Bounds, point: Point) LatLon {
    const earth_radius = 6371000.0;
    const lat = bounds.sw.lat + point.y / earth_radius * 180.0 / std.math.pi;
    const lon = bounds.sw.lon + point.x / (earth_radius * std.math.cos(bounds.sw.lat * std.math.pi / 180.0)) * 180.0 / std.math.pi;
    return .{ .lat = lat, .lon = lon };
}