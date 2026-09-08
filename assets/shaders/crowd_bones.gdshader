shader_type spatial;
render_mode cull_back;
uniform sampler2D bone_texture : filter_nearest, repeat_disable;
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform int bone_count = 17;
varying vec3 instance_tint;

mat4 bone_at(int bone, int frame) {
	vec4 a = texelFetch(bone_texture, ivec2(bone * 3, frame), 0);
	vec4 b = texelFetch(bone_texture, ivec2(bone * 3 + 1, frame), 0);
	vec4 c = texelFetch(bone_texture, ivec2(bone * 3 + 2, frame), 0);
	return mat4(vec4(a.x, b.x, c.x, 0.0), vec4(a.y, b.y, c.y, 0.0),
		vec4(a.z, b.z, c.z, 0.0), vec4(a.w, b.w, c.w, 1.0));
}

mat4 sample_pose(int bone, float frame) {
	mat4 first = bone_at(bone, int(floor(frame)));
	mat4 second = bone_at(bone, int(ceil(frame)));
	return first * (1.0 - fract(frame)) + second * fract(frame);
}

void vertex() {
	int bone = clamp(int(floor(UV2.x * float(bone_count))), 0, bone_count - 1);
	mat4 current = sample_pose(bone, INSTANCE_CUSTOM.r);
	mat4 previous = sample_pose(bone, INSTANCE_CUSTOM.g);
	mat4 pose = previous * (1.0 - INSTANCE_CUSTOM.b) + current * INSTANCE_CUSTOM.b;
	VERTEX = (pose * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(mat3(pose) * NORMAL);
	instance_tint = COLOR.rgb;
}

void fragment() {
	ALBEDO = texture(palette, UV).rgb * instance_tint;
	ROUGHNESS = 0.86;
}
