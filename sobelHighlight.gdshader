/*shader_type spatial;
render_mode unshaded;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, repeat_disable;

uniform float thickness = 0.01;

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
	// Called for every vertex the material is visible on.
}

void fragment() {
    vec2 uv = UV;
    vec2 texel_size = vec2(thickness);

    vec2 sobel = vec2(0.0);

    for (int i = 0; i < 9; i++) {
        float depth = texture(SCREEN_TEXTURE, uv + sobel_sample_points[i] * thickness).r;
		ALBEDO = vec3(depth);
        sobel += depth * vec2(sobel_x[i], sobel_y[i]);
    }

    float edge = length(sobel);
    ALBEDO =  texture(SCREEN_TEXTURE,UV).rgb;
}*/
//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
shader_type spatial;
render_mode unshaded;

// pixel sampling radius
uniform float scale = 1.0;

// outline dilation after computation
uniform float outline_spread = 1.0;

uniform vec4 _Color : source_color = vec4(0.0, 1.0, 0.0, 1.0);


uniform float _DepthNormalThreshold = 0.1;
uniform float _DepthNormalThresholdScale = 3.;
uniform float _DepthThreshold = 1.5;
uniform float _NormalThreshold = 2.0;

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
	float half_scale_floor = floor(scale * 0.5);
    float half_scale_ceil = ceil(scale * 0.5);


	float half_scale_floor2 = ceil(scale * 0.5 * 2.);
	float half_scale_ceil2 = ceil(scale *0.5 * 2.);

    vec2 texel_size = vec2(1.0) / vec2(textureSize(SCREEN_TEXTURE, 0));

    // Compute UV coordinates
    vec2 bottom_left_uv  = SCREEN_UV - vec2(texel_size.x, texel_size.y) * half_scale_floor;
    vec2 top_right_uv    = SCREEN_UV + vec2(texel_size.x, texel_size.y) * half_scale_ceil;
    vec2 bottom_right_uv = SCREEN_UV + vec2(texel_size.x * half_scale_ceil, -texel_size.y * half_scale_floor);
    vec2 top_left_uv     = SCREEN_UV + vec2(-texel_size.x * half_scale_floor, texel_size.y * half_scale_ceil);

	vec3 normal0 = texture(normal_roughness_texture, bottom_left_uv).rgb;
    vec3 normal1 = texture(normal_roughness_texture, top_right_uv).rgb;
    vec3 normal2 = texture(normal_roughness_texture, bottom_right_uv).rgb;
    vec3 normal3 = texture(normal_roughness_texture, top_left_uv).rgb;



	    // Depth
    float depth0 = texture(DEPTH_TEXTURE, bottom_left_uv).r;
    float depth1 = texture(DEPTH_TEXTURE, top_right_uv).r;
    float depth2 = texture(DEPTH_TEXTURE, bottom_right_uv).r;
    float depth3 = texture(DEPTH_TEXTURE, top_left_uv).r;

	vec3 viewNormal = normal0 * 2. - 1.;
	float NdotV = 1. - dot(viewNormal, VIEW);

	// Return a value in the 0...1 range depending on where NdotV lies
	// between _DepthNormalThreshold and 1.
	float normalThreshold01 = clamp(((NdotV - _DepthNormalThreshold) / (1. - _DepthNormalThreshold)),0.0,1.0);
	// Scale the threshold, and add 1 so that it is in the range of 1..._NormalThresholdScale + 1.
	float normalThreshold = normalThreshold01 * _DepthNormalThresholdScale + 1.;

	float depthThreshold = _DepthThreshold * depth0 * normalThreshold;

	float depthFiniteDifference0 = depth1 - depth0;
	float depthFiniteDifference1 = depth3 - depth2;

	float edgeDepth = sqrt(pow(depthFiniteDifference0, 2.) + pow(depthFiniteDifference1, 2.)) * 100.;
	edgeDepth = edgeDepth > depthThreshold ? 1. : 0.;








	vec3 normalFiniteDifference0 = normal1 - normal0;
	vec3 normalFiniteDifference1 = normal3 - normal2;

	float edgeNormal = sqrt(dot(normalFiniteDifference0, normalFiniteDifference0) + dot(normalFiniteDifference1, normalFiniteDifference1));
	edgeNormal = edgeNormal > _NormalThreshold ? 1. : 0.;

      vec2 uv = SCREEN_UV;
    //vec2 texel_size = vec2(thickness);

    vec2 sobel = vec2(0.0);
	float maxDiff = 0.0;
	float depth = texture(DEPTH_TEXTURE, uv).r;
    for (int i = 0; i < 9; i++) {
        float depthN = texture(DEPTH_TEXTURE, uv + sobel_sample_points[i] * thickness).r;


		float diff = abs(depth - depthN);
    	maxDiff = max(maxDiff, diff);

		sobel += depthN * vec2(sobel_x[i], sobel_y[i]);


    }
	//edgeDepth = edgeDepth > depthThreshold ? 1. : 0.;


	float eps = 1e-6;
	float objectMask = (depth > eps && depth < 1.0 - eps) ? 1.0 : 0.0;

    float edge = length(sobel);

	edge = max(edge, 0.0);
	edge = (edge >= 0.2) ? 1. : 0.;

    //edge = maxDiff > 0.05 ? edge : 0.0;

	ALBEDO = mix(vec3(0.0), _Color.rgb, edge);
	//ALBEDO = vec3(objectMask);
	ALPHA = edge*_Color.a*objectMask;
	//ALBEDO = texture(SCREEN_TEXTURE,SCREEN_UV).rgb;
	//ALBEDO = vec3(edge);
	//ALBEDO = mix(vec3(0.0), edgeColor.rgb, edgeColor.a);

}
