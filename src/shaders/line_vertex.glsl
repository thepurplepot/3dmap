#version 330 core

layout(location = 0) in vec2 position;

uniform mat4 object_to_world;
uniform mat4 world_to_clip;
uniform sampler2D elevation_texture;
uniform vec2 m_range;

void main() {
    vec2 normalized_coords = position / m_range;
    float elevation = texture(elevation_texture, vec2(normalized_coords.x, 1 - normalized_coords.y)).r + 1; //SW to NE indexed

    gl_Position = world_to_clip * object_to_world * vec4(position.x, elevation, position.y, 1.0);
}