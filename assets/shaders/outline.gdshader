shader_type canvas_item;
render_mode blend_mix;

// ============================================================================
// 卡通描边 + 提饱和
// ----------------------------------------------------------------------------
// 做两件事：
//   1. 给实体加一圈深色外轮廓，把它从地表里"抠"出来
//   2. 顺手把贴图饱和度提一点，让整屏颜色更像手绘而不是照片
//
// 为什么用邻域 alpha 采样而不是复制四份偏移绘制：
//   偏移绘制要把每个精灵画 5 次（上下左右 + 本体），四十个单位加地物之后
//   绘制调用直接翻五倍。这里只是一次 pass 里的 8 次纹理采样，代价小得多。
//
// 宽度为什么用 TEXTURE_PIXEL_SIZE 归一化：
//   同一份材质要套在 52x43 的干员和 38x36 的坦克上。若按贴图像素给固定宽度，
//   小贴图的描边会粗得糊成一团。归一化之后所有实体的描边视觉宽度一致，
//   于是全局只需要一个 ShaderMaterial 实例。
//
// 前提：贴图四周必须留出透明边。描边只在精灵四边形范围内采样，
// 紧裁贴图（内容顶到画布边缘）的外轮廓会被裁掉 —— 由 AssetDB 统一补边。
// ============================================================================

uniform vec4 outline_color : source_color = vec4(0.141, 0.102, 0.071, 1.0);
uniform float outline_width : hint_range(0.0, 6.0) = 1.55;
uniform float saturate_mul : hint_range(0.0, 2.5) = 1.24;
// alpha 低于这个值、且邻近存在实体的像素，判为轮廓
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.34;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec4 tint = COLOR;   // 顶点色 x modulate

	// 8 向取最大 alpha：判断"我旁边有没有实体"
	float nb = 0.0;
	for (int i = 0; i < 8; i++) {
		float ang = float(i) * 0.7853981634;
		vec2 off = vec2(cos(ang), sin(ang)) * outline_width * TEXTURE_PIXEL_SIZE;
		nb = max(nb, texture(TEXTURE, UV + off).a);
	}

	vec3 rgb = base.rgb;
	float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
	rgb = mix(vec3(lum), rgb, saturate_mul);

	if (base.a < alpha_cut && nb > 0.5) {
		COLOR = vec4(outline_color.rgb * tint.rgb, outline_color.a * tint.a);
	} else {
		COLOR = vec4(clamp(rgb, 0.0, 1.0) * tint.rgb, base.a * tint.a);
	}
}
