package sdrl

import "core:fmt"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

MAP_WIDTH :: 50
MAP_HEIGHT :: 50
VIEWPORT_WIDTH :: 60
VIEWPORT_HEIGHT :: 34

TILE_SIZE :: 24 // TODO offer a set of options possibly, but 24-28 like in cogmind
// works best for my blind ass. 20 was fun but to smol.

// will tweak later
HUD_HEIGHT :: 44 // 2 lines x ~20px + 4px padding
MSG_HEIGHT :: 64 // 5 lines x ~20px + 4px padding

MAP_AREA_Y :: MSG_HEIGHT
HUD_AREA_Y :: MSG_HEIGHT + (VIEWPORT_HEIGHT * TILE_SIZE)

SCREEN_W :: VIEWPORT_WIDTH * TILE_SIZE
SCREEN_H :: MSG_HEIGHT + (VIEWPORT_HEIGHT * TILE_SIZE) + HUD_HEIGHT

// Map generation constants
CA_WALL_PROB :: 0.52
CA_SMOOTHING :: 3
ROOM_COUNT_MIN :: 4
ROOM_COUNT_MAX :: 7
ROOM_SIZE_MIN :: 5
ROOM_SIZE_MAX :: 10

MAX_LANTERN_RADIUS :: 8
MAX_FOV_RADIUS :: 12 // how far player can see when not in darkness/blinded
BASE_SPEED :: 100 // for speed based math calls that dont need go off of actor.speed, standard value

// Mutable Variants
fov_radius: int = 10 // TODO: dynamic lighting via lantern // adjust this when level gen is better.
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
	UseItem,
}

Action_Result :: struct {
	action: Action,
	cost:   int,
}

Enemy_Tag :: enum {
	Carries_Light,
	Dark_Vision,
	Smell_Based,
	Large,
	Stealthy,
}

Enemy_Type :: enum {
	Thrall,
	Wolf,
	Shade,
	Lantern_Pest,
	Skeleton_Knight,
	Wraith,
}

Potion_Type :: enum {
	Healing,
	Fuel, // portable fuel in emergencies
	Clarity, // see items/stairs, etc.
	Blindness, // lights out
	Confusion, // shrooms
	Fire, // ouch + light
	Darkness,
}

Potion_Data :: struct {
	type: Potion_Type,
}

Scroll_Type :: enum {
	Enchantment, // +1 TODO give player a armor piece to upgrade with this for defense.
	Map_Reveal, // TODO rip this from the main game
	Hostile_Tracking, // brogue twinkles.
	Identify, // id items might get nixed.
	Summoning, // pray for help buddy.
}

Scroll_Data :: struct {
	type: Scroll_Type,
}

Item :: struct {
	id:   int,
	data: Item_Data,
	x, y: int,
}

Item_Data :: union {
	Potion_Data,
	Scroll_Data,
	Ring_Data,
}

item_name :: proc(item: Item) -> string {
	#partial switch d in item.data {
	case Potion_Data:
		switch d.type {
		case .Healing:
			return "Potion of Healing"
		case .Fuel:
			return "Oil Flask"
		case .Clarity:
			return "Potion of Clarity"
		case .Blindness:
			return "Potion of Blindness"
		case .Confusion:
			return "Potion of Confusion"
		case .Fire:
			return "Fire Potion"
		case .Darkness:
			return "Potion of Darkness"
		}
	case Scroll_Data:
		switch d.type {
		case .Map_Reveal:
			return "Scroll of Revelation"
		case .Enchantment:
			return "Scroll of Enchantment"
		case .Hostile_Tracking:
			return "Scroll of Tracking"
		case .Identify:
			return "Scroll of Identify"
		case .Summoning:
			return "Scroll of Summoning"
		}
	//case Ring_Data:
	// switch d.type {
	// case .RingNames:

	//}
	}
	return "Unknown Item"
}

