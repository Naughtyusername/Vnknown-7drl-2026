package sdrl

PLAYER_BASE_DAMAGE :: 6

kill_enemy :: proc(game: ^Game, target: ^Actor) {
	target.alive = false
	if enemy_data, ok := target.data.(Enemy_Data); ok {
		log_combat(game, "The %s dies!", enemy_data.name)
	}
}

resolve_player_attack :: proc(game: ^Game, attacker: ^Actor, target: ^Actor) {
	damage := PLAYER_BASE_DAMAGE
	target.hp -= damage
	if enemy_data, ok := target.data.(Enemy_Data); ok {
		log_combat(game, "You strike the %s for %d damage!", enemy_data.name, damage)
	}
	if target.hp <= 0 {
		kill_enemy(game, target)
	}
}

resolve_enemy_attack :: proc(game: ^Game, enemy: Actor, player: ^Actor) {
	enemy_data, ok := enemy.data.(Enemy_Data)
	if !ok { return }

	player.hp -= enemy_data.damage
	log_combat(game, "The %s hits you for %d!", enemy_data.name,
			  enemy_data.damage)
}
