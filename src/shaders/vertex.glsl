#version 330 core

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec2 aTexCoords;

out vec3 FragPos;
out vec3 Normal;
out vec2 TexCoords;

uniform mat4 world_to_clip;
uniform vec3 camera_position;
uniform mat4 object_to_world;
uniform vec4 basecolor_roughness;
uniform uint tex;
uniform uint flat_shading;
uniform uint follow_camera_light;
uniform float ambient_light;

void main()
{
    FragPos = (vec4(aPos, 1.0) * object_to_world).xyz;
    Normal = aNormal * mat3(object_to_world);
    TexCoords = aTexCoords;

    gl_Position = vec4(aPos, 1.0) * object_to_world * world_to_clip;
}