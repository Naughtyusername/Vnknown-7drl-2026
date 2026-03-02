package sdrl

import rl "vendor:raylib"
import "core:math/rand"
import "core:time"

main :: proc() {

	rl.InitWindow(SCREEN_W, SCREEN_H, "Odin Roguelike - Phase 0")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL) // Frees escape for pause/state-specific binds

	game := init_game(MAP_WIDTH, MAP_HEIGHT)
	defer cleanup_game(&game)

	sm: State_Manager
	init_state(&sm)
	defer cleanup_states(&sm)

	playing_state_data := new(Playing_State)
	playing_state_data.game_ptr = &game

	playing_game_state := Game_State {
		data           = playing_state_data,
		update         = playing_update,
		draw           = playing_draw,
		kill           = playing_kill,
		is_transparent = false,
	}

	push_state(&sm, playing_game_state)

	t := time.now()._nsec
	rand.reset(u64(t))

	generate_dungeon(&game)

	for &actor in game.actors {
		schedule_actor(&game.scheduler, &actor)
	}

	player := get_player(&game)
	compute_fov(&game, player.x, player.y, fov_radius, MAX_LANTERN_RADIUS)
	center_camera(&game.camera, player.x, player.y, game.map_width, game.map_height)

	for !rl.WindowShouldClose() && !game.quit {
		update_game(&sm)

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		draw_game(&sm)
		rl.EndDrawing()
		free_all(context.temp_allocator)
	}
}
