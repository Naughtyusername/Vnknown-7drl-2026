package sdrl

import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:strings"

place_stairs :: proc(game: ^Game) {
	player := get_player(game)

	// 2D distance array, -1 = unvisited
	dist := make([dynamic][dynamic]int, game.map_height)
	defer {
		for row in dist {delete(row)}
		delete(dist)
	}
	for y in 0 ..< game.map_height {
		dist[y] = make([dynamic]int, game.map_width)
		for x in 0 ..< game.map_width {
			dist[y][x] = -1
		}
	}

	// FIFO queue
	Queue_Entry :: struct {
		x, y: int,
	}
	queue := make([dynamic]Queue_Entry, 0, 256)
	defer delete(queue)

	// Seed with player pos
	dist[player.y][player.x] = 0
	append(&queue, Queue_Entry{player.x, player.y})
	head := 0 // index into queue for FIFO behavior

	// BFS loop
	for head < len(queue) {
		current := queue[head]
		head += 1

		current_dist := dist[current.y][current.x]

		// 4-directional neighbors ( not 8 - don't want stairs to require diagonal only paths. )
		for dir in ([4][2]int{{0, -1}, {0, 1}, {-1, 0}, {1, 0}}) {
			nx := current.x + dir[0]
			ny := current.y + dir[1]

			if !in_bounds(game, nx, ny) {continue}
			if dist[ny][nx] != -1 {continue} 	// already visited
			if game.tiles[ny][nx] == .Wall {continue}

			dist[ny][nx] = current_dist + 1
			append(&queue, Queue_Entry{nx, ny})
		}
	}

	// Find farthest reachable tile, prefer opposite quadrant
	player_quadrant_x := player.x < game.map_width / 2 // true = left half
	player_quadrant_y := player.y < game.map_height / 2 // true = top half

	best_x, best_y := player.x, player.y
	best_dist := 0
	best_opposite := false

	for y in 0 ..< game.map_height {
		for x in 0 ..< game.map_width {
			d := dist[y][x]
			if d <= 0 {continue}
			if game.tiles[y][x] != .Floor {continue}

			// Is this tile in the opposite quadrant?
			opp_x := (x < game.map_width / 2) != player_quadrant_x
			opp_y := (y < game.map_height / 2) != player_quadrant_y
			is_opposite := opp_x && opp_y

			// Prefer: opposite quadrant first, then max distance
			if is_opposite && !best_opposite {
				// First opposite-quadrant candidate always wins
				best_x, best_y = x, y
				best_dist = d
				best_opposite = true
			} else if is_opposite == best_opposite && d > best_dist {
				// Same quadrant preference, pick farther
				best_x, best_y = x, y
				best_dist = d
			}
		}
	}

	game.tiles[best_y][best_x] = .Stairs_Down
}

// super basic shit, will rip later.
generate_dungeon :: proc(game: ^Game) {
	generate_ca_caves(game, CA_WALL_PROB, CA_SMOOTHING)

	num_rooms := rand.int_max(ROOM_COUNT_MAX - ROOM_COUNT_MIN + 1) + ROOM_COUNT_MIN
	rooms := make([dynamic]Rectangle, 0, num_rooms)
	defer delete(rooms)

	max_attempts := num_rooms * 3
	for _ in 0 ..< max_attempts {
		if len(rooms) >= num_rooms {
			break
		}

		room := generate_random_room(game)
		if can_place_room(game, room, rooms, 2) {
			carve_room(game, room)
			append(&rooms, room)
		}
	}

	if len(rooms) > 1 {
		connect_all_rooms(game, rooms)
	}

	// treasure rooms
	if game.current_floor >= 2 && len(rooms) >= 3 {
		chosen_idx := rand.int_max(len(rooms) - 2) + 1
		game.treasure_room = rooms[chosen_idx]
		cx, cy := get_room_center(rooms[chosen_idx])
		game.pedestal = Boon_Pedistal {
			x      = cx,
			y      = cy,
			active = true,
		}
	} else {
		game.treasure_room = nil
		game.pedestal = nil
	}

	if len(rooms) > 0 {
		player := get_player(game)
		player_x, player_y := get_room_center(rooms[0])
		player.x = player_x
		player.y = player_y
	} else {
		place_player(game)
	}

	// map placement
	place_stairs(game)
	enemy_count := 6 + game.current_floor * 2 // 8 on floor 1, 26 on floor 10
	spawn_enemies(game, enemy_count)
	place_traps(game)
	spawn_gold_piles(game)

	dump_map_ascii(game, "./logs/map.txt")
	log_messagef(game, "The dungeon shift around you...")
}

