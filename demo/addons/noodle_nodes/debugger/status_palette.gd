@tool
## Status colours shared by every debugger view and the in-game overlay.

const UNVISITED := Color(0.45, 0.45, 0.5)
const RUNNING := Color(1.0, 0.8, 0.2)
const SUCCESS := Color(0.35, 0.85, 0.4)
const FAILURE := Color(0.95, 0.35, 0.35)
const INTERRUPTED := Color(0.75, 0.5, 0.95)
const SKIP := Color(0.55, 0.6, 0.65)
const ACTIVE := Color(0.35, 0.75, 1.0)
const PENDING := Color(0.9, 0.9, 0.9)
const VERIFYING := Color(0.4, 0.7, 1.0)
const STAGED := Color(0.6, 0.9, 0.6)
const CANCELLED := Color(0.6, 0.6, 0.6)

const BY_STATUS := {
	"unvisited": UNVISITED,
	"running": RUNNING,
	"success": SUCCESS,
	"succeeded": SUCCESS,
	"failure": FAILURE,
	"failed": FAILURE,
	"interrupted": INTERRUPTED,
	"skip": SKIP,
	"active": ACTIVE,
	"pending": PENDING,
	"verifying": VERIFYING,
	"staged": STAGED,
	"cancelled": CANCELLED,
}

## Seconds over which a node's highlight fades back after its last visit.
const RECENCY_FADE_SEC := 1.0


static func for_status(status: String) -> Color:
	return BY_STATUS.get(status, UNVISITED)


## Blends c towards UNVISITED as age_usec approaches RECENCY_FADE_SEC.
static func faded(c: Color, age_usec: int) -> Color:
	var t := clampf(float(age_usec) / (RECENCY_FADE_SEC * 1000000.0), 0.0, 1.0)
	return c.lerp(UNVISITED, t * 0.7)
