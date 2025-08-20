shader_type spatial;
render_mode unshaded,depth_draw_always;

uniform vec4 _Color : source_color = vec4(0.0, 1.0, 0.0, 1.0);

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, repeat_disable;

uniform float thickness = 0.0;

const vec2 sobel_sample_points[9] = vec2[](
    vec2(-1.0,  1.0), vec2(0.0,  1.0), vec2(1.0,  1.0),
    vec2(-1.0,  0.0), vec2(0.0,  0.0), vec2(1.0,  0.0),
    vec2(-1.0, -1.0), vec2(0.0, -1.0), vec2(1.0, -1.0)
);

const float sobel_x[9] = float[](
     1.0, 0.0, -1.0,
     2.0, 0.0, -2.0,
     1.0, 0.0, -1.0
);

const float sobel_y[9] = float[](
     1.0,  2.0,  1.0,
     0.0,  0.0,  0.0,
    -1.0, -2.0, -1.0
);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
	//POSITION = vec4(VERTEX, 1.0);
}

void fragment() {
    vec2 uv = SCREEN_UV;

    vec2 sobel = vec2(0.0);
	float depthDiff = 0.0;
	float depth = texture(DEPTH_TEXTURE, uv).r;
    for (int i = 0; i < 9; i++) {
        float depthN = texture(DEPTH_TEXTURE, uv + sobel_sample_points[i] * thickness).r;
		sobel += depthN * vec2(sobel_x[i], sobel_y[i]);

		 depthDiff = max(depthDiff, abs(depthN - depth));
    }

    float edge = length(sobel);

	edge = (edge >= 0.1 && depthDiff > 0.01) ? edge : 0.;
	edge = edge > 0.0 ? clamp(0.5,0.5,edge) : 0.0;

	ALBEDO = mix(vec3(0.0), _Color.rgb, edge);
	ALPHA = texture(SCREEN_TEXTURE,SCREEN_UV).a>0.0 ? edge*_Color.a:0.0;


}