use_item :: proc(game: ^Game, idx: int) {
	player := get_player(game)
	pd := &player.data.(Player_Data)
	if idx < 0 || idx >= len(pd.inventory) {return}
	item := pd.inventory[idx]

	#partial switch d in item.data {
	case Potion_Data:
		#partial switch d.type {
		case .Healing:
			healed := min(10, player.max_hp - player.hp)
			player.hp += healed
			log_messagef(game, "The potion mends your wounds. (+%d HP)", healed)
		case .Fuel:
			added := min(100, pd.lantern.max_fuel - pd.lantern.fuel)
			pd.lantern.state = .Empty;{pd.lantern.state = .Lit}
			log_messagef(game, "You refuel the lantern. (+%d)", added)
		case .Clarity, .Blindness, .Confusion, .Fire, .Darkness:
			log_messagef(game, "You drink the potion. (TODO copy from main game)")
		}
	case Scroll_Data:
		switch d.type {
		case .Map_Reveal:
			for y in 0 ..< game.map_height {
				for x in 0 ..< game.map_width {
					game.revealed[y][x] = true
				}
			}
			log_messagef(game, "The map floods your mind!")
		case .Enchantment, .Hostile_Tracking, .Identify, .Summoning:
			log_messagef(game, "You read the scroll. TODO")
		}
	}

	unordered_remove(&pd.inventory, idx)
}

drop_item :: proc(game: ^Game, idx: int) {
	player := get_player(game)
	pd := &player.data.(Player_Data)
	if idx < 0 || idx >= len(pd.inventory) {return}
	item := pd.inventory[idx]
	item.x = player.x
	item.y = player.y
	append(&game.items, item)
	log_messagef(game, "You drop the %s.", item_name(item))
	unordered_remove(&pd.inventory, idx)

}

Ring_Type :: enum {
	Fuel_Ward, // slows lantern drain
	Stone_Skin, // +2 DR
	Swiftness, // +x move speed
	Shadow_Step, // lowers enemy spot range
	Ember_Light, // +n lantern radius (1-3?..)
	Void_Eye, // +n dark vision radius
}

Ring_Data :: struct {
	type: Ring_Type,
}

AI_State :: enum {
	Idle,
	Hunting,
	Roaming,
	Fleeing,
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
	// base stats
	id:            int,
	x, y:          int,
	hp:            int,
	alive:         bool,
	max_hp:        int,
	time_next:     int,
	speed:         int,
	// data
	data:          Actor_Data,
	stunned_turns: int,
}

Actor_Data :: union {
	Player_Data,
	Enemy_Data,
}

Player_Data :: struct {
	color:         rl.Color,
	char:          cstring,
	lantern:       Lantern,
	gold:          int,
	inventory:     [dynamic]Item,
	active_weapon: Weapon_Type, // TODO change to 1 to make whip default.
	last_dx:       int,
	last_dy:       int,
	boons:         bit_set[Player_Boon],
	sanity:        int,
	// curses / negatives
	ring:          Maybe(Ring_Type),
}

Player_Boon :: enum {
	Trap_Sight,
	Fuel_Efficiency,
	Quick_Hands,
	Dark_Adapted,
	Thick_Skin,
	Iron_Lungs,
	Keen_Nose,
	Blood_Scent,
}

Enemy_Data :: struct {
	name:         string,
	color:        rl.Color,
	char:         cstring,
	damage:       int,
	vision_range: int,
	light_radius: int,
	enemy_type:   Enemy_Type,
	ai_state:     AI_State,
	tags:         bit_set[Enemy_Tag],
	last_known_x: int,
	last_known_y: int,
}

Debug_Throttle :: struct {
	last_time: f64,
	interval:  f64,
}

Weapon_Type :: enum {
	Dagger,
	Whip,
}

Weapon_Stats :: struct {
	damage:           int,
	speed:            int,
	max_range:        int,
	get_weapon_stats: int,
	ability_cost:     int,
	swap_cost:        int,
}

