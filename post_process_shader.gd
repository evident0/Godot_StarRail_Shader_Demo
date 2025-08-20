@tool
class_name PostProcessShader
extends CompositorEffect

const template_shader := """#version 450

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;

// Our push constant.
// Must be aligned to 16 bytes, just like the push constant we passed from the script.
layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	vec2 pad;
} params;

float W_f(float x, float e0, float e1) {
	if (x <= e0)
		return 0.0;
	if (x >= e1)
		return 1.0;
	float a = (x - e0) / (e1 - e0);
	return a * a * (3.0 - 2.0 * a);
}

float H_f(float x, float e0, float e1) {
	if (x <= e0)
		return 0.0;
	if (x >= e1)
		return 1.0;
	return (x - e0) / (e1 - e0);
}

float GranTurismoTonemapper(float x) {
	float P = 1.0;
	float a = 1.0;
	float m = 0.22;
	float l = 0.4;
	float c = 1.33;
	float b = 0.0;
	float E = 2.718;

	float l0 = (P - m) * l / a;
	float L0 = m - m / a;
	float L1 = m + (1.0 - m) / a;

	float L_x = m + a * (x - m);
	float T_x = m * pow(x / m, c) + b;

	float S0 = m + l0;
	float S1 = m + a * l0;
	float C2 = a * P / (P - S1);
	float S_x = P - (P - S1) * pow(E, -(C2 * (x - S0) / P));

	float w0_x = 1.0 - W_f(x, 0.0, m);
	float w2_x = H_f(x, m + l0, m + l0);
	float w1_x = 1.0 - w0_x - w2_x;

	float f_x = T_x * w0_x + L_x * w1_x + S_x * w2_x;
	return f_x;
}


// The code we want to execute in each invocation.
void main() {
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.raster_size);

	if (uv.x >= size.x || uv.y >= size.y) {
		return;
	}

	vec4 color = imageLoad(color_image, uv);
	
	float rGT = GranTurismoTonemapper(color.r);
	float gGT = GranTurismoTonemapper(color.g);
	float bGT = GranTurismoTonemapper(color.b);
	
	

	#COMPUTE_CODE

	imageStore(color_image, uv, color);
}"""

@export_multiline var shader_code := "":
	set(value):
		mutex.lock()
		shader_code = value
		shader_is_dirty = true
		mutex.unlock()

var rd: RenderingDevice
var shader: RID
var pipeline: RID

var mutex := Mutex.new()
var shader_is_dirty := true


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	rd = RenderingServer.get_rendering_device()


# System notifications, we want to react on the notification that
# alerts us we are about to be destroyed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if shader.is_valid():
			# Freeing our shader will also free any dependents such as the pipeline!
			rd.free_rid(shader)


#region Code in this region runs on the rendering thread.
# Check if our shader has changed and needs to be recompiled.
func _check_shader() -> bool:
	if not rd:
		return false

	var new_shader_code := ""

	# Check if our shader is dirty.
	mutex.lock()
	if shader_is_dirty:
		new_shader_code = shader_code
		shader_is_dirty = false
	mutex.unlock()

	# We don't have a (new) shader?
	if new_shader_code.is_empty():
		return pipeline.is_valid()

	# Apply template.
	new_shader_code = template_shader.replace("#COMPUTE_CODE", new_shader_code);

	# Out with the old.
	if shader.is_valid():
		rd.free_rid(shader)
		shader = RID()
		pipeline = RID()

	# In with the new.
	var shader_source := RDShaderSource.new()
	shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	shader_source.source_compute = new_shader_code
	var shader_spirv : RDShaderSPIRV = rd.shader_compile_spirv_from_source(shader_source)

	if shader_spirv.compile_error_compute != "":
		push_error(shader_spirv.compile_error_compute)
		push_error("In: " + new_shader_code)
		return false

	shader = rd.shader_create_from_spirv(shader_spirv)
	if not shader.is_valid():
		return false

	pipeline = rd.compute_pipeline_create(shader)

	return pipeline.is_valid()


# Called by the rendering thread every frame.
func _render_callback(p_effect_callback_type: EffectCallbackType, p_render_data: RenderData) -> void:
	if rd and p_effect_callback_type == EFFECT_CALLBACK_TYPE_POST_TRANSPARENT and _check_shader():
		# Get our render scene buffers object, this gives us access to our render buffers.
		# Note that implementation differs per renderer hence the need for the cast.
		var render_scene_buffers := p_render_data.get_render_scene_buffers()
		if render_scene_buffers:
			# Get our render size, this is the 3D render resolution!
			var size: Vector2i = render_scene_buffers.get_internal_size()
			if size.x == 0 and size.y == 0:
				return

			# We can use a compute shader here.
			@warning_ignore("integer_division")
			var x_groups := (size.x - 1) / 8 + 1
			@warning_ignore("integer_division")
			var y_groups := (size.y - 1) / 8 + 1
			var z_groups := 1

			# Create push constant.
			# Must be aligned to 16 bytes and be in the same order as defined in the shader.
			var push_constant := PackedFloat32Array([
				size.x,
				size.y,
				0.0,
				0.0,
			])

			# Loop through views just in case we're doing stereo rendering. No extra cost if this is mono.
			var view_count: int = render_scene_buffers.get_view_count()
			for view in view_count:
				# Get the RID for our color image, we will be reading from and writing to it.
				var input_image: RID = render_scene_buffers.get_color_layer(view)

				# Create a uniform set, this will be cached, the cache will be cleared if our viewports configuration is changed.
				var uniform := RDUniform.new()
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
				uniform.binding = 0
				uniform.add_id(input_image)
				var uniform_set := UniformSetCacheRD.get_cache(shader, 0, [uniform])

				# Run our compute shader.
				var compute_list := rd.compute_list_begin()
				rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
				rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
				rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
				rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
				rd.compute_list_end()
#endregion
