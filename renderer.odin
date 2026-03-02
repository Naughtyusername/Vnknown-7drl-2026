package sdrl

import "core:fmt"
import rl "vendor:raylib"

draw_map :: proc(game: ^Game) {
	min_x, min_y, max_x, max_y := get_viewport_bounds(game.camera)

	min_x = max(0, min_x)
	min_y = max(0, min_y)
	max_x = min(game.map_width, max_x)
	max_y = min(game.map_height, max_y)

	for world_y in min_y ..< max_y {
		for world_x in min_x ..< max_x {
			if !game.revealed[world_y][world_x] {
				continue
			}

			screen_x, screen_y, _ := world_to_screen(game.camera, world_x, world_y)

			rect := rl.Rectangle {
				f32(screen_x * TILE_SIZE),
				f32(screen_y * TILE_SIZE + MAP_AREA_Y),
				TILE_SIZE,
				TILE_SIZE,
			}

			base_color: rl.Color
			#partial switch game.tiles[world_y][world_x] {
			case .Wall:
				base_color = sample_color(WALL_COLOR)
				if game.visible[world_y][world_x] {
					light_color := game.light_map[world_y][world_x]
					if is_dark(light_color) {
						light_color = AMBIENT_LIGHT
					}
					accent := apply_lighting(sample_color(WALL_ACCENT), light_color)
					rl.DrawRectangleLinesEx(rect, 1, accent)
				}
			case .Water:
				base_color = sample_color(WATER)
			case .Floor:
				base_color = sample_color(FLOOR_COLOR)
			case .Stairs_Down:
				base_color = sample_color(FLOOR_COLOR)
			// TODO
			}

			if game.visible[world_y][world_x] {
				light_color := game.light_map[world_y][world_x]
				if is_dark(light_color) {
					light_color = AMBIENT_LIGHT
				}
				tile_base_color := base_color
				base_color = apply_lighting(tile_base_color, light_color)
			} else {
				base_color.r /= 4
				base_color.g /= 4
				base_color.b /= 4
			}

			rl.DrawRectangleRec(rect, base_color)

			// Detailing draws
			#partial switch game.tiles[world_y][world_x] {
			case .Floor:
				if game.visible[world_y][world_x] {
					light_color := game.light_map[world_y][world_x]
					if is_dark(light_color) {
						light_color = AMBIENT_LIGHT
					}
					accent := apply_lighting(sample_color(FLOOR_ACCENT), light_color)
					rl.DrawCircle(
						i32(rect.x + TILE_SIZE / 2),
						i32(rect.y + TILE_SIZE / 2),
						2,
						accent,
					)
				}
			case .Wall:
				if game.visible[world_y][world_x] {
					light_color := game.light_map[world_y][world_x]
					if is_dark(light_color) {
						light_color = AMBIENT_LIGHT
					}
					accent := apply_lighting(sample_color(WALL_ACCENT), light_color)
					rl.DrawText("#", i32(rect.x + 4), i32(rect.y + 2), 20, accent)
				}
			case .Water:

			case .Stairs_Down:
				if game.visible[world_y][world_x] {
					light_color := game.light_map[world_y][world_x]
					if is_dark(light_color) {
						light_color = AMBIENT_LIGHT
					}
					stair_color := apply_lighting(rl.WHITE, light_color)
					rl.DrawText(">", i32(rect.x + 4), i32(rect.y + 2), 20, stair_color)
				}
			}
		}
	}
}

draw_player :: proc(game: ^Game) {
	player := get_player(game)
	screen_x, screen_y, visible := world_to_screen(game.camera, player.x, player.y)

	if visible {
		if data, ok := player.data.(Player_Data); ok {
			rl.DrawText(
				"@",
				i32(screen_x * TILE_SIZE + 4),
				i32(screen_y * TILE_SIZE + MAP_AREA_Y + 2),
				20,
				data.color,
			)
		}
	}
}

draw_game :: proc(sm: ^State_Manager) {
	if len(sm.stack) == 0 {
		return
	}

	// Find the lowest opaque state — draw layers from there upward
	start_index: int = 0
	for i := len(sm.stack) - 1; i >= 0; i -= 1 {
		if !sm.stack[i].is_transparent {
			start_index = i
			break
		}
	}

	for i in start_index ..< len(sm.stack) {
		sm.stack[i].draw(sm, sm.stack[i].data)
	}
}