get_weapon_stats :: proc(weapon: Weapon_Type) -> Weapon_Stats {
	switch weapon {
	case .Dagger:
		return Weapon_Stats {
			damage = 6,
			speed = 80,
			max_range = 1,
			ability_cost = 0,
			swap_cost = 60,
		}
	case .Whip:
		return Weapon_Stats {
			damage = 4,
			speed = 100,
			max_range = 3,
			ability_cost = 150,
			swap_cost = 120,
		}
	}
	return Weapon_Stats{damage = 6, speed = 80, max_range = 1}
}

Boon_Pedistal :: struct {
	x, y:   int,
	active: bool,
}

Gold_Pile :: struct {
	x, y:   int,
	amount: int,
}

Trap_Type :: enum {
	Spike,
	Snare,
	Alarm,
	Gas,
	Pit,
}

Trap :: struct {
	x, y:      int,
	type:      Trap_Type,
	revealed:  bool,
	triggered: bool,
}

Game :: struct {
	map_width:         int,
	map_height:        int,
	tiles:             [dynamic][dynamic]Tile,
	revealed:          [dynamic][dynamic]bool,
	visible:           [dynamic][dynamic]bool,
	light_map:         [dynamic][dynamic]rl.Color,
	actors:            [dynamic]Actor,
	player_index:      int, // Index of player in actors array (always 0)
	camera:            Camera,
	turn_count:        int,
	current_time:      int,
	scheduler:         Scheduler,
	// Map gen stuff
	treasure_room:     Maybe(Rectangle),
	pedestal:          Maybe(Boon_Pedistal),
	gold_piles:        [dynamic]Gold_Pile,
	// quitter
	quit:              bool,
	wants_restart:     bool,
	// Traps
	traps:             [dynamic]Trap,
	// Items / inv
	items:             [dynamic]Item,
	// status
	last_action_cost:  int,
	current_floor:     int,
	death_cause:       string, // "Thrall", "Wolf" - set when player dies
	enemies_slain:     int,
	next_wraith_spawn: int,
	wraith_count:      int,
	// log/debug
	logger:            Logger,
	debug_throttles:   map[string]Debug_Throttle,
	crash_logger:      Logger,
	game_log:          Message_Log,
	combat_log:        Message_Log,
	debug_log:         Message_Log,

	// Debug: Track how many times each tile receives light
	light_hit_count:   [dynamic][dynamic]int,
}

init_game :: proc(width, height: int) -> Game {
	game := Game {
		map_width  = width,
		map_height = height,
	}

	game.current_floor = 1

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

	// Actor allocation
	game.actors = make([dynamic]Actor, 0, 300)

	// Items / Inv
	game.items = make([dynamic]Item, 0, 32)

	// Traps
	game.traps = make([dynamic]Trap, 0, 32)

	// Gold piles
	game.gold_piles = make([dynamic]Gold_Pile, 0, 16)

	// Camera
	game.camera = Camera {
		x               = 0,
		y               = 0,
		viewport_width  = VIEWPORT_WIDTH,
		viewport_height = VIEWPORT_HEIGHT,
	}

	// Player Init
	player := Actor {
		id = 0,
		x = width / 2,
		y = height / 2,
		hp = 20,
		alive = true,
		max_hp = 20,
		time_next = 0,
		speed = 100,
		data = Player_Data {
			color = sample_color(PLAYER),
			lantern = Lantern{state = .Lit, fuel = 300, max_fuel = 300},
			active_weapon = .Whip,
			last_dx = 0,
			last_dy = 1,
			sanity = 100,
		},
	}
	append(&game.actors, player)
	if pd, ok := &game.actors[0].data.(Player_Data); ok {
		pd.inventory = make([dynamic]Item, 0, 26) // a-z
	}
	game.player_index = 0 // TODO isnt player supposed to always be 1?... double check this is not broken

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

	player := get_player(game)
	if pd, ok := &player.data.(Player_Data); ok {
		delete(pd.inventory)
	}

	delete(game.tiles)
	delete(game.revealed)
	delete(game.visible)
	delete(game.light_map)
	delete(game.actors)
	delete(game.scheduler.actors)
	delete(game.traps)
	delete(game.gold_piles)
	delete(game.items)

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

restart_game :: proc(game: ^Game) {
	player := get_player(game)
	player.hp = player.max_hp
	player.time_next = 0

	for y in 0 ..< game.map_height {
		for x in 0 ..< game.map_width {
			game.revealed[y][x] = false
			game.visible[y][x] = false
		}
	}

	// Clean up map before generate dungeon replaces things
	game.treasure_room = nil
	game.pedestal = nil
	clear(&game.traps)
	clear(&game.gold_piles)
	clear(&game.items)
	game.next_wraith_spawn = 150
	game.wraith_count = 0

	if pd, ok := &get_player(game).data.(Player_Data); ok {
		clear(&pd.inventory)
	}

	resize(&game.actors, 1)
	generate_dungeon(game)

	clear(&game.scheduler.actors)
	player = get_player(game)
	for &actor in game.actors {
		schedule_actor(&game.scheduler, &actor)
	}

	game.current_floor = 1
	game.turn_count = 0
	game.enemies_slain = 0

	center_camera(&game.camera, player.x, player.y, game.map_width, game.map_height)
	fov_r, lantern_r := get_fov_radii(game)
	compute_fov(game, player.x, player.y, fov_r, lantern_r)
}

// === HELPER Functions ===
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
		if !actor.alive {continue}
		if _, ok := actor.data.(Enemy_Data); ok {
			if !actor.alive {continue}
			if actor.x == x && actor.y == y {
				return true
			}
		}
	}
	return false
}

