shader_type spatial;
render_mode cull_disabled,depth_draw_always;//, diffuse_toon, specular_toon;

global uniform sampler2D gradientMetallic;

uniform sampler2D albedo_texture : source_color;
uniform sampler2D lightmap_texture : source_color;

uniform int g_sss_max_steps        = 32;     // Max ray steps, affects quality and performance.
uniform float g_sss_ray_max_distance = 0.03f;  // Max shadow length, longer shadows are less accurate.
uniform float g_sss_thickness        = 0.45f;  // Depth testing thickness.
uniform float g_sss_max_delta_from_original_depth = 0.005f; // The maximum allowed depth deviation from the original pixel (a big deviation decreased the probabilty that the pixel is the occluder).
uniform float g_sss_min_thickness = 0.004f;
global uniform vec4 shadow_color: source_color;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
varying vec3 camera_pos_world;

vec2 get_uv_from_view_position(vec3 position_view_space, mat4 proj_m)
{
	vec4 position_clip_space = proj_m * vec4(position_view_space.xyz, 1.0);
	vec2 position_ndc = position_clip_space.xy / position_clip_space.w;
	return position_ndc.xy * 0.5 + 0.5;
}

vec3 get_view_position_from_uv(vec2 uv, float depth, mat4 inv_proj_m)
{
	vec4 position_ndc = vec4((uv * 2.0) - 1.0, depth, 1.0);
	vec4 view_position = inv_proj_m * position_ndc;
	return view_position.xyz /= view_position.w;
}

bool is_within_screen_boundaries(vec2 position)
{
	return position.x > 0.0 && position.x < 1.0 && position.y > 0.0 && position.y < 1.0;
}

float get_noise_interleaved_gradient(vec2 screen_pos)
{
    vec3 magic = vec3(0.06711056f, 0.00583715f, 52.9829189f);
    return fract(magic.z * fract(dot(screen_pos, magic.xy)));
}

float screen_fade(vec2 uv)
{
    vec2 fade = max(vec2(0.0f), 12.0f * abs(uv - 0.5f) - 5.0f);
    return clamp(1.0f - dot(fade, fade), 0.0, 1.0);
}


vec3 reconstruct_world_position(vec2 uv, float depth, mat4 inv_proj_matrix, mat4 inv_view_matrix) {
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);

	vec4 view = inv_proj_matrix * vec4(ndc, 1.0);
	view.xyz /= view.w;

	vec4 world = inv_view_matrix * inv_proj_matrix * vec4(ndc, 1.0);
	return world.xyz / world.w;
}


float screen_space_shadows(vec3 surface_view_position, mat4 proj_m, mat4 inv_proj_m, mat4 view, vec2 screen_uv, vec3 light)
{
	vec3 current_position_view_space = surface_view_position;
	/*
	vec3 light_dir = (inverse(view) * vec4(light, 0.0)).rbg;

	vec3 ray_dir = (view * vec4(light_dir, 0.0)).xyz;
	*/
	vec3 ray_dir = light;
	float g_sss_step_length = g_sss_ray_max_distance / float(g_sss_max_steps);
    vec3 ray_step = ray_dir * g_sss_step_length;

	vec2 current_screen_position = vec2(0.0);

	float depth_original = current_position_view_space.z;

	current_position_view_space +=  ray_step;

	vec2 old_screen_position = current_screen_position;

	float occlusion = 0.0;
	float not_valid_uv = 0.0;
    vec2 ray_uv_screen_pos   = vec2(0.0);

	vec3 resulting_color = vec3(-1.0);

	float depth = texture(depth_texture, screen_uv).x;
	float eps = 1e-6;
	float objectMask = (depth > eps && depth < 1.0 - eps) ? 1.0 : 0.0;

	float offset  = get_noise_interleaved_gradient(screen_uv);

	for(int travel= 0; travel < g_sss_max_steps; travel ++)
	{

		current_position_view_space += ray_step;

		current_screen_position = get_uv_from_view_position(current_position_view_space, proj_m);

		if(!is_within_screen_boundaries(current_screen_position)){
			return 1.0f;
		}

		float depth_texture_probe_raw = texture(depth_texture, current_screen_position).x;

		vec3 depth_texture_probe_view_position = get_view_position_from_uv(current_screen_position, depth_texture_probe_raw, inv_proj_m);

		float depth_diff = depth_texture_probe_view_position.z - current_position_view_space.z;

		bool can_the_camera_see_the_ray     = (depth_diff > g_sss_min_thickness) && (depth_diff < g_sss_thickness);
		bool occluded_by_the_original_pixel = abs( current_position_view_space.z - depth_original) < g_sss_max_delta_from_original_depth;

		if (can_the_camera_see_the_ray &&  occluded_by_the_original_pixel)
        {
			occlusion = 1.0;
			occlusion *= screen_fade(current_screen_position);
            break;
        }

	}

	return 1.-occlusion;
}

