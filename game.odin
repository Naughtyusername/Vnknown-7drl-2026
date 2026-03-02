package sdrl

import "core:fmt"
import rl "vendor:raylib"

MAP_WIDTH :: 25
MAP_HEIGHT :: 25
VIEWPORT_WIDTH :: 60
VIEWPORT_HEIGHT :: 34

TILE_SIZE :: 20

SCREEN_W :: VIEWPORT_WIDTH * TILE_SIZE
SCREEN_H :: VIEWPORT_HEIGHT * TILE_SIZE

// Map generation constants
CA_WALL_PROB :: 0.42
CA_SMOOTHING :: 5
ROOM_COUNT_MIN :: 4
ROOM_COUNT_MAX :: 7
ROOM_SIZE_MIN :: 5
ROOM_SIZE_MAX :: 10

// Mutable Variants
fov_radius: int = 10 // TODO: dynamic lighting via lantern
screen_w: int
screen_h: int

draw_debug_overlay := false
draw_light_debug_overlay := false

Tile :: enum {
	Floor,
	Wall,
	Water,
	Stairs_Down,
	Tile_Max,
}

Action :: enum {
	Move,
	Attack,
	Wait,
	PickupItem,
	CastSpell,
	UseItem,
}

// TODO: improve scheduler — starts 1 tick ahead of turn
Scheduler :: struct {
	actors:       [dynamic]^Actor,
	current_time: int,
}

Camera :: struct {
	x:               int, // Top-left corner in world coordinates
	y:               int,
	viewport_width:  int, // In tiles
	viewport_height: int, // In tiles
}

Actor :: struct {
	id:        int,
	x, y:      int,
	hp:        int,
	time_next: int,
	speed:     int,
	data:      Actor_Data,
}

Actor_Data :: union {
	Player_Data,
	Enemy_Data,
}

Player_Data :: struct {
	color: rl.Color,
	char:  cstring,
}

Enemy_Data :: struct {
	color: rl.Color,
	char:  cstring,
}

Debug_Throttle :: struct {
	last_time: f64,
	interval:  f64,
}

Game :: struct {
	map_width:       int,
	map_height:      int,
	tiles:           [dynamic][dynamic]Tile,
	revealed:        [dynamic][dynamic]bool,
	visible:         [dynamic][dynamic]bool,
	light_map:       [dynamic][dynamic]rl.Color,
	actors:          [dynamic]Actor,
	player_index:    int, // Index of player in actors array (always 0)
	camera:          Camera,
	turn_count:      int,
	current_time:    int,
	scheduler:       Scheduler,
	quit:            bool,
	current_floor:   int,
	logger:          Logger,
	debug_throttles: map[string]Debug_Throttle,
	crash_logger:    Logger,
	game_log:        Message_Log,
	combat_log:      Message_Log,
	debug_log:       Message_Log,

	// Debug: Track how many times each tile receives light
	light_hit_count: [dynamic][dynamic]int,
}

init_game :: proc(width, height: int) -> Game {
	game := Game {
		map_width  = width,
		map_height = height,
	}

	game.current_floor = 0

	game.tiles = make([dynamic][dynamic]Tile, height)
	game.revealed = make([dynamic][dynamic]bool, height)
	game.visible = make([dynamic][dynamic]bool, height)
	game.light_map = make([dynamic][dynamic]rl.Color, height)

	game.light_hit_count = make([dynamic][dynamic]int, game.map_height)
	for y in 0 ..< game.map_height {
		game.light_hit_count[y] = make([dynamic]int, game.map_width)
	}

	for i in 0 ..< height {
		game.tiles[i] = make([dynamic]Tile, width)
		game.revealed[i] = make([dynamic]bool, width)
		game.visible[i] = make([dynamic]bool, width)
		game.light_map[i] = make([dynamic]rl.Color, width)
	}

	game.actors = make([dynamic]Actor, 0, 50)

	game.camera = Camera {
		x               = 0,
		y               = 0,
		viewport_width  = VIEWPORT_WIDTH,
		viewport_height = VIEWPORT_HEIGHT,
	}

	player := Actor {
		id = 0,
		x = width / 2,
		y = height / 2,
		hp = 100,
		time_next = 0,
		speed = 100,
		data = Player_Data{color = sample_color(PLAYER)},
	}
	append(&game.actors, player)
	game.player_index = 0

	game.game_log = init_message_log(1000)
	game.combat_log = init_message_log(1000)
	game.debug_log = init_message_log(1000)

	logger, ok := init_logger("game")
	if !ok {
		fmt.println("[WARNING] Logging disabled - could not open log file")
	}
	game.logger = logger
	log_gamef(&game, .INFO, "Map initialized: %dx%d", width, height)

	crash_logger, crash_ok := init_logger_simple("./logs/crash.log")
	if !crash_ok {
		log_gamef(&game, .WARN, "crash logger unavailable - could not open ./logs/crash.log")
	}
	game.crash_logger = crash_logger

	when ODIN_DEBUG {
		game.debug_throttles = make(map[string]Debug_Throttle)
	}
	return game
}

// TODO make or port over the state manager system/file.
update_game :: proc(sm: ^State_Manager) {
	if len(sm.stack) == 0 {return}

	top := &sm.stack[len(sm.stack) - 1]
	top.update(sm, top.data)
}

