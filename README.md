# Flappy 3D

A 3D first-person Flappy Bird game built with **Godot 4.7.2** and **GDScript** —
for one player or for two.

You are the bird. The camera *is* the bird: you fly continuously forward down a
corridor of procedurally generated pipe pairs. Flap too rarely and you hit the
ground; too eagerly and you hit a pipe. Every pipe you pass is a point, the gaps
get tighter, and you get faster the longer you survive.

**The bird has two controls and it is never duplicated.** Player 1 owns the
**flap** axis — up and down. Player 2 owns the **steer** axis — left and right.
Neither can touch the other's, which is what makes "two people, one bird" a
constraint rather than a shared hotkey. It also means the corridor has to move
sideways to be worth flying, so every pipe pair sits at its own lateral offset.

![gameplay](docs/screenshot.png)

## The modes

| Mode | Flap axis | Steer axis | How to run it |
| --- | --- | --- | --- |
| `SOLO` | you | — | `make play`, or pick it on the title card |
| `LOCAL 2P` | P1 | P2, same keyboard | `make demo-2p` |
| `AI_HUMAN_STEER` | the AI | you | `make demo-ai` |
| `AI_HUMAN_FLAP` | you | the AI | `make demo-ai` with `ARGS="--human=flap"` |
| `HOST` | you, on the host | the client | `make serve` |
| `CLIENT` | the host | you | `make client`, after `make serve` |

Two other things are in the world besides the pipes: an **AI co-pilot** that
takes whichever axis you are not holding, and a **hunter drone** that shoves the
bird around with its wake and takes a life on contact. Press `F1` to see what
the AI is thinking and the numbers it thought it with, and `TAB` to switch
between the co-pilot and the hunter.

## Requirements

Nothing to install by hand. `make setup` downloads a pinned Godot 4.7.2 binary
and its matching Linux export templates into a cache directory, verifying both
against the SHA512 checksums published in the official Godot release. No system
packages are touched.

You need `bash`, `curl`, `unzip`, `sha512sum` and `make` — all present on any
ordinary Linux box. To play the game you also need a GPU with Vulkan support.

## Quick start

```sh
make setup     # download and verify the pinned Godot toolchain (one time)
make test      # run the automated test suite headlessly
make play      # play the game
```

## Building the standalone game

```sh
make build          # produces build/flappy3d, a single self-contained Linux binary
./build/flappy3d    # play it
```

The exported binary embeds the resource pack, so it is a single file with no
dependency on this source tree. The only thing it still needs is a Vulkan GPU.

## Controls

| Input | Action |
| --- | --- |
| `SPACE`, `W`, `UP`, `ENTER`, or left click | Flap. Also starts the run, and restarts after a crash. |
| `A`, `LEFT` / `D`, `RIGHT` | Steer. Whoever owns the steer axis. |
| `UP` / `DOWN` | Move around the title menu. |
| `R` | Restart mid-run. |
| `F1` | Show the AI's decision and its utility table. |
| `TAB` | Switch the panel between the co-pilot and the hunter. |
| `ESC` | Quit. |

## Running the tests

```sh
make test
```

This runs the project's own headless test runner — a small, dependency-free
assertion framework in `tests/` — against the real game scene. It prints one
`PASS`/`FAIL` line per test and exits non-zero if anything fails. There are **53
tests** covering the project configuration, the scene graph, the first-person
rig, audio wiring, the two-axis flight model, reachability-constrained pipe
generation on both axes, pipe collision, the intent/authority pipeline, the
mode table, the title menu, both AI brains, the hunter, the overlay, scoring,
difficulty progression, restart, the input path, and the HUD.

The runner drives the game through `Game.advance(delta)` with a fixed delta
rather than waiting on real frames, so the results are deterministic and do not
depend on machine speed or frame timing.

Other useful targets:

