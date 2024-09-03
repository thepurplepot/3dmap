const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const zm = @import("zmath");
const Allocator = std.mem.Allocator;

window: *zglfw.Window,

size: struct {
    width: u32 = 800,
    height: u32 = 500,
} = .{},

camera: struct {
    position: [3]f32 = .{ 0.0, 5.0, 3.0 },
    forward: [3]f32 = .{ 0.0, 0.0, -1.0 },
    pitch: f32 = 0.125 * math.pi,
    yaw: f32 = 0.0,
} = .{},

mouse: struct {
    cursor_pos: [2]f64 = .{ 0.0, 0.0 },
    left_button: bool = false,
    captured: bool = false,
} = .{},

options: struct {
    texture: bool = true,
    elevation_scale: f32 = 1.0,
} = .{},

const Self = @This();

const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    tex_index: u32,
};

pub fn create(alloc: Allocator, window: *zglfw.Window) !*Self {
    const app_state = try alloc.create(Self);
    app_state.* = .{.window = window};
    return app_state;
}

pub fn destroy(self: *Self, alloc: Allocator) void {
    alloc.destroy(self);
}

fn updateFpsCounter() f64 {
    const state = struct {
        var previous_seconds: f64 = 0.0;
        var frame_count: i32 = 0;
        var fps: f64 = 60.0;
    };
    const current_seconds: f64 = zglfw.getTime();
    const elapsed_seconds: f64 = current_seconds - state.previous_seconds;
    if (elapsed_seconds > 0.25) {
        state.previous_seconds = current_seconds;
        state.fps = @as(f64, @floatFromInt(state.frame_count)) / elapsed_seconds;
        state.frame_count = 0;
    }
    state.frame_count += 1;
    return state.fps;
}

pub fn update(self: *Self) void {
    const fps = updateFpsCounter();
    zgui.backend.newFrame(self.size.width, self.size.height);
    zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .always });
    zgui.setNextWindowSize(.{ .w = 600, .h = 500, .cond = .always });

    zgui.pushStyleVar1f(.{ .idx = .window_rounding, .v = 5.0 });
    zgui.pushStyleVar2f(.{ .idx = .window_padding, .v = .{ 5.0, 5.0 } });
    defer zgui.popStyleVar(.{ .count = 2 });

    if (zgui.begin("Settings", .{ .flags = .{ .no_move = true, .no_resize = true, .no_title_bar = true } })) {
        zgui.bullet();
        zgui.textUnformattedColored(.{ 0, 0.8, 0, 1 }, "Average :");
        zgui.sameLine(.{});
        zgui.text("{d:.3} ms/frams ({d:.1} fps)", .{ 0, fps });
        zgui.spacing();
        if (zgui.sliderFloat("Elevation Scale", .{ .v = &self.options.elevation_scale, .min = 0.1, .max = 10.0, .cfmt = "%.1f" })) {
        }
        if (zgui.checkbox("Texture?", .{ .v = &self.options.texture })) {
        }
    }
    zgui.end();

    const window = self.window;

    // Handle camera rotation with mouse.
    {
        const cursor_pos = window.getCursorPos();
        const delta_x = @as(f32, @floatCast(cursor_pos[0] - self.mouse.cursor_pos[0]));
        const delta_y = @as(f32, @floatCast(cursor_pos[1] - self.mouse.cursor_pos[1]));
        self.mouse.cursor_pos = cursor_pos;

        const mouse_pressed = window.getMouseButton(.left) == .press;
        if (self.mouse.left_button != mouse_pressed) {
            if (mouse_pressed) {
                if (self.mouse.captured) {
                    window.setInputMode(.cursor, zglfw.Cursor.Mode.normal);
                    window.setInputMode(.raw_mouse_motion, false);
                }
                self.mouse.captured = false;
            } else {
                // On release
            }
        }
        self.mouse.left_button = mouse_pressed;

        const mouse_right = window.getMouseButton(.right) == .press;
        if (mouse_right) {
            if (!self.mouse.captured) {
                window.setInputMode(.cursor, zglfw.Cursor.Mode.disabled);
                window.setInputMode(.raw_mouse_motion, true);
            }
            self.mouse.captured = true;
        }

        if(self.mouse.captured) {
            self.camera.pitch += 0.0025 * delta_y;
            self.camera.yaw += 0.0025 * delta_x;
            self.camera.pitch = @min(self.camera.pitch, 0.48 * math.pi);
            self.camera.pitch = @max(self.camera.pitch, -0.48 * math.pi);
            self.camera.yaw = zm.modAngle(self.camera.yaw);
        }
    }

    // Handle camera movement with 'WASD' keys.
    {
        const speed = blk: {
            if (window.getKey(.left_shift) == .press) {
                break :blk zm.f32x4s(20.0);
            } else {
                break :blk zm.f32x4s(10.0);
            }
        };
        const delta_time = zm.f32x4s(@floatCast(1/fps));
        const transform = zm.mul(zm.rotationX(self.camera.pitch), zm.rotationY(self.camera.yaw));
        var forward = zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 0.0), transform));

        zm.storeArr3(&self.camera.forward, forward);

        const right = speed * delta_time *
            zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 0.0), forward));
        forward = speed * delta_time * forward;

        var cam_pos = zm.loadArr3(self.camera.position);

        if (window.getKey(.w) == .press) {
            cam_pos += forward;
        } else if (window.getKey(.s) == .press) {
            cam_pos -= forward;
        }
        if (window.getKey(.d) == .press) {
            cam_pos += right;
        } else if (window.getKey(.a) == .press) {
            cam_pos -= right;
        }

        zm.storeArr3(&self.camera.position, cam_pos);
    }
}
