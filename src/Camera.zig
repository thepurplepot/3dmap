const std = @import("std");
const gl = @import("opengl_bindings.zig");

const Vector3f = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn add(self: Vector3f, other: Vector3f) Vector3f {
        return Vector3f{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    pub fn sub(self: Vector3f, other: Vector3f) Vector3f {
        return Vector3f{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
    }

    pub fn mul(self: Vector3f, other: f32) Vector3f {
        return Vector3f{
            .x = self.x * other,
            .y = self.y * other,
            .z = self.z * other,
        };
    }

    pub fn dot(self: Vector3f, other: Vector3f) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn cross(self: Vector3f, other: Vector3f) Vector3f {
        return Vector3f{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    pub fn normalize(self: Vector3f) Vector3f {
        const len = std.math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
        return Vector3f{
            .x = self.x / len,
            .y = self.y / len,
            .z = self.z / len,
        };
    }
};

const MousePos = struct {
    x: f32,
    y: f32,
};

const Camera = @This();

fov: f32 = 45.0 / std.math.deg_per_rad,
aspect: f32 = 800.0 / 600.0,
near: f32 = 0.1,
far: f32 = 100.0,
position: Vector3f = Vector3f{ .x = -2.0, .y = -1.0, .z = 3.0 },
target: Vector3f = Vector3f{ .x = 0.0, .y = 0.0, .z = 0.0 },
up: Vector3f = Vector3f{ .x = 0.0, .y = 0.0, .z = 1.0 },
view: [16]f32 = undefined,
projection: [16]f32 = undefined,

const speed = 0.05;

fn lookAt(eye: Vector3f, center: Vector3f, up: Vector3f) [16]f32 {
    const f = center.sub(eye).normalize();
    const s = f.cross(up.normalize()).normalize();
    const u = s.cross(f);

    return [_]f32{
        s.x,         u.x,         -f.x,       0.0,
        s.y,         u.y,         -f.y,       0.0,
        s.z,         u.z,         -f.z,       0.0,
        -s.dot(eye), -u.dot(eye), f.dot(eye), 1.0,
    };
}

fn perspective(fov: f32, aspect: f32, near: f32, far: f32) [16]f32 {
    const tanHalfFov = std.math.tan(fov / 2.0);
    return [_]f32{
        1.0 / (aspect * tanHalfFov), 0.0,              0.0,                                0.0,
        0.0,                         1.0 / tanHalfFov, 0.0,                                0.0,
        0.0,                         0.0,              -(far + near) / (far - near),       -1.0,
        0.0,                         0.0,              -(2.0 * far * near) / (far - near), 0.0,
    };
}

pub fn setAspect(self: *Camera, aspect: f32) void {
    self.aspect = aspect;
}

pub fn update(self: *Camera, program: u32, aspect: f32) void {
    //TODO rotate camera with mouse?
    self.aspect = aspect;
    self.view = lookAt(self.position, self.target, self.up);
    const viewLoc = gl.glGetUniformLoc(program, "view", 4);
    gl.c.glUniformMatrix4fv(@bitCast(viewLoc), 1, gl.c.GL_FALSE, &self.view);

    self.projection = perspective(self.fov, self.aspect, self.near, self.far);
    const projectionLoc = gl.glGetUniformLoc(program, "projection", 10);
    gl.c.glUniformMatrix4fv(@bitCast(projectionLoc), 1, gl.c.GL_FALSE, &self.projection);

    //For lighting
    const viewPosLocation = gl.glGetUniformLoc(program, "viewPos", 7);
    gl.glUniform3f(viewPosLocation, self.position.x, self.position.y, self.position.z);
}

pub fn setupView(self: *Camera, program: u32) void {
    _ = self;
    _ = program;

    // const viewLoc = gl.glGetUniformLoc(program, "view", 4);
    // gl.c.glUniformMatrix4fv(@bitCast(viewLoc), 1, gl.c.GL_FALSE, &self.view);

    // const projectionLoc = gl.glGetUniformLoc(program, "projection", 10);
    // gl.c.glUniformMatrix4fv(@bitCast(projectionLoc), 1, gl.c.GL_FALSE, &self.projection);
}

pub const MoveDirection = enum {
    Forward,
    Backward,
    Left,
    Right,
};

pub fn move(self: *Camera, direction: MoveDirection) void {
    const toTarget = self.target.sub(self.position);
    const forward = toTarget.normalize().mul(speed);
    const right = toTarget.cross(self.up).normalize().mul(speed);
    switch (direction) {
        .Forward => self.position = self.position.add(forward),
        .Backward => self.position = self.position.sub(forward),
        .Left => self.position = self.position.sub(right),
        .Right => self.position = self.position.add(right),
    }
}

pub fn setTarget(self: *Camera, target: Vector3f) void {
    self.target = target;
}

pub const RotateDirection = enum {
    Up,
    Down,
    Left,
    Right,
};
//TODO better rotation
pub fn rotate(self: *Camera, direction: RotateDirection) void {
    const toTarget = self.target.sub(self.position);
    const right = toTarget.cross(self.up).normalize();
    const up = right.cross(toTarget).normalize();
    const rotation = 0.1;
    switch (direction) {
        .Up => self.position = self.position.add(up.mul(rotation)),
        .Down => self.position = self.position.sub(up.mul(rotation)),
        .Left => self.up = self.up.add(right.mul(rotation)),
        .Right => self.up = self.up.sub(right.mul(rotation)),
    }
}
