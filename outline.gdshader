shader_type spatial;
render_mode unshaded;

// pixel sampling radius
uniform float scale = 1.0;

uniform vec4 _Color : source_color = vec4(0.0, 1.0, 0.0, 1.0);

uniform float _DepthNormalThreshold = 0.1;
uniform float _DepthNormalThresholdScale = 3.;
uniform float _DepthThreshold = 1.5;
uniform float _NormalThreshold = 2.0;


uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, repeat_disable;

float linearize_depth(float depth)
{
    float z = depth * 2.0 - 1.0;
    return (2.0 * 0.05 * 4000.) / (4000. + 0.05 - z * (4000. - 0.05));
	//return 0.05 * 4000. / (4000. + depth * (0.05 - 4000.));
}

vec3 get_view_position_from_uv(vec2 uv, float depth, mat4 inv_proj_m)
{
	vec4 position_ndc = vec4((uv * 2.0) - 1.0, depth, 1.0);
	vec4 view_position = inv_proj_m * position_ndc;
	return view_position.xyz /= view_position.w;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
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

    // Normals
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

	float edge = max(edgeDepth, max(edgeNormal,0.0));

	float dilated_edge = edge;

	// Directional offsets for 4-neighbor dilation
	vec2 offsets[4] = vec2[](
	    vec2(texel_size.x, 0.0),
	    vec2(-texel_size.x, 0.0),
	    vec2(0.0, texel_size.y),
	    vec2(0.0, -texel_size.y)
	);
	float scaleee = clamp(1.0 / depth0, 0.0, 5.0);
	float view_depth = linearize_depth(texture(DEPTH_TEXTURE, SCREEN_UV).r);
	vec3 view_depththree = get_view_position_from_uv(SCREEN_UV, texture(DEPTH_TEXTURE, SCREEN_UV).r,INV_PROJECTION_MATRIX);
	view_depth = -view_depththree.z;

	vec4 edgeColor = vec4(_Color.rgb, _Color.a * dilated_edge);

	float nearDistance = 0.0;
	float farDistance  = 20.0;

	float distanceFade = 1.0 - smoothstep(nearDistance,farDistance, view_depth);

	ALBEDO = mix(texture(SCREEN_TEXTURE,SCREEN_UV).rgb, edgeColor.rgb, edgeColor.a);
	ALPHA = edgeColor.a;
}