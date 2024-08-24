pub const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cDefine("CIMGUI_USE_GLFW", "");
    @cDefine("CIMGUI_USE_OPENGL3", "");
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
    @cInclude("cimgui.h");
    @cInclude("cimgui_impl.h");
});

pub export fn glCreateVertexArray() u32 {
    var ret: u32 = undefined;
    c.glGenVertexArrays(1, &ret);
    return ret;
}

pub export fn glCreateBuffer() u32 {
    var ret: u32 = undefined;
    c.glGenBuffers(1, &ret);
    return @bitCast(ret);
}

pub export fn glDeleteBuffer(id: u32) void {
    const id_c: c_uint = @bitCast(id);
    c.glDeleteBuffers(1, &id_c);
}

pub export fn glVertexAttribPointer(index: u32, size: u32, typ: u32, normalized: bool, stride: u32, offs: u32) void {
    c.glVertexAttribPointer(@intCast(index), @intCast(size), @intCast(typ), @intFromBool(normalized), @intCast(stride), @ptrFromInt(@as(usize, @intCast(offs))));
}

pub export fn glEnableVertexAttribArray(index: u32) void {
    c.glEnableVertexAttribArray(@bitCast(index));
}

pub export fn glBindBuffer(target: u32, id: u32) void {
    c.glBindBuffer(@intCast(target), @bitCast(id));
}

pub export fn glBufferData(target: u32, ptr: [*]const u8, len: usize, usage: u32) void {
    c.glBufferData(@intCast(target), @intCast(len), ptr, @intCast(usage));
}

pub export fn glBindVertexArray(vao: u32) void {
    c.glBindVertexArray(@bitCast(vao));
}

pub export fn glClearColor(r: f32, g: f32, b: f32, a: f32) void {
    c.glClearColor(r, g, b, a);
}

pub export fn glClear(mask: u32) void {
    c.glClear(@bitCast(mask));
}

pub export fn glUseProgram(program: u32) void {
    c.glUseProgram(@bitCast(program));
}

pub export fn glDrawArrays(mode: u32, first: u32, count: u32) void {
    c.glDrawArrays(@intCast(mode), @intCast(first), @intCast(count));
}

pub export fn glDrawElements(mode: u32, count: u32, typ: u32, offs: u32) void {
    c.glDrawElements(@intCast(mode), @intCast(count), @intCast(typ), @ptrFromInt(@as(usize, @intCast(offs))));
}

pub export fn glGetUniformLoc(program: u32, name: [*]const u8, name_len: usize) u32 {
    var buf: [4096]u8 = undefined;
    @memcpy(buf[0..name_len], name);
    buf[name_len] = 0;
    const ret = c.glGetUniformLocation(@bitCast(program), &buf);
    return @bitCast(ret);
}

pub export fn glUniform1f(loc: u32, val: f32) void {
    c.glUniform1f(@bitCast(loc), val);
}

pub export fn glUniform2f(loc: u32, a: f32, b: f32) void {
    c.glUniform2f(@bitCast(loc), a, b);
}

pub export fn glUniform3f(loc: u32, a: f32, b: f32, d: f32) void {
    c.glUniform3f(@bitCast(loc), a, b, d);
}

pub export fn glUniform1i(loc: u32, val: u32) void {
    c.glUniform1i(@bitCast(loc), @intCast(val));
}

pub export fn glActiveTexture(val: u32) void {
    c.glActiveTexture(@bitCast(val));
}

pub export fn glBindTexture(target: u32, val: u32) void {
    c.glBindTexture(@bitCast(target), @bitCast(val));
}