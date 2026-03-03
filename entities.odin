package sdrl

import "core:math/rand"

update_player :: proc(game: ^Game, actor: ^Actor, next_x, next_y: int) {
	if in_bounds(game, next_x, next_y) && game.tiles[next_y][next_x] != .Wall {
		actor.x = next_x
		actor.y = next_y
	}
}

update_enemy :: proc(game: ^Game, actor: ^Actor) -> Action {
	if !actor.alive {return .Wait}
	player := get_player(game)

	next_x, next_y, found := astar_step(game, actor.x, actor.y, player.x, player.y)

	if get_enemy_at(game, next_x, next_y) != nil {return .Wait}

	if found && (next_x != actor.x || next_y != actor.y) {
		if next_x == player.x && next_y == player.y {
			resolve_enemy_attack(game, actor^, player)
			return .Attack
		}
        if get_enemy_at(game, next_x, next_y) != nil { return .Wait }
		actor.x = next_x
		actor.y = next_y
		return .Move
	}
	// ai state switch later, hunting/alert/roaming/idle etc.

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
		actor: Actor
		if rand.float32() < 0.6 {
			actor = make_thrall(len(game.actors), x, y)
		} else {
			actor = make_wolf(len(game.actors), x, y)
		}
		append(&game.actors, actor)
	}

}

make_thrall :: proc(id, x, y: int) -> Actor {
	return Actor {
		id = id,
		x = x,
		y = y,
		hp = 8,
		max_hp = 8,
		alive = true,
		speed = 100,
		data = Enemy_Data {
			name = "Thrall",
			char = "t",
			color = sample_color(THRALL_COLOR),
			damage = 3,
		},
	}
}

make_wolf :: proc(id, x, y: int) -> Actor {
	return Actor {
		id = id,
		x = x,
		y = y,
		hp = 12,
		max_hp = 12,
		alive = true,
		speed = 120,
		data = Enemy_Data{name = "Wolf", char = "w", color = sample_color(WOLF_COLOR), damage = 5},
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
