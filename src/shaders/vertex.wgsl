struct DrawUniforms {
    object_to_world: mat4x4<f32>,
    basecolor_roughness: vec4<f32>,
    texture: u32,
}
@group(1) @binding(0) var<uniform> draw_uniforms: DrawUniforms;

struct FrameUniforms {
    world_to_clip: mat4x4<f32>,
    camera_position: vec3<f32>,
}
@group(0) @binding(0) var<uniform> frame_uniforms: FrameUniforms;

struct VertexOut {
    @builtin(position) position_clip: vec4<f32>,
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) @interpolate(flat) tex_index: u32,
}
@vertex fn main(
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
) -> VertexOut {
    var output: VertexOut;
    output.position_clip = vec4(position, 1.0) * draw_uniforms.object_to_world * frame_uniforms.world_to_clip;
    output.position = (vec4(position, 1.0) * draw_uniforms.object_to_world).xyz;
    output.normal = normal * mat3x3(
        draw_uniforms.object_to_world[0].xyz,
        draw_uniforms.object_to_world[1].xyz,
        draw_uniforms.object_to_world[2].xyz,
    );
    output.uv = uv;

    return output;
}