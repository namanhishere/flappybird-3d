SHELL := /usr/bin/env bash
MAKEFLAGS += --no-print-directory

# tools/toolchain.env is deliberately NOT included here. It is written in shell
# syntax (${VAR:-default}), and GNU make would expand those as make references,
# silently producing wrong paths -- which `distclean` would then delete. Every
# path is resolved by tools/godot.sh, which sources the file with bash, and by
# the one recipe below that needs CACHE_ROOT, which shells out for the same
# reason.

GODOT := ./tools/godot.sh
BINARY := build/flappy3d
# Frames for the smoke runs: 180 frames is 3 seconds at the 60 Hz physics tick.
SMOKE_FRAMES ?= 180
# Every non-interactive engine invocation is bounded. A scene whose script
# fails to parse never reaches its own quit() call, so without this a typo in
# a .gd file presents as a silent ten-minute hang instead of an error that
# names the line. `make play` stays unbounded on purpose: a human drives it.
GODOT_TIMEOUT ?= 300
# Port for the two online modes. Override with PORT= on the command line.
PORT ?= 27015
# AI level for the demo targets: easy, normal, hard or unfair.
SKILL ?= unfair

.PHONY: all setup import test net-test net-smoke run play build build-verify \
	check lint clean distclean serve client demo-2p demo-ai net-windowed bench

all: test

## Fetch and verify the pinned Godot binary and export templates.
setup:
	@./tools/setup.sh

## Generate .import files. Needed after a fresh clone, before anything runs.
import:
	@GODOT_TIMEOUT=$(GODOT_TIMEOUT) GODOT_LOG_LABEL=import $(GODOT) --headless --import

## The authoritative automated validation: headless gameplay tests.
test: import
	@GODOT_TIMEOUT=$(GODOT_TIMEOUT) GODOT_LOG_LABEL=test $(GODOT) --headless res://tests/test_runner.tscn

## The authoritative online check: a host and a client in one process, driven
## through the real replication path with no socket open. Fast, deterministic,
## and it fails with a number rather than a timeout.
net-test: import
	@GODOT_TIMEOUT=$(GODOT_TIMEOUT) GODOT_LOG_LABEL=net_test $(GODOT) --headless res://tests/net_test.tscn

## The same rules over a real loopback socket, in two processes. This is the
## one that proves ENet and the RPC annotations work, which net-test cannot.
net-smoke: import
	@./tools/net_smoke.sh

## Host an online match. Run `make client` in a second terminal.
serve: import
	@GODOT_LOG_LABEL=host $(GODOT) -- --mode=host --port=$(PORT) $(ARGS)

## Join a host on this machine. Run `make serve` first.
client: import
	@GODOT_LOG_LABEL=client $(GODOT) -- --mode=client --address=127.0.0.1 --port=$(PORT) $(ARGS)

## Can the AI actually play? The gameplay benchmark: flies the real game
## headlessly and reports how many pipes the co-pilot got past.
##
## Twenty seeds by default, because the co-pilot is a bang-bang controller and
## its per-seed results are chaotic -- a single seed measures luck rather than
## skill. Pass a floor to make it a gate rather than a measurement:
##
##     make bench ARGS="--pilot=ai --skill=normal --runs=20 --min-pipes=20"
##     make bench ARGS="--pilot=script --runs=20 --min-pipes=10"
bench: import
	@GODOT_TIMEOUT=$(GODOT_TIMEOUT) GODOT_LOG_LABEL=bench $(GODOT) --headless \
		res://tests/bench.tscn -- $(ARGS)

## The full two-window acceptance check: a real host and a real client, on
## this display, for a minute, with the client's frames captured. Exits 2 with a
## message when there is no display, rather than pretending to have passed.
net-windowed: import
	@./tools/net_windowed.sh

## Local two-player co-op on one keyboard: P1 flaps, P2 steers.
demo-2p: import
	@GODOT_LOG_LABEL=demo2p $(GODOT) -- --mode=local2p $(ARGS)

## One player plus the AI co-pilot, with the explainability panel already up.
demo-ai: import
	@GODOT_LOG_LABEL=demoai $(GODOT) -- --mode=ai --human=steer --overlay \
		--skill=$(SKILL) $(ARGS)

## Boot the real game in a real window, flying itself, and fail on any error.
## This is the "does it actually run" check, not a test.
run: import
	@GODOT_TIMEOUT=$(GODOT_TIMEOUT) GODOT_LOG_LABEL=run $(GODOT) -- --autoplay --frames=$(SMOKE_FRAMES)

## Play the game interactively.
play: import
	@GODOT_LOG_LABEL=play $(GODOT)

## Export the standalone Linux binary.
build: import
	@mkdir -p build
	@GODOT_TIMEOUT=$(GODOT_TIMEOUT) GODOT_LOG_LABEL=build $(GODOT) --headless --export-release Linux $(BINARY)
	@test -x $(BINARY) || { echo "[make] ERROR: $(BINARY) was not produced" >&2; exit 1; }
	@echo "[make] built $(BINARY)"

## Boot the exported binary and fail on any error.
build-verify:
	@test -x $(BINARY) || { echo "[make] ERROR: $(BINARY) is missing; run 'make build'" >&2; exit 1; }
	@mkdir -p build/logs
	@./$(BINARY) -- --autoplay --frames=$(SMOKE_FRAMES) 2>&1 | tee build/logs/exported_run.log
	@! grep -nE 'SCRIPT ERROR|^ERROR:|USER SCRIPT ERROR|USER ERROR' build/logs/exported_run.log \
		|| { echo "[make] ERROR: exported binary reported errors" >&2; exit 1; }
	@echo "[make] exported binary ran clean"

## Full validation pass: tests, real run, export, and the exported binary.
check: test net-test run build build-verify
	@echo "[make] all validation stages passed"

## Re-run Godot's import/parse pass as a static check over every script.
lint: import
	@GODOT_TIMEOUT=$(GODOT_TIMEOUT) GODOT_LOG_LABEL=lint $(GODOT) --headless --editor --quit

## Remove build outputs but keep the downloaded toolchain cache.
clean:
	@rm -rf build .godot
	@echo "[make] cleaned"

## Also drop the cached toolchain. `make setup` will re-download it.
distclean: clean
	@source tools/toolchain.env && rm -rf "$$CACHE_ROOT" && echo "[make] removed toolchain cache at $$CACHE_ROOT"