cleanup_game :: proc(game: ^Game) {
	for i in 0 ..< game.map_height {
		delete(game.tiles[i])
		delete(game.revealed[i])
		delete(game.visible[i])
		delete(game.light_map[i])
	}

	delete(game.tiles)
	delete(game.revealed)
	delete(game.visible)
	delete(game.light_map)
	delete(game.actors)
	delete(game.scheduler.actors)

	cleanup_messages_log(&game.game_log)
	cleanup_messages_log(&game.combat_log)
	cleanup_messages_log(&game.debug_log)

	when ODIN_DEBUG {
		for row in game.light_hit_count {
			delete(row)
		}
		delete(game.light_hit_count)
	}

	when ODIN_DEBUG {
		delete(game.debug_throttles)
	}

	// Loggers last — keep alive for final writes
	cleanup_logger(&game.logger)
	cleanup_logger(&game.crash_logger)
}

get_tile :: proc(game: ^Game, x, y: int) -> Tile {
	if x < 0 || x >= game.map_width || y < 0 || y >= game.map_height {
		return .Wall
	}
	return game.tiles[y][x]
}

set_tile :: proc(game: ^Game, x, y: int, tile: Tile) {
	if x >= 0 && x < game.map_width && y >= 0 && y < game.map_height {
		game.tiles[y][x] = tile
	}
}

in_bounds :: proc(game: ^Game, x, y: int) -> bool {
	return x >= 0 && x < game.map_width && y >= 0 && y < game.map_height
}

get_player :: proc(game: ^Game) -> ^Actor {
	return &game.actors[game.player_index]
}

enemy_at :: proc(game: ^Game, x, y: int) -> bool {
	for &actor in game.actors {
		if _, ok := actor.data.(Enemy_Data); ok {
			if actor.x == x && actor.y == y {
				return true
			}
		}
	}
	return false
}

is_player :: proc(actor: ^Actor) -> bool {
	_, ok := actor.data.(Player_Data)
	return ok
}

get_action_cost :: proc(action: Action) -> int {
	switch action {
	case .Move:
		return 100
	case .Attack:
		return 100
	case .Wait:
		return 100
	case .PickupItem:
		return 100
	case .CastSpell:
		return 150
	case .UseItem:
		return 100
	}
	return 100
}

schedule_actor :: proc(scheduler: ^Scheduler, actor: ^Actor) {
	append(&scheduler.actors, actor)

	// keep sorted by time_next (bubble up)
	i := len(scheduler.actors) - 1
	for i > 0 && scheduler.actors[i].time_next < scheduler.actors[i - 1].time_next {
		scheduler.actors[i], scheduler.actors[i - 1] = scheduler.actors[i - 1], scheduler.actors[i]
		i -= 1
	}
}

pop_next_actor :: proc(scheduler: ^Scheduler) -> ^Actor {
	if len(scheduler.actors) == 0 {
		return nil
	}

	// O(n) insertion, fine for ~50 actors — optimize to min-heap if needed
	actor := scheduler.actors[0]
	ordered_remove(&scheduler.actors, 0)
	return actor
}

log_debug_categoryf :: proc(
	game: ^Game,
	category: string,
	interval: f64,
	format: string,
	args: ..any,
) {
	when ODIN_DEBUG {
		message := fmt.aprintf(format, ..args)
		defer delete(message)
		log_debug_category(game, category, message, interval)
	}
}

log_debug_category :: proc(game: ^Game, category: string, message: string, interval: f64) {
	when ODIN_DEBUG {
		current_time := rl.GetTime()

		throttle, exists := game.debug_throttles[category]
		if !exists {
			throttle = Debug_Throttle {
				last_time = 0.0,
				interval  = interval,
			}
		}

		elapsed := current_time - throttle.last_time
		if elapsed >= interval {
			formatted := fmt.aprintf("[%s] %s", category, message)
			defer delete(formatted)

			log_to_file(&game.logger, .DEBUG, formatted)

			throttle.last_time = current_time
			game.debug_throttles[category] = throttle
		}
	}
}

// Unified logging: file (always) + console (debug only)
log_game :: proc(game: ^Game, level: Log_Level, message: string) {
	log_to_file(&game.logger, level, message)

	if level == .ERROR {
		log_to_file(&game.crash_logger, level, message)
	}

	when ODIN_DEBUG {
		prefix: string
		switch level {
		case .DEBUG:
			prefix = "[DEBUG]"
		case .INFO:
			prefix = "[INFO ]"
		case .WARN:
			prefix = "[WARN ]"
		case .ERROR:
			prefix = "[ERROR]"
		}
		fmt.printf("%s %s\n", prefix, message)
	}
}

log_gamef :: proc(game: ^Game, level: Log_Level, format: string, args: ..any) {
	message := fmt.aprintf(format, ..args)
	defer delete(message) // tprintf allocates, must free
	log_game(game, level, message)
}

descend_floor :: proc(game: ^Game) {
	game.current_floor += 1

	// Free old map data (rows only - outer arrays stay allocated)
	for y in 0 ..< game.map_height {
		// Rest to defaults instead of free+realloc
		for x in 0 ..< game.map_width {
			game.tiles[y][x] = .Floor
			game.revealed[y][x] = false
			game.visible[y][x] = false
			game.light_map[y][x] = LIGHT_NONE
		}
	}

	// keep only the player
	resize(&game.actors, 1)

	// Later: full heal on floor transition

	// Generate new floor
	generate_dungeon(game)

	// Rebuild scheduler
	clear(&game.scheduler.actors)
	for &actor in game.actors {
		schedule_actor(&game.scheduler, &actor)
	}

    // Center cameraand recompute FOV
    player := get_player(game)
    center_camera(&game.camera, player.x, player.y, game.map_width,
                 game.map_height)
    compute_fov(game, player.x, player.y, fov_radius)

    log_messagef(game, "You descend to floor %d...", game.current_floor)
}
