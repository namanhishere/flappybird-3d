class_name GameConfig
extends RefCounted

## Every tunable number in the game, in one place.
##
## Keeping these together means the difficulty curve, the spawner and the tests
## all agree on what "hard" means, and rebalancing the game is a single-file
## edit. Distances are in metres, time in seconds.

# --- Flight model -----------------------------------------------------------
## Downward acceleration. Higher means the bird falls faster.
const GRAVITY := 18.0
## Upward velocity granted by one flap. Must exceed GRAVITY * (time between
## flaps) or the bird can never climb.
const FLAP_IMPULSE := 7.0
## Clamp on downward speed so a long fall cannot tunnel through obstacles.
const MAX_FALL_SPEED := -22.0
## Downward speed above which a fall stops being a glide and starts being a
## problem. The co-pilot is rewarded for holding the gap and for not falling
## *dangerously* fast; rewarding it merely for not falling would make it flap
## on every single tick, which is a bird that climbs into the sky.
const SAFE_FALL_SPEED := 12.0
## Height the bird starts (and restarts) at.
const START_Y := 5.0

# --- World bounds -----------------------------------------------------------
## Hitting the ground or the ceiling is a game over, same as hitting a pipe.
const FLOOR_Y := 0.0
const CEILING_Y := 16.0
## Radius of the bird's collision circle.
const PLAYER_RADIUS := 0.45

# --- Forward speed ----------------------------------------------------------
const FORWARD_SPEED_START := 11.0
const FORWARD_SPEED_MAX := 19.0

# --- Lateral flight (the steer axis) -----------------------------------------
## Sideways acceleration from a full steer input.
const LATERAL_ACCEL := 22.0
## Hard clamp on sideways speed. Deliberately below LATERAL_ACCEL /
## LATERAL_DAMPING, so the clamp -- not the drag -- is what stops a long hold.
const LATERAL_MAX_SPEED := 6.0
## Fraction of sideways speed lost per second when nothing pushes sideways.
## Drag alone would cap the bird at LATERAL_ACCEL / LATERAL_DAMPING, so the
## two are tuned together rather than independently.
const LATERAL_DAMPING := 3.0
## Half-width of the playable lane. The bird is hard-clamped to it, so there
## is always somewhere to steer to and no pipe can be unreachable.
const LANE_HALF_WIDTH := 6.0
## Sustainable sideways rate, including the cost of spinning up from a
## standstill. The pipe generator uses this rather than LATERAL_MAX_SPEED,
## because a bird that has to start from rest never reaches its top speed
## instantly -- and the generator's promise is that every course is flyable.
const LATERAL_SPEED := 4.0
## Largest sideways jump of a gap centre between consecutive pipes.
const MAX_GAP_CENTER_X_DELTA := 3.0

# --- Camera -----------------------------------------------------------------
## How far behind the bird's own centre the first-person camera sits, in
## metres. Player places its camera here, and the obstacle spawner uses it to
## decide when a pipe stops being drawn: the camera is what has to be outside a
## pipe, not the bird.
const CAMERA_Z_OFFSET := 0.35

# --- Networking --------------------------------------------------------------
## Seconds over which a client glides its bird back onto the host's altitude.
## Long enough to read as a correction rather than a glitch, short enough that
## the bird is where the host says it is before it matters.
const RECONCILE_TIME := 0.2
## How far out of place a client may be before it stops gliding and simply
## accepts the host's position. Beyond this the two simulations are not
## slightly out of step, they are describing different flights.
const RECONCILE_SNAP_DISTANCE := 4.0

# --- Co-op -------------------------------------------------------------------
## Lives the team starts a run with. The hunter drone spends them; the pipes
## do not, because a pipe hit is the one failure the two players caused.
const LIVES := 5
## Seconds the bird cannot be caught again after losing a life. Long enough
## for the team to recover, short enough that losing all three is a real threat.
const HUNTER_INVULNERABILITY := 2.5

