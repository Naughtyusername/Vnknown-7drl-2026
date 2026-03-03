package sdrl

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

Message_Type :: enum {
	Game,
	Combat,
	Debug,
}

Message :: struct {
	text:      string,
	type:      Message_Type,
	turn:      int,
    game_time: int,
	color:     rl.Color,
	timestamp: f64,
}

Message_Log :: struct {
	messages:      [dynamic]Message,
	max_size:      int,
	scroll_offset: int,
}

init_message_log :: proc(max_size: int = 1000) -> Message_Log {
	message_log := Message_Log {
		messages      = make([dynamic]Message),
		max_size      = max_size,
		scroll_offset = 0,
	}

	return message_log
}

cleanup_messages_log :: proc(log: ^Message_Log) {
	for msg in log.messages {
		delete(msg.text)
	}
	delete(log.messages)
}

get_message_color :: proc(type: Message_Type) -> rl.Color {
	switch type {
	case .Game:
		return rl.WHITE
	case .Combat:
		return rl.RED
	case .Debug:
		return rl.YELLOW
	}
    return rl.WHITE
}

log_message :: proc(game: ^Game, text: string, type: Message_Type = .Game) {
	msg := Message {
		text      = strings.clone(text), // Clone because callers string may be temporary
		type      = type,
		turn      = game.turn_count,
        game_time = game.current_time,
		color     = get_message_color(type),
		timestamp = rl.GetTime(),
	}

	switch type {
	case .Combat:
		append(&game.combat_log.messages, msg)
	case .Debug:
		append(&game.debug_log.messages, msg)
	case .Game:
		append(&game.game_log.messages, msg)
	}

	if len(game.game_log.messages) > game.game_log.max_size {
		delete(game.game_log.messages[0].text)
		ordered_remove(&game.game_log.messages, 0)
	}
	if len(game.combat_log.messages) > game.combat_log.max_size {
		delete(game.combat_log.messages[0].text)
		ordered_remove(&game.combat_log.messages, 0)
	}
	if len(game.debug_log.messages) > game.debug_log.max_size {
		delete(game.debug_log.messages[0].text)
		ordered_remove(&game.debug_log.messages, 0)
	}

}

log_messagef :: proc(game: ^Game, format: string, args: ..any) {
	text := fmt.tprintf(format, ..args)
	log_message(game, text, .Game)
}

log_combat :: proc(game: ^Game, format: string, args: ..any) {
	text := fmt.tprintf(format, ..args)
	log_message(game, text, .Combat)
}

log_debug :: proc(game: ^Game, format: string, args: ..any) {
	text := fmt.tprintf(format, ..args)
	log_message(game, text, .Debug)
}
