shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
// Жирные мягкие лужи крови с рваным органическим краем и потёками.
// Мягкая альфа по краю вместо жёсткого discard — не пикселит на дистанции.
uniform float blood_clock = 0.0;
uniform float spread_seconds = 6.0;
varying vec2 point;
varying vec4 mark;

float hash(float x) { return fract(sin(x * 127.1 + 311.7) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 c = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(c);
	float b = hash2(c + vec2(1.0, 0.0));
	float d = hash2(c + vec2(0.0, 1.0));
	float e = hash2(c + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(d, e, f.x), f.y);
}
float fbm(vec2 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.3 + 7.1) * 0.3 + vnoise(p * 4.7 - 3.3) * 0.1;
}
vec2 turn(vec2 p, float a) { return vec2(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y); }

void vertex() {
	point = VERTEX.xz;              // ~[-1..1] в локальных координатах пятна
	mark = INSTANCE_CUSTOM;         // born, seed, kind, volume
}

void fragment() {
	float age = max(0.0, blood_clock - mark.r);
	float seed = mark.g * 83.0;
	float kind = mark.b;            // 0 укус, 1 смерть, 2 выстрел, 3 капля, 4 след ноги
	float volume = mark.a;
	vec2 p = point;

	// Рост пятна со временем (быстро проступает, потом стабильно).
	float speed = kind < 0.5 ? 1.2 : (kind < 1.5 ? 0.9 : (kind < 2.5 ? 1.0 : 1.6));
	float grow = clamp(age / (spread_seconds * speed * mix(0.6, 1.2, hash(seed))), 0.18, 1.0);

	float d;   // знаковое расстояние: >0 внутри лужи

	if (kind > 3.5) {
		// След ноги — вытянутый отпечаток.
		vec2 q = p * vec2(1.35, 0.85);
		d = (0.62 * grow) - length(q);
		d = max(d, (0.30 * grow) - length((p - vec2(0.0, 0.55)) * vec2(1.7, 1.4)));
	} else if (kind > 2.5) {
		// Капля с воздуха — маленький круглый шарик.
		float rr = mix(0.45, 0.85, volume) * grow;
		float warp = (fbm(p * 3.0 + seed) - 0.5) * 0.18;
		d = rr + warp - length(p);
	} else {
		// Жирная клякса: круглое ядро + рваный органический край.
		float core = mix(0.42, 0.92, volume) * grow;
		float warp = (fbm(p * 2.2 + seed) - 0.5) * 0.34
				   + (fbm(p * 5.5 - seed * 1.7) - 0.5) * 0.14;
		d = core + warp - length(p);

		// Потёки-лобы наружу (по 3-5 штук) — «языки» растёкшейся крови.
		int lobes = kind < 0.5 ? 3 : 5;
		for (int i = 0; i < 5; i++) {
			if (i >= lobes) { break; }
			float fi = float(i);
			float a = mix(-3.14159, 3.14159, hash(seed + fi * 13.7));
			float reach = mix(0.55, 1.15, hash(seed + fi * 7.1)) * grow;
			float wide = mix(0.14, 0.30, hash(seed + fi * 4.3));
			vec2 dir = vec2(cos(a), sin(a));
			float along = dot(p, dir);
			float across = length(p - dir * clamp(along, 0.0, reach));
			float lobe = (wide * (1.0 - clamp(along / max(reach, 0.001), 0.0, 1.0))) - across;
			// маленькая капля-голова на конце потёка
			float head = mix(0.10, 0.18, hash(seed + fi)) - length(p - dir * reach);
			d = max(d, max(lobe, head));
		}
	}

	// Мягкий сглаженный край (анти-алиасинг по производной).
	float aa = fwidth(length(p)) * 1.3 + 0.012;
	float alpha = smoothstep(-aa, aa, d);
	if (alpha < 0.02) { discard; }

	// Влажность/подсыхание.
	float grit = fbm(p * 40.0 + seed);
	float drying = clamp(age / 140.0, 0.0, 1.0);
	float depth = smoothstep(0.0, 0.5, d);   // центр темнее и толще
	vec3 wet = mix(vec3(0.28, 0.006, 0.012), vec3(0.06, 0.001, 0.004), depth);
	ALBEDO = wet * (0.92 + grit * 0.12) * mix(1.0, 0.62, drying);
	ROUGHNESS = mix(0.14, 0.62, drying) + (1.0 - depth) * 0.06;
	METALLIC = 0.0;
	SPECULAR = mix(0.85, 0.35, drying);      // свежая кровь блестит
	ALPHA = alpha;

	// Лёгкий рельеф: блик по влажной поверхности + зернистость.
	float sheen = (1.0 - drying) * 0.12;
	NORMAL_MAP = normalize(vec3((grit - 0.5) * 0.10, (fbm(p * 33.0 - seed) - 0.5) * 0.10, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = sheen + 0.3;
}