# --- Hunter ------------------------------------------------------------------
## How far in front of the bird the drone holds station, in metres. Negative z
## is forward, so the drone sits ahead of the bird rather than level with it.
##
## This is a framing decision as much as a physics one. The camera sits a third
## of a metre behind the bird, so a drone holding the bird's own depth is level
## with the lens: it is either invisible off to one side or filling the screen,
## and a threat the player cannot see is not a threat.
const HUNTER_DEPTH_OFFSET := -4.0
## How far in front of the bird the drone hangs before the hunt starts.
const HUNTER_START_DELAY := 8.0
## How long the drone keeps its distance after a catch.
const HUNTER_RETREAT_TIME := 2.5
## Top speed, and the drag that gets it there. Both are what make the drone a
## hunter rather than a projectile: it cannot accelerate without limit, so
## where it wants to be still matters.
const HUNTER_MAX_SPEED := 7.0
const HUNTER_DRAG := 1.1
const HUNTER_THRUST := 26.0
## Steering gain and response, the same two-term shape the co-pilot's steer
## uses, because both are acceleration controls.
const HUNTER_GAIN := 2.2
const HUNTER_RESPONSE := 2.4
## Longest the lead point extrapolates the bird's velocity.
const HUNTER_MAX_LEAD := 0.8
## Radii, in metres. Dive is inside pressure, pressure is inside the wake.
const HUNTER_DIVE_RADIUS := 1.6
const HUNTER_PRESSURE_RADIUS := 4.0
## How fast the drone orbits while pressuring, in radians per second.
const HUNTER_ORBIT_RATE := 1.7
## Odds per second, scaled by the skill profile's aggression, that a drone
## within DIVE_RADIUS commits to a pass.
const HUNTER_DIVE_CHANCE := 1.2
## How long a dive lasts, in seconds. A transit, not a hover: the drone
## commits, passes through, and the pass can miss.
const HUNTER_DIVE_TIME := 1.0
## How close the drone must get to count as a catch.
const HUNTER_CONTACT_RADIUS := 0.8
## Radius of the drone's wake, and the force at its centre, in m/s^2. Zero
## outside: the wake is a place the player can stay out of, which is the whole
## reason it is a radius and not a constant.
const HUNTER_FORCE_RADIUS := 5.0
const HUNTER_FORCE := 1.5
## Radius of the drawn drone.
const HUNTER_VISUAL_RADIUS := 0.75

# --- Obstacles --------------------------------------------------------------
## Gap between two pipes at score 0, and the tightest gap the game ever uses.
const GAP_START := 5.0
const GAP_MIN := 2.8
## Score at which the difficulty curve reaches its maximum.
const SCORE_FOR_MAX_DIFFICULTY := 30

## Radius of a pipe.
const PIPE_RADIUS := 1.3
## Depth of a pipe along the flight axis.
const PIPE_DEPTH := 3.0
## How far in front of the bird the next pipe is created.
const SPAWN_DISTANCE := 45.0
## Distance between consecutive pipes.
const PIPE_SPACING := 13.0
## Pipes kept alive ahead of the bird, beyond the first. Together with the
## spawn distance and the spacing this sets the visible length of the course.
const CORRIDOR_PIPES := 4
## Largest vertical change of a gap centre between consecutive pipes. The
## generator tightens this further as the bird speeds up, because a faster
## bird has proportionally less time to climb between pipes.
const MAX_GAP_CENTER_DELTA := 3.0
## Metres per second the bird can sustainably gain by flapping. The ceiling is
## FLAP_IMPULSE / (FLAP_IMPULSE / GRAVITY) = 3.5; the generator uses a safety
## factor below that so generated courses stay comfortably flyable.
const CLIMB_RATE := 3.2
## Neutral gap centre used when the generator starts.
const GAP_CENTER_DEFAULT := 6.5
## Pipes further than this behind the bird are freed.
const CULL_DISTANCE := 25.0

# --- World dressing ---------------------------------------------------------
## Length of the scrolling ground stripe, and the gap between stripes. The
## stripes are what make forward motion readable at first-person speed.
const GROUND_STRIPE_LENGTH := 6.0
const GROUND_STRIPE_SPACING := 9.0
const GROUND_STRIPE_COUNT := 26
## Length of the solid ground slab that follows the bird.
const GROUND_SLAB_LENGTH := 400.0

# --- Presentation -----------------------------------------------------------
## Wing flap animation duration.
const WING_FLAP_DURATION := 0.22
## Seconds between automatic flaps when the game is driven by --autoplay.
const AUTOPLAY_FLAP_INTERVAL := 0.42
