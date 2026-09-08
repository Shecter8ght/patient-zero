shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, shadows_disabled, unshaded;
// Декаль-брызга: сэмплим реальную текстуру крови, подкрашиваем, подсыхаем.
// Форма и детали — из текстуры (разные + поворот/масштаб/зеркало), поэтому
// пятна не выглядят одинаковыми процедурными блобами.
uniform sampler2D splat : source_color, filter_linear_mipmap;
uniform float blood_clock = 0.0;
varying vec4 mark;   // born, seed, _, volume

void vertex() {
	mark = INSTANCE_CUSTOM;
}

void fragment() {
	vec4 t = texture(splat, UV);
	float a = t.a;
	if (a < 0.03) { discard; }

	float age = max(0.0, blood_clock - mark.r);
	float seed = mark.g;

	// Быстрое проступание (не «поп»), потом стабильно.
	float appear = smoothstep(0.0, 0.35, age);

	// Тонировка в кровь: тёмно-красное ядро, чуть варьируем оттенок по seed.
	vec3 base = t.rgb;
	float lum = dot(base, vec3(0.4, 0.35, 0.25));
	vec3 blood = vec3(0.36, 0.02, 0.02) * (0.55 + lum * 1.1);
	blood *= mix(0.9, 1.12, fract(seed * 7.0));   // разброс яркости

	// Подсыхание: темнеет и буреет со временем.
	float drying = clamp(age / 160.0, 0.0, 1.0);
	blood = mix(blood, blood * vec3(0.5, 0.42, 0.35), drying);

	ALBEDO = blood;
	ALPHA = a * appear * mix(1.0, 0.9, drying);
	// Влажный блик у свежей крови (эмиссия-подсветка вместо спекуляра в unshaded).
	EMISSION = blood * (1.0 - drying) * 0.12;
}
