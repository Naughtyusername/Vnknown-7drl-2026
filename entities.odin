package sdrl

import "core:math/rand"

update_player :: proc(game: ^Game, actor: ^Actor, next_x, next_y: int) {
	if in_bounds(game, next_x, next_y) && game.tiles[next_y][next_x] != .Wall {
		actor.x = next_x
		actor.y = next_y
	}
}

update_enemy :: proc(game: ^Game, actor: ^Actor) -> Action {
	enemy_data, ok := &actor.data.(Enemy_Data)
	player := get_player(game)
	if !ok {return .Wait}

	switch enemy_data.ai_state {
	case .Idle:
		if can_detect_player(game, actor) {
			enemy_data.ai_state = .Hunting
			enemy_data.last_known_x = player.x
			enemy_data.last_known_y = player.y
			return .Wait
		}
		if enemy_data.enemy_type == .Wolf {
			alert_wolf_pack(game, actor)
		}
	case .Hunting:
		if can_detect_player(game, actor) {
			enemy_data.last_known_x = player.x
			enemy_data.last_known_y = player.y
		}

		next_x, next_y, found := astar_step(
			game,
			actor.x,
			actor.y,
			enemy_data.last_known_x,
			enemy_data.last_known_y,
		)

		if found && (next_x != actor.x || next_y != actor.y) {
			if next_x == player.x && next_y == player.y {
				resolve_enemy_attack(game, actor^, player)
				return .Attack
			}
			if get_enemy_at(game, next_x, next_y) != nil {return .Wait}
			actor.x = next_x
			actor.y = next_y
			return .Move
		}

		if actor.x == enemy_data.last_known_x && actor.y == enemy_data.last_known_y {
			if !can_detect_player(game, actor) {
				enemy_data.ai_state = .Idle
			}
		}

	}
	return .Wait
}

alert_wolf_pack :: proc(game: ^Game, alerting_wolf: ^Actor) {
	wolf_data := alerting_wolf.data.(Enemy_Data)
	for &actor in game.actors {
		if !actor.alive {continue}
		e, ok := &actor.data.(Enemy_Data)
		if !ok {continue}
		if e.enemy_type != .Wolf {continue}
		if e.ai_state == .Hunting {continue}
		dist := max(abs(actor.x - alerting_wolf.x), abs(actor.y - alerting_wolf.y))
		if dist <= 6 {
			e.ai_state = .Hunting
			e.last_known_x = wolf_data.last_known_x
			e.last_known_y = wolf_data.last_known_y
		}
	}
}

can_detect_player :: proc(game: ^Game, actor: ^Actor) -> bool {
	player := get_player(game)
	enemy_data, ok := actor.data.(Enemy_Data)
	if !ok {return false}

	// raw
	dist := max(abs(actor.x - player.x), abs(actor.y - player.y))
	if dist > enemy_data.vision_range {return false}

	// light
	if .Dark_Vision not_in enemy_data.tags {
		player_data := player.data.(Player_Data)
		if player_data.lantern.state != .Lit {
			if dist > 3 {return false}
		}
	}

	// los
	if !has_los(game, actor.x, actor.y, player.x, player.y) {
		return false
	}
	return true
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
			enemy_type = .Thrall,
			vision_range = 8,
			tags = {.Carries_Light},
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
		data = Enemy_Data {
			name = "Wolf",
			char = "w",
			color = sample_color(WOLF_COLOR),
			damage = 5,
			enemy_type = .Wolf,
			vision_range = 6,
			tags = {.Large, .Dark_Vision},
		},
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

resolve_kick :: proc(game: ^Game, player: ^Actor, target: ^Actor, dx, dy: int) {
	base_damage := 3
	push_x := target.x + dx
	push_y := target.y + dy

	// Wall Kick
	if get_tile(game, push_x, push_y) == .Wall {
		base_damage += 2
		target.hp -= base_damage
		if e, ok := target.data.(Enemy_Data); ok {
			log_combat(game, "You kick the %s into the wall for %d damage!", e.name, base_damage)
		}
		// Push kick
	} else if get_enemy_at(game, push_x, push_y) == nil {
		target.x = push_x
		target.y = push_y
		target.hp -= base_damage
		if e, ok := target.data.(Enemy_Data); ok {
			log_combat(game, "You kick the %s back!", e.name)
		}
		// Normal kick
	} else {
		target.hp -= base_damage
		if e, ok := target.data.(Enemy_Data); ok {
			log_combat(game, "You kick the %s!", e.name)
		}
	}
	if target.hp <= 0 {
		kill_enemy(game, target)
	}
}
