package sdrl

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"

// --- State Machine Base ---

State_Manager :: struct {
	stack: [dynamic]Game_State,
}

Game_State_Proc :: proc(sm: ^State_Manager, data: rawptr)

Game_State :: struct {
	data:           rawptr,
	update:         Game_State_Proc,
	draw:           Game_State_Proc,
	kill:           Game_State_Proc,
	is_transparent: bool,
}

init_state :: proc(sm: ^State_Manager) {
	sm.stack = make([dynamic]Game_State)
}

push_state :: proc(sm: ^State_Manager, state: Game_State) {
	append(&sm.stack, state)
}

pop_state :: proc(sm: ^State_Manager) {
	if len(sm.stack) > 0 {
		top := pop(&sm.stack)
		if top.kill != nil {
			top.kill(sm, top.data)
		}
	}
}

cleanup_states :: proc(sm: ^State_Manager) {
	for len(sm.stack) > 0 {
		pop_state(sm)
	}
	delete(sm.stack)
}

// === Death State ===

Death_State :: struct {
	game_ptr: ^Game,
}

death_update :: proc(sm: ^State_Manager, data: rawptr) {
	state := (^Death_State)(data)
	if rl.GetKeyPressed() != .KEY_NULL {
		state.game_ptr.wants_restart = true
		pop_state(sm)
	}
}

death_draw :: proc(sm: ^State_Manager, data: rawptr) {
	state := (^Death_State)(data)
	game := state.game_ptr

	// Dark overlay over the map
	rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Color{0, 0, 0, 180})

	cx := SCREEN_W / 2
	cy := SCREEN_H / 2

	// "Slain by X"
	cause := fmt.ctprintf("Slain by a %s", game.death_cause)
	cw := rl.MeasureText(cause, 28)
	rl.DrawText(cause, i32(cx) - cw / 2, i32(cy) - 60, 28, rl.Color{220, 40, 40, 255})

	// "on Floor X"
	floor_text := fmt.ctprintf("on Floor %d", game.current_floor)
	fw := rl.MeasureText(floor_text, 20)
	rl.DrawText(floor_text, i32(cx) - fw / 2, i32(cy) - 24, 20, rl.Color{150, 150, 160, 255})

	// Stats
	turns_text := fmt.ctprintf("Turns survived: %d", game.turn_count)
	tw := rl.MeasureText(turns_text, 16)
	rl.DrawText(turns_text, i32(cx) - tw / 2, i32(cy) + 20, 16, rl.Color{120, 120, 130, 255})

	// kills
	kills_text := fmt.ctprintf("Enemies slain: %d", game.enemies_slain)
	kw := rl.MeasureText(kills_text, 16)
	rl.DrawText(kills_text, i32(cx) - kw / 2, i32(cy) + 42, 16, rl.Color{120, 120, 130, 255})

	// Prompt
	prompt := fmt.ctprintf("-- Press Enter/Space/Escape to exit --")
	pw := rl.MeasureText(prompt, 14)
	rl.DrawText(prompt, i32(cx) - pw / 2, i32(cy) + 100, 14, rl.Color{70, 70, 80, 255})

}

death_kill :: proc(sm: ^State_Manager, data: rawptr) {
	free((^Death_State)(data))
}

// --- Playing State ---

Playing_State :: struct {
	game_ptr: ^Game,
}