get_enemy_at :: proc(game: ^Game, x, y: int) -> ^Actor {
	for &actor in game.actors {
		if _, ok := actor.data.(Enemy_Data); !ok {continue}
		if !actor.alive {continue}
		if actor.x == x && actor.y == y {return &actor}
	}
	return nil
}

is_player :: proc(actor: ^Actor) -> bool {
	_, ok := actor.data.(Player_Data)
	return ok
}

// === Lantern / Fov ===
Lantern_State :: enum {
	Lit,
	Extinguished, // blown out from trap or enemy etc. - re-light with flint
	Empty, // no fuel, flint wont help
	// dropped?
}

Lantern :: struct {
	state:    Lantern_State,
	fuel:     int,
	max_fuel: int,
}

get_fov_radii :: proc(game: ^Game) -> (fov_r: int, lantern_r: int) {
	player_data := get_player(game).data.(Player_Data)
	fov_r = MAX_FOV_RADIUS
	lantern_r = 0
	switch player_data.lantern.state {
	case .Lit:
		lantern_r = calculate_lantern_radius(player_data.lantern)
	case .Extinguished:
		fov_r = MAX_LANTERN_RADIUS
	case .Empty:
		fov_r = 1
	}
	return
}

calculate_lantern_radius :: proc(lantern: Lantern) -> int {
	if lantern.state != .Lit || lantern.fuel <= 0 {return 0}
	ratio := f32(lantern.fuel) / f32(lantern.max_fuel)
	// math.round before int() is critical — truncation alone drops the radius on the first fuel tick.
	// pow(0.3) keeps it near max for ~80% of fuel, then steps down. First drop happens around turn 60.
	return clamp(
		int(math.round(math.pow(ratio, 0.3) * f32(MAX_LANTERN_RADIUS))),
		0,
		MAX_LANTERN_RADIUS,
	)
}

drain_fuel :: proc(game: ^Game) {
	player := get_player(game)
	data, ok := &player.data.(Player_Data)
	if !ok {return}

	if data.lantern.state != .Lit {return}

	if .Fuel_Efficiency in data.boons {
		if game.turn_count % 2 == 0 {data.lantern.fuel -= 1}
	} else {
		data.lantern.fuel -= 1
	}

	// Threshold warnings
	switch {
	case data.lantern.fuel == data.lantern.max_fuel / 2:
		log_messagef(game, "Your lantern flickers briefly...")
	case data.lantern.fuel == data.lantern.max_fuel / 4:
		log_messagef(game, "The flame sputters -- fuel is running low")
	case data.lantern.fuel == data.lantern.max_fuel / 10:
		log_messagef(game, "Your lantern is but a spark.")
	case data.lantern.fuel <= 0:
		data.lantern.state = .Empty
		log_messagef(game, "Your lantern fades away.")
	}
}