draw_enemies :: proc(game: ^Game) {
	for &actor in game.actors {
		if data, ok := actor.data.(Enemy_Data); ok {
			if game.visible[actor.y][actor.x] {
				screen_x, screen_y, in_view := world_to_screen(game.camera, actor.x, actor.y)
				if in_view {
					rl.DrawText(
						data.char,
						i32(screen_x * TILE_SIZE + 4),
						i32(screen_y * TILE_SIZE + MAP_AREA_Y + 2),
						20,
						data.color,
					)
				}
			}
		}
	}
}

draw_debug_info :: proc(game: ^Game) {
	player := get_player(game)

	y: i32 = i32(MAP_AREA_Y) + 10
	font_size: i32 = 20
	spacing: i32 = (font_size - 2)

	rl.DrawText(rl.TextFormat("Player: (%d, %d)", player.x, player.y), 10, y, font_size, rl.WHITE)
	y += spacing
	rl.DrawText(rl.TextFormat("Turn: %d", game.turn_count), 10, y, font_size, rl.WHITE)
	y += spacing
	// TODO: verify time tracks correctly — player acts at 5 TU, 20 moves per turn increment
	rl.DrawText(rl.TextFormat("Time: %d", game.current_time), 10, y, font_size, rl.WHITE)
	y += spacing
	rl.DrawText(rl.TextFormat("Actors: %d", len(game.actors)), 10, y, font_size, rl.WHITE)
	y += spacing
	rl.DrawText(
		rl.TextFormat("Scheduled: %d", len(game.scheduler.actors)),
		10,
		y,
		font_size,
		rl.WHITE,
	)
	y += spacing
	rl.DrawText(rl.TextFormat("Real Time: %f", rl.GetTime()), 10, y, font_size, rl.WHITE)
	y += spacing
	rl.DrawText(rl.TextFormat("Current Floor #%d", game.current_floor), 10, y, font_size, rl.WHITE)
	y += spacing

	if draw_light_debug_overlay {
		draw_light_debug(game)
	}
}

render_message_overlay :: proc(game: ^Game) {
	msgs := game.game_log.messages
	count := min(5, len(msgs))

	if count == 0 {return}

	start := len(msgs) - count
	line := 0

	for i in 0 ..< count {
		msg := msgs[start + i]

		age := rl.GetTime() - msg.timestamp
		alpha := i32(255) - i32(age * 40)
		if alpha <= 0 {continue}
		if alpha > 255 {alpha = 255}

		y := i32(SCREEN_H) - 25 - i32((count - 1 - line) * 20)
		x: i32 = 0

		rl.DrawRectangle(0, y - 2, SCREEN_W, 20, rl.Color{0, 0, 0, u8(alpha / 2)})
		rl.DrawText(
			fmt.ctprintf("%s", msg.text),
			x,
			y,
			16,
			rl.Color{msg.color.r, msg.color.g, msg.color.b, u8(alpha)},
		)
		line += 1
	}
}

// Overlay showing octant overlap counts — diagnoses the "psychedelic bug"
// from shadowcasting. Tiles with hit_count > 1 have octant overlap.
draw_light_debug :: proc(game: ^Game) {
	when ODIN_DEBUG {
		min_x, min_y, max_x, max_y := get_viewport_bounds(game.camera)
		min_x = max(0, min_x)
		min_y = max(0, min_y)
		max_x = min(game.map_width, max_x)
		max_y = min(game.map_height, max_y)

		for world_y in min_y ..< max_y {
			for world_x in min_x ..< max_x {
				if !game.visible[world_y][world_x] {continue}

				hit_count := game.light_hit_count[world_y][world_x]
				if hit_count > 1 {
					screen_x, screen_y, _ := world_to_screen(game.camera, world_x, world_y)
					rl.DrawText(
						rl.TextFormat("%d", hit_count),
						i32(screen_x * TILE_SIZE + 12),
						i32(screen_y * TILE_SIZE + MAP_AREA_Y + 12),
						10,
						rl.YELLOW,
					)
				}
			}
		}
	}
}

