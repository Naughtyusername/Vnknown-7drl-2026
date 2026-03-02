package sdrl

import "core:math"

// ===============================================================================================================================================================
// Shadowcasting — https://www.albertford.com/shadowcasting/
// ===============================================================================================================================================================

// TODO: debug mode that enables one octant at a time to verify each 45-degree wedge
OCTANT_MULTIPLIERS :: [8][4]int {
	// 0 - 3
	{1, 0, 0, 1},
	{0, 1, 1, 0},
	{0, -1, 1, 0},
	{-1, 0, 0, 1},
	// 4 - 7
	{-1, 0, 0, -1},
	{0, -1, -1, 0},
	{0, 1, -1, 0},
	{1, 0, 0, -1},
}

transform_octant :: proc(ox, oy, row, col, octant: int) -> (int, int) {
	table := OCTANT_MULTIPLIERS
	m := table[octant]
	return ox + col * m[0] + row * m[1], oy + col * m[2] + row * m[3]
}

cast_light :: proc(
	game: ^Game,
	ox, oy: int,
	radius: int,
	octant: int,
	start_row: int, // starts at 1
	start_slope: f32, // HIGH boundary 1.0, diagonal side
	end_slope: f32, // LOW boundary 0.0, the axis side
	visited: ^map[[2]int]bool,
) {
	if start_slope < end_slope {return}

	// Mutable LOW boundary — narrows upward as walls are encountered
	new_end: f32 = end_slope

	for current_row := start_row; current_row <= radius; current_row += 1 {

		prev_blocked := false

		for col in 0 ..= current_row {
			l_slope := (f32(col) - 0.5) / f32(current_row)
			r_slope := (f32(col) + 0.5) / f32(current_row)

			// Tile's far edge doesn't reach visible region
			if r_slope < new_end {continue}
			// Tile's near edge is past visible region — everything after is too
			if l_slope > start_slope {break}

			wx, wy := transform_octant(ox, oy, current_row, col, octant)
			in_range :=
				in_bounds(game, wx, wy) &&
				(col * col + current_row * current_row <= radius * radius)

			// Out of bounds treated as wall to keep shadow logic correct at map edges
			blocked := true
			if in_range {
				blocked = is_blocking(game.tiles[wy][wx])
			}

			is_symmetric :=
				f32(col) >= f32(current_row) * new_end &&
				f32(col) <= f32(current_row) * start_slope

			if in_range {
				if blocked || is_symmetric {
					game.visible[wy][wx] = true
					game.revealed[wy][wx] = true

					tile_coord := [2]int{wx, wy}
					if tile_coord not_in visited^ {
						dist := math.sqrt(f32(col * col + current_row * current_row))
						intensity := (1.0 - dist / f32(radius))

						dimmed_light := dim_color(sample_color(LANTERN_LIGHT_COLOR), intensity)
						game.light_map[wy][wx] = dimmed_light // Direct assignment, no add_light!

						visited^[tile_coord] = true

						when ODIN_DEBUG {
							game.light_hit_count[wy][wx] += 1 // Should always be 1 now
						}
					}
				}
			}

			// Wall/floor transition state machine
			if blocked {
				if !prev_blocked {
					// floor -> wall: recurse for the sub-arc below the wall
					cast_light(
						game,
						ox,
						oy,
						radius,
						octant,
						current_row + 1,
						l_slope,
						new_end,
						visited,
					)
				}
				prev_blocked = true
			} else {
				if prev_blocked {
					// wall -> floor: LOW boundary jumps past the shadow
					new_end = l_slope
				}
				prev_blocked = false
			}
		}
		if prev_blocked {
			return
			// Last tile in row was a wall — everything beyond is blocked.
			// Without this return we get wall hacks!
		}
	}
}

// ===============================================================================================================================================================
// Bresenham line-of-sight — separate from shadowcasting, cheap for enemy FOV etc.
// ===============================================================================================================================================================
compute_fov :: proc(game: ^Game, origin_x, origin_y, radius: int) {
	for y in 0 ..< game.map_height {
		for x in 0 ..< game.map_width {
			game.visible[y][x] = false
			game.light_map[y][x] = LIGHT_NONE
		}
	}

	if in_bounds(game, origin_x, origin_y) {
		game.visible[origin_y][origin_x] = true
		game.revealed[origin_y][origin_x] = true
		game.light_map[origin_y][origin_x] = sample_color(LANTERN_LIGHT_COLOR)
	}

	// Prevents octant overlap — each tile lit only once
	visited := make(map[[2]int]bool)
	defer delete(visited)

	for octant in 0 ..< 8 {
		cast_light(game, origin_x, origin_y, radius, octant, 1, 1.0, 0.0, &visited)
	}
}

// ===============================================================================================================================================================
// Bresenham line algorithm
// ===============================================================================================================================================================
has_line_of_sight :: proc(game: ^Game, x0, y0, x1, y1: int) -> bool {
	dx := abs(x1 - x0)
	dy := abs(y1 - y0)

	sx := x0 < x1 ? 1 : -1
	sy := y0 < y1 ? 1 : -1

	err := dx - dy

	x := x0
	y := y0

	for {
		// Don't check origin or target tile for blocking
		if (x != x0 || y != y0) && (x != x1 || y != y1) {
			if !in_bounds(game, x, y) {
				return false
			}
			if is_blocking(game.tiles[y][x]) {
				return false
			}
		}

		if x == x1 && y == y1 {
			break
		}

		e2 := 2 * err

		if e2 > -dy {
			err -= dy
			x += sx
		}

		if e2 < dx {
			err += dx
			y += sy
		}
	}

	return true
}

is_blocking :: proc(tile: Tile) -> bool {
	return tile == .Wall
}