// === ACTION economy / scheudler queue ===
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

// === LOGGING / debug etc.
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

// === flooor ascention / descention logic / debug / reset game

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

	// Clean up map before generate dungeon replaces things
	game.treasure_room = nil
	game.pedestal = nil
	clear(&game.traps)
	clear(&game.gold_piles)
	clear(&game.items)
	game.next_wraith_spawn = 150
	game.wraith_count = 0

	// Generate new floor
	generate_dungeon(game)

	// Rebuild scheduler
	clear(&game.scheduler.actors)
	for &actor in game.actors {
		schedule_actor(&game.scheduler, &actor)
	}

	// Center cameraand recompute FOV
	player := get_player(game)
	center_camera(&game.camera, player.x, player.y, game.map_width, game.map_height)

	fov_r, lantern_r := get_fov_radii(game)
	compute_fov(game, player.x, player.y, fov_r, lantern_r)
	player.max_hp += 5 // fixed player scaling value
	player.hp = player.max_hp

	log_messagef(game, "You descend to floor %d...", game.current_floor)
}

ascend_floor :: proc(game: ^Game) {
	game.current_floor -= 1

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

	// Clean up map before generate dungeon replaces things
	game.treasure_room = nil
	game.pedestal = nil
	clear(&game.traps)
	clear(&game.gold_piles)
	clear(&game.items)
	game.next_wraith_spawn = 150
	game.wraith_count = 0

	// Generate new floor
	generate_dungeon(game)

	// Rebuild scheduler
	clear(&game.scheduler.actors)
	for &actor in game.actors {
		schedule_actor(&game.scheduler, &actor)
	}

	// Center cameraand recompute FOV
	player := get_player(game)
	center_camera(&game.camera, player.x, player.y, game.map_width, game.map_height)

	fov_r, lantern_r := get_fov_radii(game)
	compute_fov(game, player.x, player.y, fov_r, lantern_r)
	player.hp = player.max_hp

	log_messagef(game, "You descend to floor %d...", game.current_floor)
}

// === BOONS
grant_random_boon :: proc(game: ^Game) {
	player := get_player(game)
	pd := &player.data.(Player_Data)

	available: [8]Player_Boon
	count := 0
	for boon in Player_Boon {
		if boon not_in pd.boons {
			available[count] = boon
			count += 1
		}
	}
	if count == 0 {
		log_messagef(game, "The pedestal has nothing more to offer.")
		return
	}

	chosen := available[rand.int_max(count)]
	pd.boons += {chosen}
	log_messagef(game, "The altar grants you: %s", boon_name(chosen))
}

boon_name :: proc(boon: Player_Boon) -> string {
	switch boon {
	case .Trap_Sight:
		return "Trap Sight"
	case .Fuel_Efficiency:
		return "Fuel Efficiency"
	case .Quick_Hands:
		return "Quick Hands"
	case .Dark_Adapted:
		return "Dark Adapted"
	case .Thick_Skin:
		return "Thick Skin"
	case .Iron_Lungs:
		return "Iron Lungs"
	case .Keen_Nose:
		return "Keen Nose"
	case .Blood_Scent:
		return "Blood Scent"
	}
	return "Unknown Boon"
}

// GOLD
try_pickup_gold :: proc(game: ^Game) {
	player := get_player(game)
	pd := &player.data.(Player_Data)

	for i := len(game.gold_piles) - 1; i >= 0; i -= 1 {
		pile := game.gold_piles[i]
		if pile.x == player.x && pile.y == player.y {
			pd.gold += pile.amount
			log_messagef(game, "You pocket %d gold.", pile.amount)
			unordered_remove(&game.gold_piles, i)
		}
	}
}