/*
void vertex() {
	//POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}
*/
void vertex(){
	camera_pos_world = CAMERA_POSITION_WORLD;
}

void fragment(){
	
	ALBEDO = texture(albedo_texture,UV).rgb;
}



void light() {
	bool is_directional = false;
	if(LIGHT_IS_DIRECTIONAL){
		is_directional = true;
	}

	float depth_center = texture(depth_texture, SCREEN_UV).x;

	vec3 surface_view_position 	= get_view_position_from_uv(SCREEN_UV, depth_center, INV_PROJECTION_MATRIX);

	vec4 worldSpacePosition = INV_VIEW_MATRIX * vec4(surface_view_position, 1.0);

	float sss = screen_space_shadows(surface_view_position,
	 PROJECTION_MATRIX,
	 INV_PROJECTION_MATRIX,
	 VIEW_MATRIX,
	 SCREEN_UV,
	 LIGHT);

	vec3 worldNormal = (INV_VIEW_MATRIX * vec4(NORMAL.xyz, 0.0)).xyz;

	vec3 light_dir = (INV_VIEW_MATRIX * vec4(LIGHT.xyz, 0.0)).rgb;

	float NdotL = dot(worldNormal, -light_dir);

	float lSmooth  = smoothstep(0, 0.05, NdotL);

	float lLerp = mix((1.0), (0.0), lSmooth);

	vec2 metallicUV = vec2(dot(worldNormal, normalize(normalize(camera_pos_world-worldSpacePosition.rgb) + light_dir)));

	/*
	vec3 toon_shadows = mix(shadow_color.rgb ,
	vec3(1.0) ,
	sss*lLerp)
	* LIGHT_COLOR/PI
	* ATTENUATION;
	*/
	/*
	vec3 metalliness = (mix( vec3(0.0) ,
	 vec3(texture(gradientMetallic,metallicUV).r) ,
	texture(lightmap_texture,UV).b));
	*/
	vec4 lm = texture(lightmap_texture, UV);
	float ao = lm.r;
	float aoSkinMask = lm.a;
	float roughness = lm.g;
	float metallic_mask = lm.b;

	float metallic_lookup = texture(gradientMetallic, metallicUV).r;
	float metallic = mix(0.0, metallic_lookup, metallic_mask);

	float aoao =mix(0.0,1.0, (ao + (aoSkinMask > 0.01?0.0:1.0)));

	vec3 toon_diffuse = mix(shadow_color.rgb * texture(albedo_texture,UV).rgb, vec3(1.0), sss * lLerp*aoao)
	                  * LIGHT_COLOR / PI ;

	vec3 V =  normalize(normalize(camera_pos_world-worldSpacePosition.rgb));
	vec3 L = normalize(light_dir);

	vec3 H = normalize(V + L);
	float spec = pow(max(dot(worldNormal, H), 0.0), 1.0 / max(1.0-roughness, 0.001));

	vec3 diffuse_part = toon_diffuse * (1.0 - metallic);
	vec3 specular_part = LIGHT_COLOR * spec * metallic;

	vec3 final_color = (diffuse_part + specular_part);

	if(is_directional){
		DIFFUSE_LIGHT = final_color;
	}
}