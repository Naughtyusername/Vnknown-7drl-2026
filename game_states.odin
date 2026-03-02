package sdrl

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

// --- Playing State ---

Playing_State :: struct {
	game_ptr: ^Game,
}

playing_update :: proc(sm: ^State_Manager, data: rawptr) {
	state := (^Playing_State)(data)
	game := state.game_ptr

	if rl.IsKeyPressed(.GRAVE) {
		return
	}

	if rl.IsKeyPressed(.R) {
		for y in 0 ..< game.map_height {
			for x in 0 ..< game.map_width {
				game.revealed[y][x] = false
				game.visible[y][x] = false
			}
		}

		resize(&game.actors, 1) // Keep only player at index 0

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
		compute_fov(game, get_player(game).x, get_player(game).y, fov_radius)
		game.turn_count = 0
		return
	}

    // TODO: fullscreen toggle
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

	player_acted := false

	for !player_acted {
		actor := pop_next_actor(&game.scheduler)
		if actor == nil {break}

		if is_player(actor) {
			if action, ok := handle_input(game).?; ok {
				action_cost := get_action_cost(action)
				actor.time_next += action_cost * 100 / actor.speed
				game.current_time = actor.time_next
				game.scheduler.current_time = actor.time_next
				schedule_actor(&game.scheduler, actor)

				center_camera(&game.camera, actor.x, actor.y, game.map_width, game.map_height)
				compute_fov(game, actor.x, actor.y, fov_radius)
				game.turn_count += 1

				player_acted = true
			} else {
				schedule_actor(&game.scheduler, actor)
				break
			}
		} else {
			ai_action := update_enemy(game, actor)
			action_cost := get_action_cost(ai_action)
			actor.time_next += action_cost * 100 / actor.speed
			game.current_time = actor.time_next
			game.scheduler.current_time = actor.time_next
			schedule_actor(&game.scheduler, actor)
		}
	}
}

playing_draw :: proc(sm: ^State_Manager, data: rawptr) {
	state := (^Playing_State)(data)
	game := state.game_ptr
	draw_map(game)
	draw_enemies(game)
	draw_player(game)
	render_message_overlay(game)
	when ODIN_DEBUG {
        if draw_debug_overlay { draw_debug_info(game) }
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

// --- Input Handling ---
handle_input :: proc(game: ^Game) -> Maybe(Action) {
	player := get_player(game)

	next_x := player.x
	next_y := player.y

    // TODO we need to swap the rl key here to allow for shifted keys..
    // when we do that add in numpad and arrow key support.
	if rl.IsKeyPressed(.K) {next_y -= 1}
	if rl.IsKeyPressed(.J) {next_y += 1}
	if rl.IsKeyPressed(.H) {next_x -= 1}
	if rl.IsKeyPressed(.L) {next_x += 1}
	if rl.IsKeyPressed(.Y) {next_x -= 1;next_y -= 1}
	if rl.IsKeyPressed(.U) {next_x += 1;next_y -= 1}
	if rl.IsKeyPressed(.B) {next_x -= 1;next_y += 1}
	if rl.IsKeyPressed(.N) {next_x += 1;next_y += 1}

    // TEMP TODO stair decend
    if rl.IsKeyPressed(.PERIOD) && (rl.IsKeyDown(.LEFT_SHIFT) ||
        rl.IsKeyDown(.RIGHT_SHIFT)) {
            player_tile := get_tile(game, player.x, player.y)
            if player_tile == .Stairs_Down {
                descend_floor(game)
                return .Move // counts as an action
            } else {
                log_messagef(game, "There are no stairs here.")
                return nil
            }
        }

	if next_x != player.x || next_y != player.y {
		target_tile := get_tile(game, next_x, next_y)

		if target_tile != .Wall {
			if enemy_at(game, next_x, next_y) {
				log_messagef(game, "You attacked %d for %d damage!") // TODO: real combat
				return .Attack
			}
			player.x = next_x
			player.y = next_y
			return .Move
		}
		log_messagef(game, "You bump into the wall.")
		return nil
	}

	if rl.IsKeyPressed(.PERIOD) {
		return .Wait
	}

	return nil
}
