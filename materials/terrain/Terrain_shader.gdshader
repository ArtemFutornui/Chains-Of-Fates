shader_type spatial;
render_mode cull_back, diffuse_toon;

uniform sampler2D gradient_texture; // Градієнтна текстура для зміни кольору
uniform sampler2D noise_texture;    // Текстура шуму (FastNoiseLite)

uniform float min_height = -1;      // Мінімальна висота
uniform float max_height = 256;     // Максимальна висота
uniform float noise_scale = 0.001;    // Масштаб для координат шуму
uniform vec4 color_dirt: source_color = vec4(0.15,0.15,0.15,1.0);
uniform float from_dirt = 0.5;
uniform float to_grass = 0.9;
uniform float dirt_max_height = 50.0;

varying vec3 world_pos;

void vertex() {
    //world_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

}

void fragment() {
    // Нормалізуємо висоту від 0 до 1
    float height_factor = clamp((world_pos.y - min_height) / (max_height - min_height), 0.0, 1.0);

    // Отримуємо колір із градієнта
    vec4 gradient_color = texture(gradient_texture, vec2(height_factor, 0.5));

    // Масштабуємо координати для шуму так, щоб вся мапа була однією клітинкою для шуму
    // Використовуємо глобальні координати world_pos.xz, щоб охопити всю територію
    vec2 noise_coords = world_pos.xz * noise_scale * 0.1; // Масштаб для координат шуму
    float noise_value = texture(noise_texture, noise_coords).r; // Отримуємо значення шуму
    // Впливаємо на світлість за допомогою шуму
    float light_factor = (noise_value * 0.5 + 0.5); // Варіація світлості
    light_factor = pow(light_factor, 3.0); // М'якші переходи

    // Модифікуємо колір з урахуванням шуму
    //vec3 final_color = gradient_color.rgb * light_factor;

	vec3 normal_local = NORMAL;
	vec3 transformed_normal = (INV_VIEW_MATRIX*vec4(normal_local, 0.0)).xyz;
	vec3 up = vec3(0.0, 1.0, 0.0);
	float dot_product = dot(transformed_normal, up);

	float t = smoothstep(from_dirt, to_grass, dot_product);
	vec3 final_color = mix(color_dirt.rgb, gradient_color.rgb,t) * light_factor;
	//vec2 uv = world_pos.xz;

	//if(dot_product > dirt_threshold){
		//final_color = gradient_color.rgb * light_factor;
	//} else{
		//if(dot_product >dirt_threshold2){
			//final_color = mix(gradient_color.rgb, color_dirt.rgb,dot_product-0.5) * light_factor;
		//}else{
			//final_color = color_dirt.rgb * light_factor;
		//}
	//}



    // Додаємо ефект освітлення
    vec3 light_direction = normalize(vec3(1.0, 1.0, 1.0)); // Напрямок світла
    float light_intensity = max(dot(normalize(NORMAL), light_direction), 0.0);


    // Розраховуємо фінальний колір з урахуванням освітлення
    ALBEDO = final_color * (0.5 + light_intensity * 0.5);
}