playing_update :: proc(sm: ^State_Manager, data: rawptr) {
	state := (^Playing_State)(data)
	game := state.game_ptr

	if game.wants_restart {
		game.wants_restart = false
		restart_game(game)
		return
	}
	// Open Inv
	if rl.IsKeyPressed(.I) {
		inv := new(Inventory_State)
		inv.game_ptr = game
		inv.selected_idx = -1
		push_state(
			sm,
			Game_State {
				data = inv,
				update = inventory_update,
				draw = inventory_draw,
				kill = inventory_kill,
				is_transparent = true,
			},
		)
		return
	}

	// Restart Game Debug feature TODO Remove or wrap in ODIN_DEBUG before releasing on the 7th
	if rl.IsKeyPressed(.R) {
		for y in 0 ..< game.map_height {
			for x in 0 ..< game.map_width {
				game.revealed[y][x] = false
				game.visible[y][x] = false
			}
		}


		resize(&game.actors, 1) // Keep only player at index 0 ALWAYS

		generate_dungeon(game)

		clear(&game.scheduler.actors)
		for &actor in game.actors {
			schedule_actor(&game.scheduler, &actor)
		}

		center_camera(
			&game.camera,
			get_player(game).x,
			get_player(game).y,
			game.map_width,
			game.map_height,
		)

		fov_r, lantern_r := get_fov_radii(game)
		compute_fov(game, get_player(game).x, get_player(game).y, fov_r, lantern_r)

		game.turn_count = 0
		return
	}

	if rl.IsKeyPressed(.F11) {
		rl.ToggleFullscreen()
		rl.GetScreenWidth()
		rl.GetScreenHeight()
	}

	if rl.IsKeyPressed(.P) || rl.IsKeyPressed(.ESCAPE) {
		paused_state_data := new(Paused_State)
		paused_state_data.menu_items = make([]cstring, 2)
		paused_state_data.menu_items[0] = "Resume"
		paused_state_data.menu_items[1] = "Quit"
		paused_state_data.selected_item = 0
		paused_state_data.game_ptr = game

		paused_game_state := Game_State {
			data           = paused_state_data,
			update         = paused_update,
			draw           = paused_draw,
			kill           = paused_kill,
			is_transparent = true,
		}
		push_state(sm, paused_game_state)
		return
	}

	// Debug keybinds
	when ODIN_DEBUG {
		if rl.IsKeyPressed(.F8) {
			draw_light_debug_overlay = !draw_light_debug_overlay
		}
	}
	when ODIN_DEBUG {
		if rl.IsKeyPressed(.F3) {
			draw_debug_overlay = !draw_debug_overlay
		}
	}
	when ODIN_DEBUG {
		if rl.IsKeyPressed(.F5) {
			grant_random_boon(game)
		}
	}
	when ODIN_DEBUG {
		if rl.IsKeyPressed(.MINUS) {
			descend_floor(game)
		}
	}
	when ODIN_DEBUG {
		if rl.IsKeyPressed(.EQUAL) {
			ascend_floor(game)
		}
	}
	when ODIN_DEBUG {
		if rl.IsKeyPressed(.Z) {
			player := get_player(game)
			player.hp = player.max_hp
			log_messagef(game, "[DEBUG] Healed.")
		}
	}
	when ODIN_DEBUG {
		if rl.IsKeyPressed(.X) {
			if pd, pd_ok := &get_player(game).data.(Player_Data); pd_ok {
				pd.lantern.fuel = 300
				log_messagef(game, "[DEBUG] Fueled.")
			}
		}
	}

	when ODIN_DEBUG {
		if rl.IsKeyPressed(.C) {
			player := get_player(game)
			wx, wy := player.x, player.y
			outer: for dy in -5 ..= 5 {
				for dx in -5 ..= 5 {
					nx, ny := player.x + dx, player.y + dy
					if in_bounds(game, nx, ny) &&
					   game.tiles[ny][nx] == .Floor &&
					   !enemy_at(game, nx, ny) {
						wx, wy = nx, ny
						break outer // Odin's labled break, allows escape of both loops
					}
				}
			}
			wraith := make_wraith(len(game.actors), wx, wy)
			append(&game.actors, wraith)
			schedule_actor(&game.scheduler, &game.actors[len(game.actors) - 1])
			game.wraith_count += 1
			log_messagef(game, "[DEBUG] Wraith spawned.")
		}
	}

	player_acted := false

	for !player_acted {
		actor := pop_next_actor(&game.scheduler)
		if actor == nil {break}

		if is_player(actor) {
			if actor.stunned_turns > 0 {
				actor.stunned_turns -= 1
				log_messagef(game, "You are stunned!")
				actor.time_next += BASE_SPEED * BASE_SPEED / actor.speed
				game.current_time = actor.time_next
				game.scheduler.current_time = actor.time_next
				schedule_actor(&game.scheduler, actor)
				drain_fuel(game)
				//FOV recompute
				fov_r, lantern_r := get_fov_radii(game)
				compute_fov(game, actor.x, actor.y, fov_r, lantern_r)
				// Enemy lighting compute
				for &ea in game.actors {
					if !ea.alive {continue}
					ed, ok := ea.data.(Enemy_Data)
					if !ok {continue}
					if .Carries_Light not_in ed.tags {continue}
					if ed.light_radius <= 0 {continue}
					lc: rl.Color
					#partial switch ed.enemy_type {
					case .Thrall:
						lc = sample_color(THRALL_LIGHT)
					case .Wraith:
						lc = sample_color(WRAITH_LIGHT)
					case:
						lc = rl.WHITE
					}
					emit_light(game, ea.x, ea.y, ed.light_radius, lc)
				}
				game.turn_count += 1
				player_acted = true
				continue
			}
			if result, ok := handle_input(game).?; ok { 	// .? is odins Maybe/Optional wrapper
				// try to unwrap this Maybe, if there is data, run it.
				actor.time_next += result.cost * BASE_SPEED / actor.speed

				game.current_time = actor.time_next
				game.scheduler.current_time = actor.time_next
				schedule_actor(&game.scheduler, actor)

				// Lantern handling
				drain_fuel(game)
				player_data := get_player(game).data.(Player_Data)
				fov_r := MAX_FOV_RADIUS
				lantern_r := 0
				switch player_data.lantern.state {
				case .Lit:
					lantern_r = calculate_lantern_radius(player_data.lantern)
				case .Extinguished:
					fov_r = MAX_FOV_RADIUS // Can still see cave geometry
				case .Empty:
					fov_r = 3 // nearly blind
				}

				center_camera(&game.camera, actor.x, actor.y, game.map_width, game.map_height)
				compute_fov(game, actor.x, actor.y, fov_r, lantern_r)
				// Enemy lighting compute
				for &ea in game.actors {
					if !ea.alive {continue}
					ed, e_ok := ea.data.(Enemy_Data)
					if !e_ok {continue}
					if .Carries_Light not_in ed.tags {continue}
					if ed.light_radius <= 0 {continue}
					lc: rl.Color
					#partial switch ed.enemy_type {
					case .Thrall:
						lc = sample_color(THRALL_LIGHT)
					case .Wraith:
						lc = sample_color(WRAITH_LIGHT)
					case:
						lc = rl.WHITE
					}
					emit_light(game, ea.x, ea.y, ed.light_radius, lc)
				}
				game.turn_count += 1

				// sanity drain -- lazy fast -- TODO base this not on lantern state but is_tile_lit....
				// but we still have the bug of light ball blobs so unless i fix that before lauch, this is safer.
				if pd, pd_ok := &get_player(game).data.(Player_Data); pd_ok {
					pd.sanity_tick += 1
					#partial switch pd.lantern.state {
					case .Empty:
						pd.sanity = max(0, pd.sanity - 1)
					case .Extinguished:
						if pd.sanity_tick % 2 == 0 {
							pd.sanity = max(0, pd.sanity - 1)
						}
					case .Lit:
						// starting with 10 turns per sanity regen, scale from there (clamp to 100 in here since i didnt do it elsewhere...TODO maybe do that since other things will drain sanity.)
						if pd.sanity_tick % 10 == 0 && pd.sanity <= 99 {
							pd.sanity = max(0, pd.sanity + 1)
						}
						// Wraith Sanity drain -- TODO Boss will be similar to this wehn implemented
						for &other in game.actors {
							e, e_ok := other.data.(Enemy_Data)
							if !e_ok || !other.alive {continue}
							if e.enemy_type != .Wraith {continue}
							dist := max(
								abs(other.x - get_player(game).x),
								abs(other.y - get_player(game).y),
							)
							if dist <= 5 {
								pd.sanity = max(0, pd.sanity - 1)
							}
						}
					}
				}


				WRAITH_SPAWN_INTERVAL_BASE :: 150
				WRAITH_SPAWN_INTERVAL_MIN :: 80

				// wraith spawn checker
				if game.current_floor >= 2 && game.turn_count >= game.next_wraith_spawn {
					player := get_player(game)
					// spawn away from player
					spawn_x, spawn_y := player.x, player.y
					best_dist := 0
					for _ in 0 ..< 200 {
						tx := rand.int_max(game.map_width)
						ty := rand.int_max(game.map_height)
						if game.tiles[ty][tx] != .Floor {continue}
						d := max(abs(tx - player.x), abs(ty - player.y))
						if d > best_dist {
							best_dist = d
							spawn_x, spawn_y = tx, ty
						}
						if best_dist > 15 {break}
					}
					wraith := make_wraith(len(game.actors), spawn_x, spawn_y)
					append(&game.actors, wraith)
					schedule_actor(&game.scheduler, &game.actors[len(game.actors) - 1])
					game.wraith_count += 1
					// Each successive wraith comes faster, floor depth also tightens interval
					interval := max(
						WRAITH_SPAWN_INTERVAL_MIN,
						WRAITH_SPAWN_INTERVAL_BASE -
						game.wraith_count * 15 -
						game.current_floor * 5,
					)
					game.next_wraith_spawn += interval
					log_messagef(game, "A chill runs down your spine...")
				}

				player_acted = true
			} else {
				schedule_actor(&game.scheduler, actor)
				break
			}
		} else {
			if !actor.alive {continue}

			// Stun handling
			if actor.stunned_turns > 0 {
				actor.stunned_turns -= 1
				action_cost := 200 // TODO stun_duration
				actor.time_next += action_cost * BASE_SPEED / actor.speed
				game.current_time = actor.time_next
				game.scheduler.current_time = actor.time_next
				schedule_actor(&game.scheduler, actor)
				continue
			}

			// Death state handling
			ai_action := update_enemy(game, actor)
			if get_player(game).hp <= 0 {
				death_state_data := new(Death_State)
				death_state_data.game_ptr = game
				push_state(
					sm,
					Game_State {
						data = death_state_data,
						update = death_update,
						draw = death_draw,
						kill = death_kill,
						is_transparent = true,
					},
				)
				break
			}
			action_cost := get_action_cost(ai_action)
			actor.time_next += action_cost * BASE_SPEED / actor.speed
			game.current_time = actor.time_next
			game.scheduler.current_time = actor.time_next
			schedule_actor(&game.scheduler, actor)
		}
	}
}

