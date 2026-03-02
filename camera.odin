package sdrl

// TODO we need to clamp this to not move map outside of view (hud going over)

center_camera :: proc(camera: ^Camera, target_x, target_y, map_width, map_height: int) {
    camera.x = target_x - camera.viewport_width / 2
    camera.y = target_y - camera.viewport_height / 2

    camera.x = clamp(camera.x, 0, max(0, map_width - camera.viewport_width))
    camera.y = clamp(camera.y, 0, max(0, map_height - camera.viewport_height))
}

world_to_screen :: proc(camera: Camera, world_x, world_y: int) -> (screen_x, screen_y: int, visible: bool) {
    screen_x = world_x - camera.x
    screen_y = world_y - camera.y
    visible = screen_x >= 0 && screen_x < camera.viewport_width &&
              screen_y >= 0 && screen_y < camera.viewport_height
    return
}

get_viewport_bounds :: proc(camera: Camera) -> (min_x, min_y, max_x, max_y: int) {
    min_x = camera.x
    min_y = camera.y
    max_x = camera.x + camera.viewport_width
    max_y = camera.y + camera.viewport_height
    return
}

in_viewport :: proc(camera: Camera, world_x, world_y: int) -> bool {
    return world_x >= camera.x && world_x < camera.x + camera.viewport_width &&
           world_y >= camera.y && world_y < camera.y + camera.viewport_height
}
