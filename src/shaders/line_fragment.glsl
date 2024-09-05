#version 330 core

uniform mat4 object_to_world;
uniform mat4 world_to_clip;
uniform vec3 line_color;

out vec4 FragColor;

void main() {
    FragColor = vec4(line_color, 1.0);
}