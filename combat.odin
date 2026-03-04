package sdrl

kill_enemy :: proc(game: ^Game, target: ^Actor) {
	target.alive = false

	game.enemies_slain += 1

	if enemy_data, ok := target.data.(Enemy_Data); ok {
		log_combat(game, "The %s dies!", enemy_data.name)
	}
}

resolve_player_attack :: proc(game: ^Game, attacker: ^Actor, target: ^Actor) {
	player := get_player(game)
	player_data, ok := player.data.(Player_Data)
	if !ok {return}

	stats := get_weapon_stats(player_data.active_weapon)
	damage := stats.damage
	if player_data.active_weapon != .Whip {
		game.last_action_cost = stats.speed
	}

	target.hp -= damage
	if enemy_data, e_ok := target.data.(Enemy_Data); e_ok {
		log_combat(game, "You strike the %s for %d damage!", enemy_data.name, damage)
	}
	if target.hp <= 0 {
		kill_enemy(game, target)
	}
}

resolve_enemy_attack :: proc(game: ^Game, enemy: Actor, player: ^Actor) {
	enemy_data, ok := enemy.data.(Enemy_Data)
	if !ok {return}

	game.death_cause = enemy_data.name // sets death flag name were this hit to be the last hit
	player.hp -= enemy_data.damage
	log_combat(game, "The %s hits you for %d!", enemy_data.name, enemy_data.damage)
}
