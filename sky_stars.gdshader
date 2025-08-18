shader_type sky;

uniform sampler2D sky_tex : source_color;

uniform float energy : hint_range(0.0, 10.0, 0.1) = 1.0;
uniform float gamma : hint_range(0.0,4.0) = 1.0;
uniform sampler2D tint_ramp : source_color, repeat_disable, hint_default_white;
uniform vec3 scale = vec3(1);
uniform float triplanar_blend_power : hint_range(0.0,40.0) = 4.0;
uniform float seamless_blend : hint_range(0.0,0.5) = 0.1;

vec4 textureSeamless(sampler2D tex, vec2 uv, vec2 padding){
	vec2 inv_scale = 1.0 / (1.0 + 2.0 * padding);

	// Get partial derivatives here for textureGrad() to avoid mipmapping seams
	vec2 dx = dFdx(uv) * inv_scale;
	vec2 dy = dFdy(uv) * inv_scale;

	// Textures need to repeat somewhere. In addition, repeat must be enabled on the sampler
	uv = fract(uv+0.5)-0.5;

	// Get the bilinear blend factors. This is actually undefined for padding = 0
	vec2 u = smoothstep(-padding, padding, uv);

	// Apply scale
	uv *= inv_scale;

	// Bilinear interpolation
	inv_scale = 0.5 * (1.0 - inv_scale);
	vec4 lower_right = textureGrad(tex, uv - vec2(-1,-1) * inv_scale,  dx, dy);
	vec4 lower_left = textureGrad(tex, uv - vec2(1,-1) * inv_scale,  dx, dy);
	vec4 upper_right = textureGrad(tex, uv - vec2(-1,1) * inv_scale, dx, dy);
	vec4 upper_left = textureGrad(tex, uv - vec2(1,1) * inv_scale, dx, dy);

	lower_right = mix(lower_left, lower_right, u.x);
	upper_right = mix(upper_left, upper_right, u.x);

	return mix(upper_right, lower_right, u.y);
}

// "p" point being textured
// "n" surface normal at "p"
// "k" controls the sharpness of the blending in the transitions areas
// "s" texture sampler
vec4 boxmap( in sampler2D s, in vec3 p, in vec3 n, in float k )
{
    // project+fetch
    vec4 x = textureSeamless( s, p.yz, vec2(seamless_blend) );
    vec4 y = textureSeamless( s, p.zx, vec2(seamless_blend) );
    vec4 z = textureSeamless( s, p.xy, vec2(seamless_blend) );

    // blend weights
    vec3 w = pow( abs(n), vec3(k) );

    // blend and return
    return (x*w.x + y*w.y + z*w.z) / (w.x + w.y + w.z);
}

void sky() {
	// Ray direction
	vec3 rd = EYEDIR;

	// Apply scaling
	vec3 p = rd;
	p = normalize(rd / scale) * scale;
	vec3 n = normalize(p / scale);

	// Triplanar mapping of sky texture
	COLOR = boxmap(sky_tex, p, n, triplanar_blend_power).rgb;
	COLOR = energy * pow(COLOR, vec3(gamma));
	COLOR *= textureLod(tint_ramp, SKY_COORDS.yx, 0.0).rgb;

	// Alpha of tint ramp determines transparency of sky texture
	COLOR = mix(textureLod(tint_ramp, SKY_COORDS.yx, 0.0).rgb, COLOR, textureLod(tint_ramp, SKY_COORDS.yx, 0.0).a);
}