draw_log_column :: proc(log: Message_Log, x_offset: i32) {
	count := min(3, len(log.messages))
	if count == 0 {return}

	start := len(log.messages) - count

	for i in 0 ..< count {
		msg := log.messages[start + i]
		y := i32(4 + i * 20)
		rl.DrawText(fmt.ctprintf("%s", msg.text), x_offset, y, 16, msg.color)
	}
}

draw_message_area :: proc(game: ^Game) {
	// Background
	rl.DrawRectangle(0, 0, SCREEN_W, MSG_HEIGHT, rl.Color{0, 11, 30, 255})

	// Vertical divider between messages and combat logs
	mid_x := i32(SCREEN_W / 2)
	rl.DrawLine(mid_x, 2, mid_x, i32(MSG_HEIGHT) - 2, rl.Color{40, 40, 60, 255})

	// Left column is game logs / all events
	draw_log_column(game.game_log, 10)

	// Right column is combat logs, damage numbers, kills
	draw_log_column(game.combat_log, mid_x + 10)
}

get_resource_color :: proc(current, max_val: int) -> rl.Color {
	if max_val == 0 {return rl.Color{220, 40, 40, 255}}
	pct := f32(current) * 100.0 / f32(max_val)
	if pct > 75 {return rl.Color{0, 220, 230, 255}} 	// cyan - healthy
	if pct > 50 {return rl.Color{0, 200, 0, 255}} 	// green - fine
	if pct > 25 {return rl.Color{230, 200, 0, 255}} 	// yellow - caution
	return rl.Color{220, 40, 40, 255} // red - danger
}

draw_hud :: proc(game: ^Game) {
	player := get_player(game)
	player_data, ok := player.data.(Player_Data)
	if !ok {return}

	// === Background and separator ===
	rl.DrawRectangle(0, i32(HUD_AREA_Y), SCREEN_W, i32(HUD_HEIGHT), rl.Color{0, 11, 30, 255})
	rl.DrawLine(0, i32(HUD_AREA_Y), SCREEN_W, i32(HUD_AREA_Y), rl.Color{40, 40, 60, 255})

	FONT_SIZE :: i32(16)
	y1 := i32(HUD_AREA_Y) + 4 // line 1 - player status
	y2 := i32(HUD_AREA_Y) + 24 // line 2 - game state

	// === Line 1: player status ===
	rl.DrawText("@", 10, y1, FONT_SIZE, sample_color(PLAYER))

	rl.DrawText(
		fmt.ctprintf("HP:%d/%d", player.hp, 20), // TODO: player.max_hp
		140,
		y1,
		FONT_SIZE,
		get_resource_color(player.hp, 20),
	)

	rl.DrawText(
		fmt.ctprintf("Fuel:%d/%d", player_data.lantern.fuel, player_data.lantern.max_fuel),
		260,
		y1,
		FONT_SIZE,
		get_resource_color(player_data.lantern.fuel, player_data.lantern.max_fuel),
	)

	rl.DrawText("San:0%", 460, y1, FONT_SIZE, rl.Color{0, 220, 230, 255}) //
	// TODO: sanity
	rl.DrawText("[Fists]", 560, y1, FONT_SIZE, rl.WHITE) //
	// TODO: weapon

	// === Line 2: game state ===
	rl.DrawText(fmt.ctprintf("Fl:%d", game.current_floor), 10, y2, FONT_SIZE, rl.WHITE)
	rl.DrawText(
		fmt.ctprintf("T:%d", game.turn_count),
		80,
		y2,
		FONT_SIZE,
		rl.Color{100, 100, 120, 255},
	)

	lantern_label: cstring
	lantern_color: rl.Color
	switch player_data.lantern.state {
	case .Lit:
		lantern_label = "Lantern:Lit"
		lantern_color = rl.Color{245, 160, 55, 255}
	case .Extinguished:
		lantern_label = "Lantern:Off"
		lantern_color = rl.Color{140, 140, 140, 255}
	case .Empty:
		lantern_label = "LANTERN:EMPTY"
		lantern_color = rl.Color{220, 40, 40, 255}
	}
	rl.DrawText(lantern_label, 200, y2, FONT_SIZE, lantern_color)
}
