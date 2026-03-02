package sdrl

import "core:math/rand"
import rl "vendor:raylib"

update_player :: proc(game: ^Game, actor: ^Actor, next_x, next_y: int) {
	if in_bounds(game, next_x, next_y) && game.tiles[next_y][next_x] != .Wall {
		actor.x = next_x
		actor.y = next_y
	}
}

update_enemy :: proc(game: ^Game, actor: ^Actor) -> Action {
	player := get_player(game)

    next_x, next_y, found := astar_step(game, actor.x, actor.y, player.x, player.y)

    if found && (next_x != actor.x || next_y != actor.y) {
        actor.x = next_x
        actor.y = next_y
        return .Move
    }

	if in_bounds(game, next_x, next_y) && game.tiles[next_y][next_x] != .Wall {
		actor.x = next_x
		actor.y = next_y
		return .Move
	}

	return .Wait
}

spawn_enemies :: proc(game: ^Game, count: int) {
	player := get_player(game)
	for _ in 0 ..< count {
		x, y: int

		for attempts := 0; attempts < 1000; attempts += 1 {
			x = rand.int_max(game.map_width)
			y = rand.int_max(game.map_height)

			if game.tiles[y][x] == .Floor && (x != player.x || y != player.y) {
				break
			}
		}

		enemy := Actor {
			id = len(game.actors),
			x = x,
			y = y,
			hp = 10,
			time_next = 0,
			speed = 100, // TODO: variable speed
			data = Enemy_Data{color = rl.Color{200, 80, 60, 255}, char = "e"},
		}
		append(&game.actors, enemy)
	}
}

place_player :: proc(game: ^Game) {
	player := get_player(game)
	player.x = game.map_width / 2
	player.y = game.map_height / 2

	// If center is blocked, find a random floor tile
	if game.tiles[player.y][player.x] != .Floor {
		for attempts := 0; attempts < 1000; attempts += 1 {
			player.x = rand.int_max(game.map_width)
			player.y = rand.int_max(game.map_height)

			if game.tiles[player.y][player.x] == .Floor {
				break
			}
		}
	}
}