| Command | What it does |
| --- | --- |
| `make check` | The full validation pass: tests, the online tests, a real windowed run, the export, and a run of the exported binary. |
| `make net-test` | A host and a client in one process, driven through the real replication path with no socket open. |
| `make net-smoke` | Two processes over a real loopback socket; checks the handshake, the snapshot rate, and that no pipe is ever sent. |
| `make net-windowed` | Two real windows for a minute, with the client's frames captured. |
| `make bench` | Flies the real game headlessly and reports how many pipes the AI got past. |
| `make run` | Boots the real game in a window for 3 seconds, flying itself, and fails on any engine error. |
| `make lint` | Re-parses every script through Godot's importer as a static check. |
| `make clean` | Removes `build/` and `.godot/`, keeping the downloaded toolchain. |
| `make distclean` | Also removes the cached toolchain. `make setup` re-downloads it. |

`make bench` takes extra arguments, and a floor turns a measurement into a
gate:

```sh
make bench ARGS="--pilot=ai --skill=normal --runs=20 --min-pipes=20"
make bench ARGS="--pilot=script --runs=20 --min-pipes=10"
```

## Layout

```
Makefile              build, test and run entry points
project.godot         Godot project configuration
export_presets.cfg    the Linux export preset
scenes/main.tscn      world, ground, spawner, player, drone, audio, UI, menu, overlay
scripts/
  game.gd             state machine, score, and the order of the simulation
  player.gd           the first-person bird: camera, wings, movement
  obstacle.gd         one pipe pair: geometry and collision
  obstacle_spawner.gd keeps a corridor of pipes alive
  ground.gd           the scrolling ground and its speed stripes
  hunter_drone.gd     the drone: mesh, model, brain, and the wake it writes
  ui.gd               title card, score, lives, roles, game-over card
  mode_menu.gd        mode and skill, built in code
  ai_overlay.gd       the explainability panel: state, aim, utility table
  target_marker.gd    the crosshair and the predicted-path ribbon
  sfx.gd              sound effects
  materials.gd        the colour palette
  input_actions.gd    input map, registered at runtime
  game_config.gd      every tunable number, in one place
  difficulty.gd       the difficulty curve, as pure functions
  flight_model.gd     the bird's two-axis physics, as a pure value object
  obstacle_plan.gd    deterministic, reachability-constrained pipe generation
  bird_intent.gd      the one control message every source produces
  authority.gd        host-side validation of a peer's input
  bird_state.gd       the replicated value
  match_config.gd     mode, seed, port, skill
  control_map.gd      which source drives which axis, per mode
  skill_profile.gd    four levels of the same brain
  bird_sensors.gd     what a brain is allowed to perceive
  flight_predictor.gd runs a copy of the model forward
  ai_utility.gd       scores a candidate flight
  co_pilot_brain.gd   picks a flap rhythm, or a steer
  hunter_model.gd     the drone's kinematics
  hunter_sensors.gd   what the hunter is allowed to perceive
  hunter_brain.gd     lead-pursuit intercept
  hunter_thrust.gd    one hunter decision
  net/protocol.gd     every wire constant, in one file
  net/multiplayer_link.gd  the ENet peer and the eight RPCs; no game logic
tests/
  test_runner.gd      the 53 tests
  test_framework.gd   the assertion recorder
  net_test.gd         the six online tests
  bench.gd            the gameplay benchmark
tools/
  setup.sh            reproducible toolchain download
  toolchain.env       pinned versions, checksums and cache paths
  godot.sh            runs Godot, fails on any engine error, and bounds the run
  net_smoke.sh        two processes over a real loopback socket
  net_windowed.sh     two real windows, a minute, frames captured
  gen_audio.py        generates the four sound effects
assets/audio/         the generated .wav files
docs/                 architecture, method, assets, limitations, validation
```

## Further reading

- [Architecture](docs/ARCHITECTURE.md) — how the pieces fit together and why.
- [Method](docs/METHOD.md) — how the project was built: protocol, CLI and tool usage, the bugs and what caught them, and the alternatives that were rejected.
- [Assets and licences](docs/ASSETS.md) — everything is procedural; nothing is third-party.
- [Known limitations](docs/KNOWN_LIMITATIONS.md) — what is *not* covered.
- [Validation results](docs/VALIDATION.md) — the final verification pass.
