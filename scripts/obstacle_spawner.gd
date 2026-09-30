extends Node3D
class_name ObstacleSpawner

## Keeps a corridor of pipe pairs in front of the bird.
##
## Spawns ahead of the player, culls whatever is left behind, and reports each
## pipe the moment it is passed so the game can score it. The layout comes
## from ObstaclePlan, which is seeded, so a given seed always produces the same
## course.

## Emitted exactly once per pipe, as the bird's centre crosses its mid-plane.
signal pipe_passed(index: int)

var plan := ObstaclePlan.new()
var obstacles: Array[Obstacle] = []

var _next_spawn_z: float = 0.0
var _player_z: float = 0.0

## Wipes the corridor and lays a fresh course. The same seed rebuilds the same
## layout, which is what lets the tests assert exact positions.
func reset(player_z: float, seed_value: int) -> void:
	_clear()
	_player_z = player_z
	plan.reset(seed_value)
	# The first pipe sits a full lookahead ahead, so the opening seconds are
	# gentle, and the rest of the corridor is laid out beyond it.
	_next_spawn_z = player_z - GameConfig.SPAWN_DISTANCE
	_spawn_ahead(player_z, 0)

## Advances spawning, scoring and culling for one fixed step.
func advance(player_z: float, score: int) -> void:
	_player_z = player_z
	_spawn_ahead(player_z, score)
	for obstacle in obstacles:
		# The scored flag is the guard that makes a pipe worth exactly one
		# point: it is set here and checked here, so the signal fires once
		# however many frames the bird spends behind the pipe.
		if not obstacle.scored and obstacle.is_passed_by(player_z):
			obstacle.scored = true
			pipe_passed.emit(obstacle.index)
		# Drawing follows the camera, not the bird. The camera sits
		# CAMERA_Z_OFFSET behind the bird's centre, so a pipe the bird has
		# already cleared can still be around the camera for a third of a
		# metre -- which filled the view with the inside of a green box. The
		# bird's own position still decides scoring and collision.
		obstacle.set_drawn(not obstacle.is_passed_by(
			player_z + GameConfig.CAMERA_Z_OFFSET))
	_cull(player_z)

## The pipe the bird is about to reach: the nearest one still ahead of it.
## Anything already behind the bird is ignored, so this always describes the
## obstacle currently being flown at, not the far end of the corridor.
func next_obstacle() -> Obstacle:
	var best: Obstacle = null
	for obstacle in obstacles:
		if obstacle.position.z > _player_z:
			continue
		if best == null or obstacle.position.z > best.position.z:
			best = obstacle
	return best

## Number of pipes currently alive, used by the HUD and by tests.
func obstacle_count() -> int:
	return obstacles.size()

## Lays pipes until the corridor reaches its full depth ahead of the bird.
## The horizon is measured from the bird rather than from the last pipe, so
## the corridor stays a fixed length as the bird advances instead of running
## away from it.
func _spawn_ahead(player_z: float, score: int) -> void:
	var horizon := player_z - GameConfig.SPAWN_DISTANCE \
		- GameConfig.CORRIDOR_PIPES * GameConfig.PIPE_SPACING
	while _next_spawn_z >= horizon:
		var obstacle := Obstacle.new()
		obstacle.configure(plan.next_obstacle(score))
		# The pipe pair carries the plan's sideways offset, so the corridor
		# actually requires steering rather than centring.
		obstacle.position = Vector3(obstacle.gap_center_x, 0.0, _next_spawn_z)
		add_child(obstacle)
		obstacles.append(obstacle)
		_next_spawn_z -= GameConfig.PIPE_SPACING

## Frees pipes that are far enough behind. The node is deliberately left
## parented: queue_free() still disposes it on the next frame, but keeping it
## in the tree means a wholesale teardown of the spawner also reclaims any
## pipe that has not been processed yet.
func _cull(player_z: float) -> void:
	var survivors: Array[Obstacle] = []
	for obstacle in obstacles:
		if obstacle.position.z - player_z > GameConfig.CULL_DISTANCE:
			obstacle.queue_free()
		else:
			survivors.append(obstacle)
	obstacles = survivors

func _clear() -> void:
	for obstacle in obstacles:
		obstacle.queue_free()
	obstacles.clear()
