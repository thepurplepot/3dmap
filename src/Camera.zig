const std = @import("std");
const gl = @import("opengl_bindings.zig");

//TODO better movment

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
near: f32 = 0.001,
far: f32 = 3.0,
position: Vector3f = Vector3f{ .x = 0, .y = 0, .z = 0.05 },
target: Vector3f = Vector3f{ .x = 0.0, .y = 0.0, .z = 0.0 },
up: Vector3f = Vector3f{ .x = 0.0, .y = 0.0, .z = 1.0 },
yaw: f32 = 90,
pitch: f32 = -15,
view: [16]f32 = undefined,
projection: [16]f32 = undefined,
mouse_down: bool = false,
last_mouse_pos: MousePos = MousePos{ .x = 0.0, .y = 0.0 },

const speed = 0.005;

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
    _ = program;

    self.rotate(0, 0);

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

pub fn handleMove(self: *Camera, direction: MoveDirection) void {
    const toTarget = self.target.sub(self.position);
    const right = toTarget.cross(self.up).normalize();
    switch (direction) {
        .Forward => self.move(toTarget, speed),
        .Backward => self.move(toTarget, -speed),
        .Left => self.move(right, -speed),
        .Right => self.move(right, speed),
    }
}

fn move(self: *Camera, direction: Vector3f, amount: f32) void {
    const movement = direction.mul(amount);
    self.position = self.position.add(movement);
    self.target = self.target.add(movement);
}

pub fn rotate(self: *Camera, yawOffset: f32, pitchOffset: f32) void {
    self.yaw += yawOffset;
    self.pitch += pitchOffset;
    std.debug.print("Yaw: {d}, Pitch: {d}\n", .{self.yaw, self.pitch});

    // Constrain the pitch
    if (self.pitch > 89.0) self.pitch = 89.0;
    if (self.pitch < -89.0) self.pitch = -89.0;

    const front = (Vector3f{
        .x = @cos(self.yaw / std.math.deg_per_rad) * @cos(self.pitch / std.math.deg_per_rad),
        .y = @cos(self.pitch / std.math.deg_per_rad) * @sin(self.yaw / std.math.deg_per_rad),
        .z = @sin(self.pitch / std.math.deg_per_rad),
    }).normalize();

    self.target = self.position.add(front);
}

pub fn setTarget(self: *Camera, target: Vector3f) void {
    self.target = target;
}

pub fn updateMousePos(self: *Camera, pos: anytype) void {
    if (self.mouse_down) {
        var xOffset = pos.x - self.last_mouse_pos.x;
        var yOffset = pos.y - self.last_mouse_pos.y;

        const sensitivity = 400;
        xOffset *= sensitivity;
        yOffset *= sensitivity;

        self.rotate(-xOffset, -yOffset);
    }

    self.last_mouse_pos = .{.x = pos.x, .y = pos.y};
}