place_traps :: proc(game: ^Game) {
	// 3 + game.current_floor / 3. 3 6 9 etc. - basic start TODO adjust later
	// manhatan heuristic, distance from other traps, no trap clusters currently or ever
	// at least a few tiles from player spawn, no one turn trap(ideally none in the starting proximity if i can get that in here)
	player := get_player(game)

	// Collect all corridor tiles
	corridors := make([dynamic][2]int, 0, 64)
	defer delete(corridors)

	for y in 1 ..< game.map_height - 1 {
		for x in 1 ..< game.map_width - 1 {
			if is_corridor_tile(game, x, y) {
				append(&corridors, [2]int{x, y})
			}
		}
	}

	rand.shuffle(corridors[:])

	num_traps := 3 + game.current_floor / 3
	placed := 0

	for candidate in corridors {
		if placed >= num_traps {break}
		cx, cy := candidate[0], candidate[1]

		//Distance from player start
		player_dist := abs(cx - player.x) + abs(cy - player.y)
		if player_dist < 3 {continue}

		//Distance from existing traps
		too_close := false
		for trap in game.traps {
			d := abs(cx - trap.x) + abs(cy - trap.y)
			if d < 5 {
				too_close = true
				break
			}
		}
        if too_close { continue }

        // Counting enum values with uniform distribution the odin way
        trap_type := Trap_Type(rand.int_max(len(Trap_Type)))
        append(&game.traps, Trap{x = cx, y = cy, type = trap_type})
        placed += 1
	}
}

dump_map_ascii :: proc(game: ^Game, filename: string) {
	player := get_player(game)

	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	fmt.sbprintf(&sb, "Floor %d  %dx%d\n", game.current_floor, game.map_width, game.map_height)

	for y in 0 ..< game.map_height {
		for x in 0 ..< game.map_width {
			ch: byte

			if x == player.x && y == player.y {
				ch = '@'
			} else if p, ok := game.pedestal.?; ok && p.x == x && p.y == y {
				if p.active {ch = '+'} else {ch = 'x'}
			} else {
				enemy := get_enemy_at(game, x, y)
				if enemy != nil {
					if e, e_ok := enemy.data.(Enemy_Data); e_ok {
						ch = string(e.char)[0] // cstring index gives the raw byte
					}
				} else {
					switch game.tiles[y][x] {
					case .Floor:
						ch = '.'
					case .Wall:
						ch = '#'
					case .Stairs_Down:
						ch = '>'
					case .Water:
						ch = '~'
					case .Tile_Max:
						ch = '?'
					}
				}
			}

			strings.write_byte(&sb, ch)
		};strings.write_byte(&sb, '\n')
	}

	content := strings.to_string(sb)
	_ = os.write_entire_file(filename, transmute([]byte)content)
}

is_corridor_tile :: proc(game: ^Game, x, y: int) -> bool {
	if get_tile(game, x, y) != .Floor {return false}

	n := get_tile(game, x, y - 1) == .Floor
	s := get_tile(game, x, y + 1) == .Floor
	e := get_tile(game, x + 1, y) == .Floor
	w := get_tile(game, x - 1, y) == .Floor

	// Exactly 2 neightbors AND they must be opposite pairs
	ns := n && s && !e && !w
	ew := e && w && !n && !s
	return ns || ew
}
