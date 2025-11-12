shader_type spatial;
render_mode cull_back, diffuse_toon;

uniform sampler2D noise_texture;    // Текстура шуму (FastNoiseLite)
uniform float noise_scale = 0.001;    // Масштаб для координат шуму

uniform sampler2D sand_texture;     // Текстура для трави
uniform sampler2D dirt_texture;      // Текстура для бруду/землі
uniform sampler2D grass_texture;     // Текстура для трави

uniform vec4 sand_tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);  // Колірний відтінок для піску
uniform vec4 grass_tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // Колірний відтінок для трави
uniform vec4 dirt_tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);  // Колірний відтінок для землі

uniform float min_height = -1;      // Мінімальна висота
uniform float max_height = 256;     // Максимальна висота
uniform float from_dirt = 0.5;
uniform float to_grass = 0.9;
uniform float sand_height_start = 0.0;
uniform float sand_height_end = 0.2;

uniform float uv_scale = 0.1;

varying vec3 world_pos;

vec4 hash4( vec2 p ) { return fract(sin(vec4( 1.0+dot(p,vec2(37.0,17.0)),
                                              2.0+dot(p,vec2(11.0,47.0)),
                                              3.0+dot(p,vec2(41.0,29.0)),
                                              4.0+dot(p,vec2(23.0,31.0))))*103.0); }

vec4 textureNoTile( sampler2D samp, in vec2 uv )
{
    vec2 iuv = floor( uv );
    vec2 fuv = fract( uv );

    vec4 ofa = hash4( iuv + vec2(0.0,0.0) );
    vec4 ofb = hash4( iuv + vec2(1.0,0.0) );
    vec4 ofc = hash4( iuv + vec2(0.0,1.0) );
    vec4 ofd = hash4( iuv + vec2(1.0,1.0) );

    vec2 ddx = dFdx( uv );
    vec2 ddy = dFdy( uv );

    // transform per-tile uvs
    ofa.zw = sign(ofa.zw-0.5);
    ofb.zw = sign(ofb.zw-0.5);
    ofc.zw = sign(ofc.zw-0.5);
    ofd.zw = sign(ofd.zw-0.5);

    // uv's, and derivarives (for correct mipmapping)
    vec2 uva = uv*ofa.zw + ofa.xy; vec2 ddxa = ddx*ofa.zw; vec2 ddya = ddy*ofa.zw;
    vec2 uvb = uv*ofb.zw + ofb.xy; vec2 ddxb = ddx*ofb.zw; vec2 ddyb = ddy*ofb.zw;
    vec2 uvc = uv*ofc.zw + ofc.xy; vec2 ddxc = ddx*ofc.zw; vec2 ddyc = ddy*ofc.zw;
    vec2 uvd = uv*ofd.zw + ofd.xy; vec2 ddxd = ddx*ofd.zw; vec2 ddyd = ddy*ofd.zw;

    // fetch and blend
    vec2 b = smoothstep(0.25,0.75,fuv);

    return mix( mix( textureGrad( samp, uva, ddxa, ddya ),
                     textureGrad( samp, uvb, ddxb, ddyb ), b.x ),
                mix( textureGrad( samp, uvc, ddxc, ddyc ),
                     textureGrad( samp, uvd, ddxd, ddyd ), b.x), b.y );
}

void vertex() {
    //world_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

}

void fragment() {
    // Нормалізуємо висоту від 0 до 1
    float height_factor = clamp((world_pos.y - min_height) / (max_height - min_height), 0.0, 1.0);

    // Масштабуємо координати для шуму так, щоб вся мапа була однією клітинкою для шуму
    // Використовуємо глобальні координати world_pos.xz, щоб охопити всю територію
    vec2 noise_coords = world_pos.xz * noise_scale * 0.1; // Масштаб для координат шуму
    float noise_value = texture(noise_texture, noise_coords).r; // Отримуємо значення шуму
    // Впливаємо на світлість за допомогою шуму
    float light_factor = (noise_value * 0.5 + 0.5); // Варіація світлості
    light_factor = pow(light_factor, 3.0); // М'якші переходи

    vec2 uv = world_pos.xz * uv_scale; // Координати для тайлінгу текстур. Можете налаштувати 0.1 під свій розмір.
	// Отримуємо кольори з текстур
    vec3 dirt_color = textureNoTile(dirt_texture, uv).rgb * dirt_tint_color.rgb;
    vec3 grass_color = textureNoTile(grass_texture, uv).rgb * grass_tint_color.rgb;
    vec3 sand_color = textureNoTile(sand_texture, uv).rgb * sand_tint_color.rgb;


	vec3 normal_local = NORMAL;
	vec3 transformed_normal = (INV_VIEW_MATRIX*vec4(normal_local, 0.0)).xyz;
	vec3 up = vec3(0.0, 1.0, 0.0);
	float dot_product = dot(transformed_normal, up);

	float height_blend = smoothstep(sand_height_start, sand_height_end, height_factor);
    vec3 mixed_by_height_color = mix(sand_color, grass_color, height_blend);

	float slope_blend = smoothstep(from_dirt, to_grass, dot_product); // Це більше для "низьких" схилів
	vec3 final_albedo_color = mix(dirt_color, mixed_by_height_color, slope_blend);

	// Застосовуємо шум для варіації світлості
    final_albedo_color *= light_factor;

    // Додаємо ефект освітлення
    vec3 light_direction = normalize(vec3(1.0, 1.0, 1.0)); // Напрямок світла
    float light_intensity = max(dot(normalize(NORMAL), light_direction), 0.0);


    // Розраховуємо фінальний колір з урахуванням освітлення
    ALBEDO = final_albedo_color * (0.5 + light_intensity * 0.5);
}
