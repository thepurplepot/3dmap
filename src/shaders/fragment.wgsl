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

@group(1) @binding(1) var image: texture_2d_array<f32>;
@group(1) @binding(2) var image_sampler: sampler;

const pi = 3.1415926;

fn saturate(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

// Trowbridge-Reitz GGX normal distribution function.
fn distributionGgx(n: vec3<f32>, h: vec3<f32>, alpha: f32) -> f32 {
    let alpha_sq = alpha * alpha;
    let n_dot_h = saturate(dot(n, h));
    let k = n_dot_h * n_dot_h * (alpha_sq - 1.0) + 1.0;
    return alpha_sq / (pi * k * k);
}

fn geometrySchlickGgx(x: f32, k: f32) -> f32 {
    return x / (x * (1.0 - k) + k);
}

fn geometrySmith(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, k: f32) -> f32 {
    let n_dot_v = saturate(dot(n, v));
    let n_dot_l = saturate(dot(n, l));
    return geometrySchlickGgx(n_dot_v, k) * geometrySchlickGgx(n_dot_l, k);
}

fn fresnelSchlick(h_dot_v: f32, f0: vec3<f32>) -> vec3<f32> {
    return f0 + (vec3(1.0, 1.0, 1.0) - f0) * pow(1.0 - h_dot_v, 5.0);
}

@fragment fn main(
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) @interpolate(flat) tex_index: u32,
) -> @location(0) vec4<f32> {
    let v = normalize(frame_uniforms.camera_position - position);
    let n = normalize(normal);

    let base_color = draw_uniforms.basecolor_roughness.xyz;
    let ao = 1.0;
    var roughness = draw_uniforms.basecolor_roughness.a;
    var metallic: f32;
    if (roughness < 0.0) { metallic = 1.0; } else { metallic = 0.0; }
    roughness = abs(roughness);

    let alpha = roughness * roughness;
    var k = alpha + 1.0;
    k = (k * k) / 8.0;
    var f0 = vec3(0.04);
    f0 = mix(f0, base_color, metallic);

    let light_positions = array<vec3<f32>, 2>(
        vec3(25.0, 25.0, 25.0),
        vec3(-25.0, 25.0, 25.0),
        // vec3(25.0, 25.0, -25.0),
        // vec3(-25.0, 25.0, -25.0),
    );
    let light_radiance = array<vec3<f32>, 2>(
        20.0 * vec3(200.0, 160.0, 120.0),
        20.0 * vec3(200.0, 150.0, 200.0),
        // 20.0 * vec3(200.0, 0.0, 0.0),
        // 20.0 * vec3(200.0, 150.0, 0.0),
    );

    var lo = vec3(0.0);
    for (var light_index: i32 = 0; light_index < 2; light_index = light_index + 1) {
        let lvec = light_positions[light_index] - position;

        let l = normalize(lvec);
        let h = normalize(l + v);

        let distance_sq = dot(lvec, lvec);
        let attenuation = 1.0 / distance_sq;
        let radiance = light_radiance[light_index] * attenuation;

        let f = fresnelSchlick(saturate(dot(h, v)), f0);

        let ndf = distributionGgx(n, h, alpha);
        let g = geometrySmith(n, v, l, k);

        let numerator = ndf * g * f;
        let denominator = 4.0 * saturate(dot(n, v)) * saturate(dot(n, l));
        let specular = numerator / max(denominator, 0.001);

        let ks = f;
        let kd = (vec3(1.0) - ks) * (1.0 - metallic);

        let n_dot_l = saturate(dot(n, l));
        lo = lo + (kd * base_color / pi + specular) * radiance * n_dot_l;
    }

    let ambient = vec3(0.1) * base_color * ao;
    var color = ambient + lo;
    color = color / (color + 1.0);
    color = pow(color, vec3(1.0 / 2.2));

    if(draw_uniforms.texture == 1u) {
        color = color * textureSample(image, image_sampler, uv, tex_index).xyz;
    }

    return vec4(color, 1.0);
}   