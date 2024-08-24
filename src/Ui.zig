const std = @import("std");
const gl = @import("opengl_bindings.zig");
const Mesh = @import("Mesh.zig");

pub const Ui = @This();

const overlay_width = 400;
io: *gl.c.ImGuiIO,
height_multiplier: f32 = 1.0,

pub fn init(window: *gl.c.GLFWwindow) !Ui {
    _ = gl.c.igCreateContext(null);
    errdefer gl.c.igDestroyContext(null);

    if (!gl.c.ImGui_ImplGlfw_InitForOpenGL(window, true)) {
        return error.InitImGuiGlfw;
    }
    errdefer gl.c.ImGui_ImplGlfw_Shutdown();

    if (!gl.c.ImGui_ImplOpenGL3_Init("#version 150")) {
        return error.InitImGuiOgl;
    }
    errdefer gl.c.ImGui_ImplOpenGL3_Shutdown();

    const io = gl.c.igGetIO();
    io.*.IniFilename = null;
    io.*.LogFilename = null;

    return .{
        .io = io,
    };
}

pub fn deinit(self: *Ui) void {
    _ = self;
    gl.c.ImGui_ImplOpenGL3_Shutdown();
    gl.c.ImGui_ImplGlfw_Shutdown();
    gl.c.igDestroyContext(null);
}

fn startFrame() void {
    gl.c.ImGui_ImplOpenGL3_NewFrame();
    gl.c.ImGui_ImplGlfw_NewFrame();
    gl.c.igNewFrame();
}

fn setOverlayDims(self: *Ui, width: c_int, height: c_int) void {
    _ = self;
    gl.c.igSetNextWindowSize(.{
        .x = overlay_width,
        .y = 0,
    }, 0);
    gl.c.igSetNextWindowPos(
        .{
            .x = @floatFromInt(width - 20),
            .y = @floatFromInt(height - 10),
        },
        0,
        .{
            .x = 1.0,
            .y = 1.0,
        },
    );
}

pub const RequestedActions = struct {
    consumed_mouse_input: bool = false,
    update_height_multiplier: ?f32 = null,
};

fn drawOverlay(self: *Ui) RequestedActions {
    var actions = RequestedActions{};
    _ = gl.c.igBegin("Overlay", null, gl.c.ImGuiWindowFlags_NoResize | gl.c.ImGuiWindowFlags_NoMove | gl.c.ImGuiWindowFlags_NoTitleBar);

    if (gl.c.igSliderFloat("Height Multiplier", &self.height_multiplier, 0, 10, "%.3f", 0)) {
        actions.update_height_multiplier = self.height_multiplier;
    }

    gl.c.igEnd();

    actions.consumed_mouse_input = self.io.*.WantCaptureMouse;

    return actions;
}

pub fn render(self: *Ui, width: c_int, height: c_int) RequestedActions {
    startFrame();
    self.setOverlayDims(width, height);

    const ret = self.drawOverlay();
    gl.c.igRender();
    gl.c.ImGui_ImplOpenGL3_RenderDrawData(gl.c.igGetDrawData());
    return ret;
}

pub fn handleUiActions(actions: RequestedActions, mesh: *Mesh) !void {
    if (actions.update_height_multiplier) |val| {
        mesh.updateElevationScale(val);
    }
}
