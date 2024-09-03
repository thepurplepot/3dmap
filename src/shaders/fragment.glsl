#version 330 core

in vec3 FragPos;
in vec3 Normal;
in vec2 TexCoords;

out vec4 FragColor;

uniform sampler2D texture_sampler;
uniform mat4 world_to_clip;
uniform vec3 camera_position;
uniform mat4 object_to_world;
uniform vec4 basecolor_roughness;
uniform uint tex;
uniform uint flat_shading;
uniform uint follow_camera_light;
uniform float ambient_light;
uniform float specular_strength;

float saturate(float x) { return clamp(x, 0.0, 1.0); }

float distributionGgx(vec3 n, vec3 h, float alpha) {
    float alpha_sq = alpha * alpha;
    float n_dot_h = saturate(dot(n, h));
    float k = n_dot_h * n_dot_h * (alpha_sq - 1.0) + 1.0;
    return alpha_sq / (3.1415926 * k * k);
}

float geometrySchlickGgx(float x, float k) {
    return x / (x * (1.0 - k) + k);
}

float geometrySmith(vec3 n, vec3 v, vec3 l, float k) {
    float n_dot_v = saturate(dot(n, v));
    float n_dot_l = saturate(dot(n, l));
    return geometrySchlickGgx(n_dot_v, k) * geometrySchlickGgx(n_dot_l, k);
}

vec3 fresnelSchlick(float h_dot_v, vec3 f0) {
    return f0 + (vec3(1.0, 1.0, 1.0) - f0) * pow(1.0 - h_dot_v, 5.0);
}

void main()
{
    // vec3 v = normalize(camera_position - FragPos);
    // vec3 n = normalize(Normal);

    // vec3 base_color = basecolor_roughness.rgb;
    // if(tex == uint(1)) {
    //     base_color = texture(texture_sampler, TexCoords).rgb;
    // }
    // float ao = 1.0;
    // float roughness = basecolor_roughness.a;
    // float metallic = roughness < 0.0 ? 1.0 : 0.0;
    // roughness = abs(roughness);

    // float alpha = roughness * roughness;
    // float k = alpha + 1.0;
    // k = (k * k) / 8;
    // vec3 f0 = vec3(0.04);
    // f0 = mix(f0, base_color, metallic);

    // //Sun
    // vec3 sun_direction = normalize(vec3(-0.5, -0.05, -0.5));
    // vec3 sun_color = vec3(1.0, 1.0, 0.9);

    // vec3 l = normalize(sun_direction);
    // vec3 h = normalize(l + v);

    // vec3 f = fresnelSchlick(saturate(dot(h, v)), f0);
    // float ndf = distributionGgx(n, h, alpha);
    // float g = geometrySmith(n, v, l, k);

    // vec3 numerator = ndf * g * f;
    // float denominator = 4.0 * saturate(dot(n, v)) * saturate(dot(n, l));
    // vec3 specular = numerator / max(denominator, 0.001);

    // vec3 ks = f;
    // vec3 kd = (vec3(1.0) - ks) * (1.0 - metallic);

    // float n_dot_l = saturate(dot(n, l));
    // vec3 lo = (kd * base_color / 3.1415926 + specular) * sun_color * n_dot_l;

    // // Ambient
    // vec3 ambient = vec3(0.1) * base_color * ao;
    // vec3 color = ambient; //+ lo;
    // color = color / (color + 1.0);
    // color = pow(color, vec3(1.0 / 2.2));



    vec3 lightColor = vec3(1.0, 1.0, 0.8);
    vec3 lightPos = vec3(-20.0, 20.0, -20.0);
    if (follow_camera_light == uint(1)) {
        lightPos = camera_position + vec3(5.0, 0.0, 0.0);
    }
    // Ambient
    float ambientStrength = ambient_light;
    vec3 ambient = ambientStrength * lightColor;
    
    // Diffuse 
    vec3 norm = normalize(Normal);
    vec3 lightDir = normalize(lightPos - FragPos);
    float diff = max(dot(norm, lightDir), 0.0);
    vec3 diffuse = diff * lightColor;
    
    // Specular
    vec3 viewDir = normalize(camera_position - FragPos);
    vec3 reflectDir = reflect(-lightDir, norm);  
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32);
    vec3 specular = specular_strength * spec * lightColor; 

    vec3 colour = basecolor_roughness.rgb;
    if (tex == uint(1)) {
        colour = texture(texture_sampler, TexCoords).rgb;
    } 
    
    vec3 result = (ambient + diffuse + specular) * colour;

    if (flat_shading == uint(1)) {
        FragColor = vec4(colour, 1.0);
    } else {
        FragColor = vec4(result, 1.0);
    }
}