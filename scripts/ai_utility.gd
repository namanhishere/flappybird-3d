class_name AiUtility
extends RefCounted

## Scores one candidate flight, and says why.
##
## Deliberately separate from the brain, so the F1 overlay can display the
## number the brain actually chose by rather than a description written after
## the fact. If the two ever disagree, the overlay is showing the real thing
## and the test can prove it.
##
## Every weight here was chosen by measurement rather than taste: the
## benchmark in tests/bench.gd flies the real game headlessly over ten seeds,
## and each of the numbers below has a note recording what happens when it is
## moved. The two that surprised me are W_CENTRE and W_BAND, and both of them
## are about a single asymmetry -- gravity only ever pushes the bird down, so
## any objective that rewards "closer to the target" without also punishing
## "above the band" will flap the bird into the ceiling sixty times a second.
##
## Units are metres, seconds, and the odd product of the two.

## Gentle pull towards the centre of the gap, in score per metre.
##
## An order of magnitude below W_BAND, and that ratio is the whole point.
## Inside the clear band this is the only term, so it gives the bird a mild
## reason to sit in the middle rather than on the lip. Set it near W_BAND and
## the co-pilot stops flying: at 0.30 and at 1.00 the ten-seed mean sat nine
## and eleven pipes below the value this has.
const W_CENTRE := 0.6

## Steep cost for each metre of straying outside the clear band, on top of the
## constant the gentle term has already charged for reaching the edge.
##
## The centring term alone makes "flap now" win whenever the bird is below the
## gap, because a flap is the only thing that adds height and height is the
## only thing that reduces the penalty. Once leaving the band is far dearer than
## sitting in the middle of it, the bird stops climbing out of a mistake it has
## already made and glides back in instead.
const W_BAND := 12.0

## Each wasted flap. Load-bearing rather than cosmetic: a schedule that flaps
## to no purpose should lose to one that holds still, and every intermediate
## value tested (0.15, 0.06, 0.00) let the bird flap for its own sake and cost
## several pipes a run.
const W_FLAP := 0.30

## How hard arriving in a dangerous fall is punished. Only bites past
## GameConfig.SAFE_FALL_SPEED: a bird that is merely gliding is not in trouble,
## and rewarding it for not gliding is what makes it flap forever.
const W_DESCENT_FALL := 1.5

## How much the hunter's wake is allowed to matter, per m/s^2 of wind, scaled by
## the time left before the gap.
const W_WIND := 0.35

## Sideways churn, so the co-pilot aims rather than oscillates.
##
## Tuned by measurement, not taste. At a quarter of this the bird approaches a
## gap it can already see without committing, arrives late, and clips the pipe;
## at four times it the line is so damped that the co-pilot lags the whole
## corridor. It was briefly dropped to a third because a narrower test wanted
## faster convergence, which cost four pipes per run at NORMAL -- worth
## recording, because it is the clearest case in the project of a number that
## looks like taste and is not.
const W_CHURN := 0.25

## The lateral clear half-width: outside this the bird is beside the pipe slab
## entirely rather than inside it, at any height.
static func lateral_half() -> float:
	return GameConfig.PIPE_RADIUS + GameConfig.PLAYER_RADIUS

## Scores a vertical flight schedule.
##
## `path` is a candidate trajectory. The terms are: how far the path strayed
## from the gap's centre, how far it strayed *outside* the clear band, how hard
## the hunter is shoving, how many flaps it burned, and whether it is falling
## dangerously fast at the end.
static func score(
		path: Array[Vector2], target: Vector2, gap_size: float,
		time_to_gap: float, wind: Vector2, flap_count: int,
		delta: float) -> float:
	if path.is_empty():
		return -INF
	var half := maxf(gap_size * 0.5 - GameConfig.PLAYER_RADIUS, 0.0)
	var descent := maxf(-_arrival_speed(path) - GameConfig.SAFE_FALL_SPEED, 0.0)
	return -_vertical_cost(path, target.y, half) \
		- W_WIND * wind.length() * maxf(time_to_gap, 0.0) \
		- W_FLAP * float(flap_count) \
		- W_DESCENT_FALL * descent

## Scores a steer candidate, on the lateral axis only.
##
## Same shape as the vertical score: a gentle pull onto the line, a steep cost
## for straying outside the pipe's slab, and a churn term paying for the
## sideways speed the bird is still carrying when it arrives.
static func steer_score(
		path: Array[Vector2], target_x: float, dt: float) -> float:
	if path.is_empty():
		return -INF
	return -_horizontal_cost(path, target_x, lateral_half()) \
		- W_CHURN * _lateral_churn(path, dt)

## Per-sample cost, averaged over the path.
##
## Inside the band the cost is a gentle linear pull towards the centre, so
## precision is rewarded. Outside it the cost is superlinear, so straying is
## punished hard, and it is punished the same way above and below.
##
## Both properties come from the shape, and an earlier version got neither: it
## charged the *worst* excursion on the path separately from the mean, and every
## candidate starts from the same place, so the worst sample was the shared
## starting error. That added a large constant, cancelled the differences
## between candidates, and left the plain mean picking the smallest possible
## movement -- so the bird sat still until the error was so large that even a
## bad command helped, then locked over and sailed past. Averaging a per-sample
## cost that is itself steep outside the band keeps the discrimination and the
## punishment at the same time.
static func _vertical_cost(path: Array[Vector2], target_y: float, half: float) -> float:
	var total := 0.0
	for point in path:
		total += _sample_cost(absf(point.y - target_y), half)
	return total / float(path.size())

## The same, sideways: outside `half` the bird is beside the pipe rather than
## level with it, at any height.
static func _horizontal_cost(path: Array[Vector2], target_x: float, half: float) -> float:
	var total := 0.0
	for point in path:
		total += _sample_cost(absf(point.x - target_x), half)
	return total / float(path.size())

## The cost of one sample being `error` metres from the target, where `half` is
## the clear half-width.
static func _sample_cost(error: float, half: float) -> float:
	if half <= 0.0:
		return W_BAND * error * error
	if error <= half:
		return W_CENTRE * error
	var excess := error - half
	return W_CENTRE * half + W_BAND * excess * excess / half

## Mean absolute sideways speed, in m/s. High for a line that reverses
## direction repeatedly, low for one that commits and arrives.
static func _lateral_churn(path: Array[Vector2], dt: float) -> float:
	if path.size() < 2 or dt <= 0.0:
		return 0.0
	var total := 0.0
	for i in range(1, path.size()):
		total += absf(path[i].x - path[i - 1].x) / dt
	return total / float(path.size() - 1)

## Downward speed at the end of the path, recovered from the last two samples.
static func _arrival_speed(path: Array[Vector2]) -> float:
	if path.size() < 2:
		return 0.0
	return path[path.size() - 1].y - path[path.size() - 2].y
