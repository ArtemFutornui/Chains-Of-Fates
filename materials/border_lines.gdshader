shader_type spatial;
render_mode unshaded,depth_test_disabled; // unshaded для збереження кольору, blend_mix для прозорості, depth_draw_never щоб було видно крізь інші об'єкти, cull_disabled для двосторонності (хоча лінії одномірні)

uniform vec4 line_color : source_color = vec4(1.0,0,0,1.0);
uniform float fade_start_distance = 500.0;
uniform float fade_end_distance = 800.0;

varying vec3 world_pos;

void vertex() {
	// Отримуємо світові координати поточної вершини
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    // Обчислюємо відстань від фрагмента до камери
    float distance_to_camera = distance(world_pos, CAMERA_POSITION_WORLD.xyz);

    // Обчислюємо альфа-значення для плавного зникнення
    float alpha = 1.0 - smoothstep(fade_start_distance, fade_end_distance, distance_to_camera);

    // Встановлюємо колір і альфа
    ALBEDO = line_color.rgb;
    ALPHA = line_color.a * alpha;

    // Якщо альфа дуже мала, відкидаємо фрагмент для оптимізації
    if (ALPHA < 0.01) {
        discard;
    }
}