playing_draw :: proc(sm: ^State_Manager, data: rawptr) {
	state := (^Playing_State)(data)
	game := state.game_ptr
	draw_message_area(game) // topbar
	draw_map(game) // worldmap
	draw_pedestal(game)
	draw_traps(game)
	draw_gold_piles(game)
	draw_items(game)
	draw_enemies(game)
	draw_player(game)
	draw_hud(game) // bottom bar ui/hud
	when ODIN_DEBUG {
		if draw_debug_overlay {draw_debug_info(game)}
	}
}

playing_kill :: proc(sm: ^State_Manager, data: rawptr) {
	state := (^Playing_State)(data)
	free(state)
}

// --- Paused State ---

Paused_State :: struct {
	menu_items:    []cstring,
	selected_item: int,
	game_ptr:      ^Game,
}

paused_update :: proc(sm: ^State_Manager, data: rawptr) {
	state := (^Paused_State)(data)

	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.J) {
		state.selected_item += 1
		if state.selected_item >= len(state.menu_items) {
			state.selected_item = 0
		}
	}
	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.K) {
		state.selected_item -= 1
		if state.selected_item < 0 {
			state.selected_item = len(state.menu_items) - 1
		}
	}

	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE) {
		switch state.selected_item {
		case 0:
			pop_state(sm)
			return
		case 1:
			state.game_ptr.quit = true
			return
		}
	}

	if rl.IsKeyPressed(.P) || rl.IsKeyPressed(.ESCAPE) {
		pop_state(sm)
		return
	}
}

