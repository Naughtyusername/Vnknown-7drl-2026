# 7DRL 2026

*Descend into darkness. Seal the sarcophagus. The realm gets another age.*

A roguelike entry for the [7 Day Roguelike Challenge](https://itch.io/jam/7drl) 2026.

## About

You play a lone figure descending into mountain caves to seal an ancient evil buried deep below. Your lantern is your lifeline — fuel is finite, and the darkness is not empty. This is gothic horror through resource scarcity and creeping dread, not jump scares.

## Features

- Traditional roguelike — turn-based, grid-based, permadeath
- Dual vision system — FOV and lighting are independent; you can see into darkness, but not clearly
- Lantern fuel as the central resource — your light radius shrinks as fuel runs out
- Sanity system that warps your perception of the caves around you
- Risk/reward darkness — going unlit is dangerous but opens up tactical options
- Procedural cave generation with a hand-crafted tutorial floor

## Inspirations

Brogue, Infra Arcana, Cogmind, Darkest Dungeon, Golden Krone Hotel, Castlevania

## Tech Stack

- **Language**: [Odin](https://odin-lang.org/)
- **Graphics**: [Raylib](https://www.raylib.com/)
- **Platforms**: Linux, macOS, Windows

## Building

Requires the [Odin compiler](https://odin-lang.org/docs/install/). Raylib ships with Odin's vendor collection, no extra deps needed.

```bash
odin build . -out:bin/game
./bin/game
```

## Notes

Built by porting and adapting systems from a closed-source personal roguelike project — reusing FOV, rendering, scheduling, and messaging patterns but building a fresh codebase for the jam.

## AI Usage

Claude was used for documentation scaffolding, best practices discussion, and code review. All game code is written by hand.

## License

MIT
