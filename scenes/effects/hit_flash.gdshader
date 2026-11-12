// Hit flash (Issue #51 Stage 3): mixes the sprite towards `flash_color` by
// `flash_amount` (0 = unchanged), keeping its alpha. Lives on the sprite's own
// material, so modulate / self_modulate (telegraph, champion, phase and slow
// tints) are never touched. Driven by HitFeedback.flash().
// In a canvas_item fragment(), COLOR already holds the texture sample x
// modulate; sampling TEXTURE again would square the colours (a sprite darkened
// for good after its first hit, Issue #51 Stage 4 fix). At flash_amount 0 the
// output is exactly the unshaded sprite.
shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base = COLOR;
	COLOR = vec4(mix(base.rgb, flash_color.rgb, flash_amount), base.a);
}