paused_draw :: proc(sm: ^State_Manager, data: rawptr) {
	state := (^Paused_State)(data)

	rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Color{0, 0, 0, 128})

	FONT_SIZE :: 30
	ITEM_SPACING :: 40
	total_menu_height := len(state.menu_items) * ITEM_SPACING
	menu_y := (SCREEN_H - total_menu_height) / 2

	for i in 0 ..< len(state.menu_items) {
		item_text := state.menu_items[i]
		text_width := rl.MeasureText(item_text, FONT_SIZE)
		text_color: rl.Color = rl.GRAY
		if i == state.selected_item {
			text_color = rl.WHITE
		}

		item_x := (SCREEN_W - text_width) / 2
		item_y := menu_y + (i * ITEM_SPACING)
		rl.DrawText(item_text, item_x, cast(i32)item_y, FONT_SIZE, text_color)
	}
}

paused_kill :: proc(sm: ^State_Manager, data: rawptr) {
	state := (^Paused_State)(data)
	delete(state.menu_items) // free slice before struct
	free(state)
}

try_pickup_item :: proc(game: ^Game) {
	player := get_player(game)
	pd := &player.data.(Player_Data)
	for i := len(game.items) - 1; i >= 0; i -= 1 {
		item := game.items[i]
		if item.x == player.x && item.y == player.y {
			if len(pd.inventory) >= 26 {
				log_messagef(game, "Your pack is full.")
				break
			}
			item.x = 0;item.y = 0 // clear ground positions
			append(&pd.inventory, item)
			// Name thitm based on type
			#partial switch d in item.data {
			case Potion_Data:
				log_messagef(game, "You pick up a potion.")
			case Scroll_Data:
				log_messagef(game, "You pick up a scroll.")
			}
			unordered_remove(&game.items, i)
		}
	}
}

