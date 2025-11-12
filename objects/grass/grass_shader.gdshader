shader_type spatial;
render_mode cull_disabled,diffuse_toon,depth_draw_always;

//uniform vec3 chunk_position;
uniform vec3 color: source_color = vec3(0.093, 0.442, 0.129);
uniform vec3 color2: source_color = vec3(0.103,0.267,0.11);
uniform sampler2D noise_texture;
uniform sampler2D wind_texture;
uniform float noise_scale = 0.001;    // Масштаб для координат шуму
//uniform float tilt = 4.0;
uniform float fade_start = 128.0;
uniform float fade_end = 512.0;
//parameters for waving
uniform float wind_strength = 0.1;
uniform float wind_scale = 0.05; // масштаб вітрового шуму
uniform float wind_speed = 0.05; // швидкість "руху" вітру
uniform float amplitude_variation = 0.7; // від 0 до 1
uniform float noise_power = 1.5; // підсилює контраст шуму
uniform float randomness_rotation = 1.0;
uniform vec2 wind_direction = vec2(1.0, 0.5); // нормалізований напрямок

varying vec3 world_pos;

void vertex(){
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // Обчислюємо коефіцієнт впливу: 1.0 - uv.y
    //float strength = 1.0 - UV.y;
	//VERTEX += strength/tilt;

	// Випадковий поворот
	vec2 noise_uv = world_pos.xz * 0.01;
	float rand = texture(wind_texture, noise_uv).r;
	// Кут повороту від 0 до 2π
	float angle = rand * 6.2831 * randomness_rotation; // 2π
	// Розрахунок повороту у XZ-площині
	float cos_a = cos(angle);
	float sin_a = sin(angle);

	// Повертаємо травинку навколо Y (до згину)
	float x = VERTEX.x;
	float z = VERTEX.z;
	VERTEX.x = x * cos_a - z * sin_a;
	VERTEX.z = x * sin_a + z * cos_a;

	float dist = distance(CAMERA_POSITION_WORLD, world_pos);
	if (dist <= fade_start) {

		// Локальні координати, щоб гнути лише верхні частини травинки
		float bend_factor = 1.0 - UV.y;
		//float wind_angle = sin(TIME * 0.01) * 3.14159;
		//vec2 wind_direction_dynamic = vec2(cos(wind_angle), sin(wind_angle));
		// Рух шуму в напрямку вітру
		vec2 shifted_uv = world_pos.xz * wind_scale;

		// Зсув координат у напрямку вітру по часу
		shifted_uv -= normalize(wind_direction) * TIME * wind_speed;
		float wind_noise = texture(wind_texture, shifted_uv).r;
		// варіація амплітуди — деякі майже не гнуться, інші більше
		float noise_amp = pow(wind_noise, noise_power); // робить контрастнішим
		noise_amp = mix(1.0 - amplitude_variation, 1.0, noise_amp); // зміщення між слабким і сильним вітром
		float wind_wave = wind_noise * wind_strength;

		vec2 bend_dir = normalize(wind_direction);
		VERTEX.x += bend_dir.x * wind_wave * bend_factor*noise_amp;
		VERTEX.z += bend_dir.y * wind_wave * bend_factor*noise_amp;
	}
}



void fragment() {
    float dist = distance(CAMERA_POSITION_WORLD, world_pos);
    float alpha = clamp((fade_end - dist) / (fade_end - fade_start), 0.0, 1.0);

	vec2 noise_coords = world_pos.xz * noise_scale * 0.1; // Масштаб для координат шуму
    float noise_value = texture(noise_texture, noise_coords).r; // Отримуємо значення шуму
	float light_factor = (noise_value * 0.5 + 0.5); // Варіація світлості
    light_factor = pow(light_factor, 3.0); // М'якші переходи

	vec3 noised_color = color * light_factor;
	vec3 noised_color2 = color2 * light_factor;

	float weight = 1.0 - UV.y;
	vec3 final_color = mix(noised_color2, noised_color, weight);
	NORMAL = vec3(0,1,0);
	NORMAL_MAP = vec3(0.5,1,0.5);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
    ALBEDO = final_color;
    ALPHA = alpha;
}