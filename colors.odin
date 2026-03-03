package sdrl

import "core:math/rand"
import rl "vendor:raylib"

// inspired from brogue's color dancing
Color_Range :: struct {
	r, g, b:             u8, // base color
	r_var, g_var, b_var: u8, // per-channel random variance
	uniform_var:         u8, // brighness variance (all channels equally)
	dances:              bool, // true = re-roll eery frame, false = sample once
}

sample_color :: proc(cr: Color_Range) -> rl.Color {
	r_offset := cr.r_var > 0 ? u8(rand.int_max(int(cr.r_var) + 1)) : 0
	g_offset := cr.g_var > 0 ? u8(rand.int_max(int(cr.g_var) + 1)) : 0
	b_offset := cr.b_var > 0 ? u8(rand.int_max(int(cr.b_var) + 1)) : 0
	uniform := cr.uniform_var > 0 ? u8(rand.int_max(int(cr.uniform_var) + 1)) : 0

	r := min(u16(cr.r) + u16(r_offset) + u16(uniform), 255)
	g := min(u16(cr.g) + u16(g_offset) + u16(uniform), 255)
	b := min(u16(cr.b) + u16(b_offset) + u16(uniform), 255)

	return rl.Color{u8(r), u8(g), u8(b), 255}
}

// ===== ENVIRONMENT =====
// Dark blue-grey walls, subtle per-tile variation, static
WALL_COLOR :: Color_Range{16, 40, 80, 5, 5, 12, 4, false}
WALL_ACCENT :: Color_Range{45, 80, 145, 8, 8, 15, 6, false}

// Near-black navy floors, very subtle variation
FLOOR_COLOR :: Color_Range{9, 20, 45, 2, 3, 6, 2, false}
FLOOR_ACCENT :: Color_Range{15, 30, 58, 3, 4, 8, 3, false}

// Cool blue-cyan, gentle shimmer
WATER :: Color_Range{15, 100, 140, 5, 15, 20, 8, true}

// Bright warm gold, slight dancing to catch the eye
STAIRS :: Color_Range{230, 200, 100, 10, 10, 5, 15, true}

// Fog of war — flat, no variance
FOG :: Color_Range{8, 12, 25, 0, 0, 0, 0, false}

// ===== LIGHTING =====
// Warm flickering lantern — the player's primary light source
LANTERN_LIGHT_COLOR :: Color_Range{245, 160, 55, 20, 15, 8, 10, true}

// ===== ENTITIES =====
// Cyan-tinted, minimal variance — player is the visual anchor
PLAYER :: Color_Range{10, 195, 205, 5, 8, 8, 5, false}

// ===== ENEMIES =====
THRALL_COLOR :: Color_Range{220, 130, 45, 8, 5, 5, 3, false} // burnt amber
WOLF_COLOR :: Color_Range{140, 150, 175, 5, 5, 8, 3, false} // steel grey-blue
SHADE_COLOR :: Color_Range{60, 20, 80, 10, 5, 12, 8, true} // dim purple,
//  dances
PEST_COLOR :: Color_Range{160, 230, 30, 8, 10, 5, 6, true} // acid
//  chartreuse, dances
KNIGHT_COLOR :: Color_Range{190, 200, 220, 5, 5, 8, 4, false} // pale bone-blue
WRAITH_COLOR :: Color_Range{192, 1, 181, 20, 0, 15, 12, true} // pulsing
//  magenta, dances
BOSS_COLOR :: Color_Range{120, 0, 20, 15, 0, 5, 8, true} // deep blood,

// ===== STANDARD & DEFAULT COLORS =====
LIGHT_NONE :: rl.Color{0, 0, 0, 255} // Darkness
AMBIENT_LIGHT :: rl.Color{90, 90, 100, 255}

// ===== UI COLORS =====
UI_BG :: rl.Color{20, 20, 25, 255}
UI_TEXT :: rl.Color{220, 220, 220, 255}
UI_HIGHLIGHT :: rl.Color{255, 215, 0, 255}

add_light :: proc(existing: rl.Color, new_light: rl.Color) -> rl.Color {
	return rl.Color {
		min(u8(int(existing.r) + int(new_light.r)), 255),
		min(u8(int(existing.g) + int(new_light.g)), 255),
		min(u8(int(existing.b) + int(new_light.b)), 255),
		255,
	}
	// TODO debug text, check if colors are saturating (hitting 255) or wrapping over
}

is_dark :: proc(c: rl.Color) -> bool {
	return c.r < 10 && c.g < 10 && c.b < 10
}

apply_lighting :: proc(base: rl.Color, light: rl.Color) -> rl.Color {
	r := (f32(base.r) / 255.0) * (f32(light.r) / 255.0) * 255.0
	g := (f32(base.g) / 255.0) * (f32(light.g) / 255.0) * 255.0
	b := (f32(base.b) / 255.0) * (f32(light.b) / 255.0) * 255.0
	return rl.Color{u8(r), u8(g), u8(b), base.a}
}

dim_color :: proc(base: rl.Color, intensity: f32) -> rl.Color {
	factor := clamp(intensity, 0.0, 1.0)
	return rl.Color {
		u8(f32(base.r) * factor),
		u8(f32(base.g) * factor),
		u8(f32(base.b) * factor),
		base.a,
	}
}