Inventory_State :: struct {
	game_ptr:     ^Game,
	selected_idx: int, // -1 = no selection
}

inventory_update :: proc(sm: ^State_Manager, data: rawptr) {
	state := (^Inventory_State)(data)
	game := state.game_ptr
	player := get_player(game)
	pd := &player.data.(Player_Data)
	shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

	if rl.IsKeyPressed(.ESCAPE) {
		if state.selected_idx >= 0 {
			state.selected_idx = -1
		} else {
			pop_state(sm)
		}
		return
	}

	if state.selected_idx < 0 {
		// Letter selection
		for i in 0 ..< 26 {
			key := rl.KeyboardKey(int(rl.KeyboardKey.A) + i)
			if rl.IsKeyPressed(key) && i < len(pd.inventory) {
				state.selected_idx = i
				return
			}
		}
	} else {
		item := pd.inventory[state.selected_idx]
		// d = drink potion
		if rl.IsKeyPressed(.D) && !shift {
			if _, ok := item.data.(Potion_Data); ok {
				use_item(game, state.selected_idx)
				pop_state(sm)
				return
			}
		}
		// r = read scroll
		if rl.IsKeyPressed(.R) {
			if _, ok := item.data.(Scroll_Data); ok {
				use_item(game, state.selected_idx)
				pop_state(sm)
				return
			}
		}
		// D = drop
		if rl.IsKeyPressed(.D) && shift {
			drop_item(game, state.selected_idx)
			state.selected_idx = -1
			if len(pd.inventory) == 0 {pop_state(sm)}
			return
		}
	}
}

inventory_draw :: proc(sm: ^State_Manager, data: rawptr) {
	state := (^Inventory_State)(data)
	game := state.game_ptr
	pd := get_player(game).data.(Player_Data)

	INV_X :: i32(SCREEN_W) * 3 / 4
	INV_Y :: i32(0)
	INV_W :: i32(SCREEN_W) / 4
	INV_H :: i32(SCREEN_H)
	INV_FONT :: i32(16)
	INV_LINE_H :: i32(20)

	rl.DrawRectangle(INV_X, INV_Y, INV_W, INV_H, rl.Color{0, 8, 20, 135}) // mostly transparent so you dont miss anything
	rl.DrawRectangleLinesEx(
		rl.Rectangle{f32(INV_X), f32(INV_Y), f32(INV_W), f32(INV_H)},
		1,
		rl.Color{40, 60, 100, 255},
	)
	rl.DrawText("[ INVENTORY ]", INV_X + 10, INV_Y + 8, INV_FONT, rl.WHITE)
	rl.DrawLine(INV_X, INV_Y + 28, INV_X + INV_W, INV_Y + 28, rl.Color{40, 60, 100, 255})

	if len(pd.inventory) == 0 {
		rl.DrawText("(empty)", INV_X + 10, INV_Y + 38, INV_FONT, rl.GRAY)
	}
	for i in 0 ..< len(pd.inventory) {
		item := pd.inventory[i]
		y := INV_Y + 36 + i32(i) * INV_LINE_H
		color := rl.WHITE

		if state.selected_idx == i {
			rl.DrawRectangle(INV_X + 4, y - 1, INV_W - 8, INV_LINE_H, rl.Color{30, 70, 120, 200})
			color = rl.YELLOW
		}

		letter := fmt.ctprintf("%c)", rune('a') + rune(i))
		rl.DrawText(letter, INV_X + 10, y, INV_FONT, color)
		rl.DrawText(fmt.ctprintf("%s", item_name(item)), INV_X + 34, y, INV_FONT, color)
	}

	// Bottom action bar
	bar_y := INV_Y + INV_H - 28
	rl.DrawLine(INV_X, bar_y, INV_X + INV_W, bar_y, rl.Color{40, 60, 100, 255})

	if state.selected_idx >= 0 && state.selected_idx < len(pd.inventory) {
		item := pd.inventory[state.selected_idx]
		#partial switch _ in item.data {
		case Potion_Data:
			rl.DrawText(
				"[d]rink  [D]rop  [Esc]cancel",
				INV_X + 10,
				bar_y + 6,
				INV_FONT,
				rl.Color{160, 160, 180, 255},
			)
		case Scroll_Data:
			rl.DrawText(
				"[r]ead  [D]rop  [Esc]cancel",
				INV_X + 10,
				bar_y + 6,
				INV_FONT,
				rl.Color{160, 160, 180, 255},
			)
		}
	} else {
		rl.DrawText(
			"[a-z] select item  [Esc] close",
			INV_X + 10,
			bar_y + 6,
			INV_FONT,
			rl.Color{100, 100, 120, 255},
		)
	}
}

