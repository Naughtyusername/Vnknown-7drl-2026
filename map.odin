package sdrl

import "core:math/rand"

place_stairs :: proc(game: ^Game) {
    player := get_player(game)

    // 2D distance array, -1 = unvisited
    dist := make([dynamic][dynamic]int, game.map_height)
    defer {
        for row in dist { delete(row) }
        delete(dist)
    }
    for y in 0..<game.map_height {
        dist[y] = make([dynamic]int, game.map_width)
        for x in 0..<game.map_width {
            dist[y][x] = -1
        }
    }

    // FIFO queue
    Queue_Entry :: struct { x, y: int }
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

            if !in_bounds(game, nx, ny) { continue }
            if dist[ny][nx] != -1 {continue } // already visited
            if game.tiles[ny][nx] == .Wall { continue }

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

    for y in 0..<game.map_height {
        for x in 0..<game.map_width {
            d := dist[y][x]
            if d <= 0 { continue }
            if game.tiles[y][x] != .Floor { continue }

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
    for _ in 0..<max_attempts {
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

    if len(rooms) > 0 {
        player := get_player(game)
        player_x, player_y := get_room_center(rooms[0])
        player.x = player_x
        player.y = player_y
    } else {
        place_player(game)
    }

    place_stairs(game)
    spawn_enemies(game, 10)

    log_messagef(game, "The dungeon shift around you...")
}
