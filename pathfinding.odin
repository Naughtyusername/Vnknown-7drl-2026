package sdrl

  Pathfind_Node :: struct {
      x, y:           int,
      cost_so_far:    int,
      estimated_total: int, // cost_so_far + heuristic
      parent_idx:     int,
  }

  // Returns (next_x, next_y, found).
  // Computes A* from start to goal, returns just the first step.
  // max_dist caps search depth so distant enemies don't burn cycles.
  astar_step :: proc(
      game: ^Game,
      start_x, start_y, goal_x, goal_y: int,
      max_dist: int = 30,
  ) -> (int, int, bool) {
      if start_x == goal_x && start_y == goal_y {
          return start_x, start_y, true
      }

      // Open list — linear scan for min estimated_total (fine for bounded search)
      open := make([dynamic]Pathfind_Node, 0, 128)
      defer delete(open)

      // Closed set — already-evaluated tiles
      visited := make([dynamic][dynamic]bool, game.map_height)
      defer {
          for row in visited { delete(row) }
          delete(visited)
      }
      for y in 0..<game.map_height {
          visited[y] = make([dynamic]bool, game.map_width)
      }

      // Parent tracking for path reconstruction
      Parent :: struct { x, y: int }
      came_from := make([dynamic][dynamic]Parent, game.map_height)
      defer {
          for row in came_from { delete(row) }
          delete(came_from)
      }
      for y in 0..<game.map_height {
          came_from[y] = make([dynamic]Parent, game.map_width)
          for x in 0..<game.map_width {
              came_from[y][x] = Parent{-1, -1}
          }
      }

      // Chebyshev distance — correct heuristic for 8-directional movement.
      // Max of dx/dy because diagonal moves cost the same as cardinal.
      chebyshev :: proc(x, y, goal_x, goal_y: int) -> int {
          dx := abs(x - goal_x)
          dy := abs(y - goal_y)
          return max(dx, dy)
      }

      append(&open, Pathfind_Node{
          x = start_x, y = start_y,
          cost_so_far = 0,
          estimated_total = chebyshev(start_x, start_y, goal_x, goal_y),
          parent_idx = -1,
      })

      dirs := [8][2]int{
          {0, -1}, {0, 1}, {-1, 0}, {1, 0},       // cardinal
          {-1, -1}, {1, -1}, {-1, 1}, {1, 1},       // diagonal
      }

      for len(open) > 0 {
          // Find node with lowest estimated_total
          best_idx := 0
          for i in 1..<len(open) {
              if open[i].estimated_total < open[best_idx].estimated_total {
                  best_idx = i
              }
          }

          current := open[best_idx]
          // Swap-remove from open list
          open[best_idx] = open[len(open) - 1]
          pop(&open)

          if visited[current.y][current.x] { continue }
          visited[current.y][current.x] = true

          // Reached goal — walk came_from back to find the first step
          if current.x == goal_x && current.y == goal_y {
              step_x, step_y := goal_x, goal_y
              for {
                  parent := came_from[step_y][step_x]
                  if parent.x == start_x && parent.y == start_y {
                      return step_x, step_y, true
                  }
                  step_x, step_y = parent.x, parent.y
              }
          }

          // Don't expand past max search distance
          if current.cost_so_far >= max_dist { continue }

          for dir in dirs {
              nx := current.x + dir[0]
              ny := current.y + dir[1]

              if !in_bounds(game, nx, ny) { continue }
              if visited[ny][nx] { continue }
              if game.tiles[ny][nx] == .Wall { continue }

              // Don't path through other enemies, but allow pathing TO
              // the goal tile (which is the player)
              if (nx != goal_x || ny != goal_y) && enemy_at(game, nx, ny) {
                  continue
              }

              new_cost := current.cost_so_far + 1

              prev := came_from[ny][nx]
              if prev.x == -1 {
                  came_from[ny][nx] = Parent{current.x, current.y}
                  append(&open, Pathfind_Node{
                      x = nx, y = ny,
                      cost_so_far = new_cost,
                      estimated_total = new_cost + chebyshev(nx, ny, goal_x,
  goal_y),
                      parent_idx = -1,
                  })
              }
          }
      }

      // No path found
      return start_x, start_y, false
  }