inventory_kill :: proc(sm: ^State_Manager, data: rawptr) {
	free((^Inventory_State)(data))
}

// --- Input Handling ---
handle_input :: proc(game: ^Game) -> Maybe(Action_Result) {
	player := get_player(game)
	shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

	next_x := player.x
	next_y := player.y

	// === VI KEYS ====
	if rl.IsKeyPressed(.H) && !shift {next_x -= 1}
	if rl.IsKeyPressed(.J) && !shift {next_y += 1}
	if rl.IsKeyPressed(.K) && !shift {next_y -= 1}
	if rl.IsKeyPressed(.L) && !shift {next_x += 1}

	if rl.IsKeyPressed(.Y) && !shift {next_x -= 1;next_y -= 1}
	if rl.IsKeyPressed(.U) && !shift {next_x += 1;next_y -= 1}
	if rl.IsKeyPressed(.B) && !shift {next_x -= 1;next_y += 1}
	if rl.IsKeyPressed(.N) && !shift {next_x += 1;next_y += 1}

	// === NUMPAD ===
	if rl.IsKeyPressed(.KP_4) && !shift {next_x -= 1}
	if rl.IsKeyPressed(.KP_2) && !shift {next_y += 1}
	if rl.IsKeyPressed(.KP_8) && !shift {next_y -= 1}
	if rl.IsKeyPressed(.KP_6) && !shift {next_x += 1}

	if rl.IsKeyPressed(.KP_7) && !shift {next_x -= 1;next_y -= 1}
	if rl.IsKeyPressed(.KP_9) && !shift {next_x += 1;next_y -= 1}
	if rl.IsKeyPressed(.KP_1) && !shift {next_x -= 1;next_y += 1}
	if rl.IsKeyPressed(.KP_3) && !shift {next_x += 1;next_y += 1}

	// === ARROW KEYS ===
	if rl.IsKeyPressed(.LEFT) && !shift {next_x -= 1}
	if rl.IsKeyPressed(.DOWN) && !shift {next_y += 1}
	if rl.IsKeyPressed(.UP) && !shift {next_y -= 1}
	if rl.IsKeyPressed(.RIGHT) && !shift {next_x += 1}

	// Weapon swap
	if rl.IsKeyPressed(.TAB) {
		if pd, ok := &player.data.(Player_Data); ok {
			if pd.active_weapon == .Dagger {
				pd.active_weapon = .Whip
				log_messagef(game, "You ready the whip")
			} else if pd.active_weapon == .Whip {
				pd.active_weapon = .Dagger
				log_messagef(game, "You pull your dagger")
			}
		}
		pd := &player.data.(Player_Data)
		stats := get_weapon_stats(pd.active_weapon)
		if .Quick_Hands in pd.boons {
			swap_cost := stats.swap_cost / 2
			return Action_Result{action = .Wait, cost = swap_cost}
		} else {
			game.last_action_cost = stats.swap_cost
		}
		return Action_Result{action = .Wait, cost = stats.swap_cost}
	}

	// Toggle lantern
	if rl.IsKeyPressed(.L) && shift {
		if data, ok := &player.data.(Player_Data); ok {
			switch data.lantern.state {
			case .Lit:
				data.lantern.state = .Extinguished
				log_messagef(game, "You snuff out the flame.")
			case .Extinguished:
				if data.lantern.fuel > 0 {
					data.lantern.state = .Lit
					log_messagef(game, "You re-light the lantern.")
				} else {
					log_messagef(game, "No fuel remains.")
					return nil
				}
			case .Empty:
				log_messagef(game, "No fuel remains.")
				return nil
			}
			return Action_Result{action = .Wait, cost = BASE_SPEED}
		}
	}

	// Whip (A)bility
	if rl.IsKeyPressed(.A) {
		pd := player.data.(Player_Data)
		if pd.active_weapon != .Whip {
			log_messagef(game, "Nothing to activate.")
			return nil
		}
		// Scan in facing dir for a target to trip
		dx := pd.last_dx
		dy := pd.last_dy
		for dist in 1 ..= 3 {
			check_x := player.x + dx * dist
			check_y := player.y + dy * dist

			if get_tile(game, check_x, check_y) == .Wall {break}
			if target := get_enemy_at(game, check_x, check_y); target != nil {
				stats := get_weapon_stats(pd.active_weapon)
				target.stunned_turns = 2
				if e_data, ok := target.data.(Enemy_Data); ok {
					log_messagef(game, "You trip the %s!", e_data.name)
				}
				return Action_Result{action = .Attack, cost = stats.ability_cost}
			}
		}
		log_messagef(game, "No target in range.")
		return nil
	}

	// (K)ick skill
	if rl.IsKeyPressed(.K) && shift {
		pd := player.data.(Player_Data)
		// kick at nothing
		if pd.last_dx == 0 && pd.last_dy == 0 {
			log_messagef(game, "You kick at nothing.")
			return nil
		}

		// nothing *to* kick
		target := get_enemy_at(game, player.x + pd.last_dx, player.y + pd.last_dy)
		if target == nil {
			log_messagef(game, "Nothing to kick.")
			return nil
		}
		resolve_kick(game, player, target, pd.last_dx, pd.last_dy)
		return Action_Result{action = .Attack, cost = game.last_action_cost}
	}

	if rl.IsKeyPressed(.PERIOD) && shift {
		player_tile := get_tile(game, player.x, player.y)
		if player_tile == .Stairs_Down {
			descend_floor(game)
			return Action_Result{action = .Move, cost = BASE_SPEED}
		} else {
			log_messagef(game, "There are no stairs here.")
			return nil
		}
	}

	// Treasure room / pedestal
	if ped, ok := game.pedestal.?; ok && ped.active && next_x == ped.x && next_y == ped.y {
		grant_random_boon(game)
		ped.active = false
		game.pedestal = ped // write back the modified copy
		return Action_Result{action = .Wait, cost = BASE_SPEED}
	}

	// Movement / Bounds checking
	if next_x != player.x || next_y != player.y {
		if pd, ok := &player.data.(Player_Data); ok {
			pd.last_dx = next_x - player.x
			pd.last_dy = next_y - player.y
		}

		pw := player.data.(Player_Data)
		if pw.active_weapon == .Whip {
			dx := next_x - player.x
			dy := next_y - player.y
			for dist in 1 ..= 3 {
				check_x := player.x + dx * dist
				check_y := player.y + dy * dist

				if get_tile(game, check_x, check_y) == .Wall {break}

				if target := get_enemy_at(game, check_x, check_y); target != nil {
					resolve_player_attack(game, player, target)
					return Action_Result{action = .Attack, cost = game.last_action_cost}
				}
			}
		}

		target_tile := get_tile(game, next_x, next_y)

		// Player movement
		if target_tile != .Wall {
			if target := get_enemy_at(game, next_x, next_y); target != nil {
				resolve_player_attack(game, player, target)
				return Action_Result{action = .Attack, cost = game.last_action_cost}
			}
			player.x = next_x
			player.y = next_y
			check_trap(game, player)
			try_pickup_gold(game)
			try_pickup_item(game)
			return Action_Result{action = .Move, cost = BASE_SPEED}
		}
		log_messagef(game, "You bump into the wall.")
		return nil
	}

	if rl.IsKeyPressed(.PERIOD) {
		return Action_Result{action = .Move, cost = BASE_SPEED}
	}

	return nil
}
