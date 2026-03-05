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

	// TODO added a roaming ai, not handled yet
	#partial switch enemy_data.ai_state {
	// idle
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
		if enemy_data.enemy_type == .Shade {
			player_data := player.data.(Player_Data)
			tile_lit := !is_dark(game.light_map[actor.y][actor.x])
			if tile_lit && player_data.lantern.state == .Lit {
				enemy_data.ai_state = .Fleeing;{
					enemy_data.ai_state = .Idle
				}

			}
		}
	// hunting
	case .Hunting:
		if can_detect_player(game, actor) {
			enemy_data.last_known_x = player.x
			enemy_data.last_known_y = player.y
		}

		// astar a*
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
			check_trap(game, actor)
			return .Move
		}

		if actor.x == enemy_data.last_known_x && actor.y == enemy_data.last_known_y {
			if !can_detect_player(game, actor) {
				enemy_data.ai_state = .Idle
			}
		}
	// Fleeing
	case .Fleeing:
		best_x, best_y := actor.x, actor.y
		best_dist := max(abs(actor.x - player.x), abs(actor.y - player.y))
		for dir in ([4][2]int{{0, -1}, {0, 1}, {-1, 0}, {1, 0}}) {
			nx := actor.x + dir[0]
			ny := actor.y + dir[1]
			if get_tile(game, nx, ny) == .Wall {continue}
			if get_enemy_at(game, nx, ny) != nil {continue}
			d := max(abs(nx - player.x), abs(ny - player.y))
			if d > best_dist {
				best_dist = d
				best_x, best_y = nx, ny
			}
		}
		if best_x != actor.x || best_y != actor.y {
			actor.x = best_x
			actor.y = best_y
			check_trap(game, actor)
			return .Move
		}
	//Roaming
	// TODO
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
		roll := rand.float32()
		if game.current_floor >= 2 && roll < 0.15 {
			actor = make_shade(len(game.actors), x, y)
		} else if roll < 0.50 {
			actor = make_thrall(len(game.actors), x, y)
		} else if roll < 0.80 {
			actor = make_wolf(len(game.actors), x, y)
		} else {
			actor = make_lantern_pest(len(game.actors), x, y)
		}
		append(&game.actors, actor)
	}

}

spawn_gold_piles :: proc(game: ^Game) {
	player := get_player(game)
	count := 2 + rand.int_max(3)

	for _ in 0 ..< count {
		x, y: int
		for attempts := 0; attempts < 1000; attempts += 1 {
			x = rand.int_max(game.map_width)
			y = rand.int_max(game.map_height)
			if game.tiles[y][x] == .Floor && (x != player.x || y != player.y) {
				break
			}
		}
		amount := 20 + rand.int_max(41)
		append(&game.gold_piles, Gold_Pile{x = x, y = y, amount = amount})
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

make_lantern_pest :: proc(id, x, y: int) -> Actor {
	return Actor {
		id = id,
		x = x,
		y = y,
		hp = 4,
		max_hp = 4,
		alive = true,
		speed = 150,
		data = Enemy_Data {
			name = "Lantern Pest",
			char = "p",
			color = sample_color(PEST_COLOR),
			vision_range = 10,
			tags = {.Dark_Vision},
		},
	}
}

make_shade :: proc(id, x, y: int) -> Actor {
	return Actor {
		id = id,
		x = x,
		y = y,
		hp = 6,
		max_hp = 6,
		alive = true,
		speed = 90,
		data = Enemy_Data {
			name = "Shade",
			char = "s",
			color = sample_color(SHADE_COLOR),
			damage = 6,
			enemy_type = .Shade,
			vision_range = 12,
			tags = {.Dark_Vision, .Stealthy},
		},
	}
}

make_wraith :: proc(id, x, y: int) -> Actor {
	return Actor {
		id = id, x = x, y = y,
		hp = 20, max_hp = 20, alive = true, speed = 80,
		data = Enemy_Data {
			name = "Wraith", char = "W",
			color = sample_color(WRAITH_COLOR),
			damage = 8, enemy_type = .Wraith,
			vision_range = 20,
			tags = {.Dark_Vision, .Carries_Light},
		},
}
}

check_trap :: proc(game: ^Game, actor: ^Actor) {
	for &trap in game.traps {
		if trap.x != actor.x || trap.y != actor.y {continue}
		if trap.triggered {continue}

		trap.triggered = true
		trap.revealed = true

		is_player_actor := is_player(actor)

		switch trap.type {
		case .Spike:
			actor.hp -= 5
			if is_player_actor {
				log_messagef(game, "Spikes shoot from the floor! (-%5 HP)")
			}
		case .Snare:
			if is_player_actor {
				actor.stunned_turns = 2
				if is_player_actor {
					log_messagef(game, "A snare catches your leg! You're stunned.")
				}
			} else {
				actor.stunned_turns = 2
			}
		case .Alarm:
			// This may be a bit too aggressive haha TODO
			for &a in game.actors {
				if e, ok := &a.data.(Enemy_Data); ok {
					e.ai_state = .Hunting
					e.last_known_x = trap.x
					e.last_known_y = trap.y
				}
			}
			log_messagef(game, "A shrill alarm sounds!")
		case .Gas:
			if is_player_actor {
				pd := actor.data.(Player_Data)
				if .Iron_Lungs not_in pd.boons {
					if data := &actor.data.(Player_Data); true {
						data.lantern.fuel -= 50 // TODO make sure this is working
						if data.lantern.fuel < 0 {data.lantern.fuel = 0}
					}
					log_messagef(game, "Choking gas! Your lantern dims.")
				} else {
					log_messagef(game, "Choking gas -- but your lungs hold")
				}
			}
		case .Pit:
			actor.hp -= 3
			if is_player_actor {
				log_messagef(game, "You fall into a pit! (-3 HP)")
			}
		}

		// Check death
		if actor.hp <= 0 && is_player_actor {
			// Death handled by caller checking hp
			// TODO
		}
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
