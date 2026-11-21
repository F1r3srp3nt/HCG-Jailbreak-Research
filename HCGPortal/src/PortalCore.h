//
//  PortalCore.h
//  HCG Portal — Hakmi Capital Group
//
//  The pure C core, shared by the SpringBoard tweak, the Settings bundle, the
//  host tests (tests/test_core.c) and the Simulator harnesses. No UIKit, no
//  Objective-C, no allocation: every decision that can be tested without a
//  phone lives here.
//
//    - appearance and placement values: defaults, ranges, clamping (NaN-safe)
//    - render plan: Reduce Motion, Low Power Mode, intensity -> what animates
//    - layout: where the portal goes between the clock/widgets and the first
//      notification / media platter / quick action, and when it shrinks,
//      collapses to a compact orb or hides
//    - radial menu geometry: item centres that stay on screen and never overlap
//    - access (0.1.0~beta4): Portal is usable only while iOS itself reports the
//      device unlocked, by every source available; any "locked" or any
//      missing source keeps it closed (fail closed). Each revocation starts a
//      new access epoch, so nothing queued before a lock can run after it
//    - visibility: when the portal is shown and rendering runs
//    - the pending action: exactly the selected action runs once, only if its
//      access epoch is still current when it is about to run; a relock, a
//      timeout, screen-off or disabling discard it
//

#ifndef PORTAL_CORE_H
#define PORTAL_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

// ---- Appearance and placement ---------------------------------------------

#define PORTAL_SIZE_MIN 96.0
#define PORTAL_SIZE_MAX 180.0
#define PORTAL_SIZE_DEFAULT 132.0
#define PORTAL_COMPACT_SIZE 56.0
#define PORTAL_OFFSET_X_LIMIT 120.0
#define PORTAL_OFFSET_Y_MIN (-40.0)
#define PORTAL_OFFSET_Y_MAX 240.0
#define PORTAL_OFFSET_Y_DEFAULT 16.0
#define PORTAL_BRIGHTNESS_MIN 0.2
#define PORTAL_BRIGHTNESS_DEFAULT 0.85
#define PORTAL_SPEED_MIN 0.25
#define PORTAL_SPEED_MAX 2.0
#define PORTAL_SPEED_DEFAULT 1.0
#define PORTAL_INTENSITY_DEFAULT 0.6

typedef enum {
    PORTAL_PALETTE_SIGNATURE = 0, // cyan and violet (default)
    PORTAL_PALETTE_AURORA,        // teal and green
    PORTAL_PALETTE_SOLAR,         // amber and rose
    PORTAL_PALETTE_MONO,          // white and silver
    PORTAL_PALETTE_COUNT
} PortalPalette;

typedef struct {
    int palette;        // PortalPalette
    double brightness;  // 0.2 ... 1
    double speed;       // 0.25 ... 2 (animation-speed multiplier)
    double intensity;   // 0 ... 1 (glow and particles)
} PortalAppearance;

typedef struct {
    double size;     // portal diameter in points, 96 ... 180
    double offsetX;  // from the horizontal centre, -120 ... 120
    double offsetY;  // below the clock/widgets anchor, -40 ... 240
} PortalPlacement;

typedef struct {
    double r, g, b;
} PortalRGB;

void portal_appearance_defaults(PortalAppearance *a);
void portal_appearance_clamp(PortalAppearance *a);
void portal_placement_defaults(PortalPlacement *p);
void portal_placement_clamp(PortalPlacement *p);

// Identifiers used in preferences ("signature", "aurora", "solar", "mono").
const char *portal_palette_id(int palette);
int portal_palette_from_id(const char *identifier); // unknown -> SIGNATURE
// The two energy colours (primary ring, secondary ring) of a palette.
void portal_palette_colours(int palette, PortalRGB *primary, PortalRGB *secondary);

// ---- Render plan -----------------------------------------------------------

typedef enum {
    PORTAL_LOWPOWER_STATIC = 0, // default: static appearance, no particles
    PORTAL_LOWPOWER_ECONOMY,    // slow rings, no particles, one glow layer
    PORTAL_LOWPOWER_HIDE,       // nothing drawn
    PORTAL_LOWPOWER_COUNT
} PortalLowPowerPolicy;

const char *portal_low_power_id(int policy);    // "static", "economy", "hide"
int portal_low_power_from_id(const char *identifier); // unknown -> STATIC

typedef struct {
    int draw;               // anything at all
    int animate;            // rings rotate, core breathes
    int particles;          // emitter on
    int glowLayers;         // 0 ... 3
    double ringPeriod;      // seconds per lap of the outer ring (when animating)
    double particleRate;    // particles per second (when on): restrained, <= 6
    int unlockAnimation;    // the brief opening flourish on unlock
    int reason;             // PortalPlanReason
} PortalRenderPlan;

typedef enum {
    PORTAL_PLAN_FULL = 0,
    PORTAL_PLAN_REDUCE_MOTION,
    PORTAL_PLAN_LOW_POWER_STATIC,
    PORTAL_PLAN_LOW_POWER_ECONOMY,
    PORTAL_PLAN_LOW_POWER_HIDDEN,
} PortalPlanReason;

PortalRenderPlan portal_render_plan(const PortalAppearance *appearance, int reduceMotion, int lowPower,
                                    int lowPowerPolicy, int unlockAnimationEnabled);

// ---- Layout ----------------------------------------------------------------

#define PORTAL_MAX_OBSTACLES 32
#define PORTAL_GAP 12.0           // clearance to the clock and to obstacles
#define PORTAL_EDGE_MARGIN 16.0   // clearance to the screen sides
#define PORTAL_BOTTOM_RESERVE 128.0 // flashlight, camera and home indicator when not reported

typedef struct {
    double x, y, w, h;
} PortalRect;

typedef struct {
    PortalRect bounds;      // host view bounds (portrait)
    PortalRect safe;        // safe-area rectangle inside bounds
    int anchorKnown;        // the clock / widget bottom was found
    double anchorBottom;    // y of the lowest clock or widget edge
    int obstacleCount;
    PortalRect obstacles[PORTAL_MAX_OBSTACLES]; // notifications, media, live activities, quick actions…
} PortalLayoutInput;

typedef enum {
    PORTAL_LAYOUT_HIDDEN = 0, // no room at all: nothing drawn, nothing intercepted
    PORTAL_LAYOUT_FULL,       // the chosen size
    PORTAL_LAYOUT_REDUCED,    // smaller than chosen, still >= PORTAL_SIZE_MIN
    PORTAL_LAYOUT_COMPACT,    // a 56 pt orb
} PortalLayoutMode;

typedef struct {
    int mode;          // PortalLayoutMode
    double cx, cy;     // centre in host coordinates
    double diameter;   // drawn diameter
    double hitRadius;  // touch radius (>= 22 pt so the target is >= 44 pt)
    double anchor;     // the anchor actually used
    double floor;      // the lowest y the portal may reach
} PortalLayout;

double portal_estimated_anchor(const PortalRect *bounds, const PortalRect *safe);
PortalLayout portal_layout(const PortalLayoutInput *in, const PortalPlacement *placement);
const char *portal_layout_mode_name(int mode);

// ---- Radial menu -----------------------------------------------------------

#define PORTAL_MENU_MAX_ITEMS 6
#define PORTAL_MENU_ITEM_SIZE 64.0   // touch target and backing disc
#define PORTAL_MENU_ITEM_GAP 8.0

typedef struct {
    int count;
    double radius;                       // orbit radius
    double x[PORTAL_MENU_MAX_ITEMS];     // item centres
    double y[PORTAL_MENU_MAX_ITEMS];
    double extentRadius;                 // circle around the portal centre containing every item
    int shifted;                         // no facing fitted; the fan was shifted and may cover the portal
} PortalMenuLayout;

// Items fan out around the portal on an orbit that clears it: below it when
// they fit (the clock is above), otherwise the first facing that keeps every
// 64 pt disc inside `safe`. Never squeezed.
PortalMenuLayout portal_menu_layout(const PortalLayout *portal, int count, const PortalRect *safe);
// Index of the item whose disc contains (x, y), or -1.
int portal_menu_hit(const PortalMenuLayout *menu, double x, double y);

// ---- Access (iOS unlock state) ------------------------------------------------
// Each source is PORTAL_SIGNAL_YES / _NO, or _UNKNOWN when it could not be read on this iOS.

#define PORTAL_SIGNAL_UNKNOWN (-1)
#define PORTAL_SIGNAL_NO 0
#define PORTAL_SIGNAL_YES 1

typedef struct {
    int protectedDataAvailable; // -[UIApplication isProtectedDataAvailable]: the keybag is unlocked (NO before the first unlock)
    int lockStateLocked;        // Darwin state com.apple.springboard.lockstate != 0
    int uiLocked;               // -[SBLockScreenManager isUILocked]
    int inSecureApp;            // -[SBCoverSheetPresentationManager isInSecureApp] (camera over the Lock Screen)
    int screenOn;               // Darwin state com.apple.springboard.hasBlankedScreen == 0
} PortalAccessInput;

typedef enum {
    PORTAL_ACCESS_GRANTED = 0,  // every required source reports unlocked
    PORTAL_ACCESS_LOCKED,       // some source reports locked (or before the first unlock)
    PORTAL_ACCESS_UNVERIFIED,   // a required source is unavailable: closed
    PORTAL_ACCESS_SCREEN_OFF,   // the display is off
} PortalAccess;

// Granted only if protectedDataAvailable == YES, lockStateLocked == NO and uiLocked == NO
// (all three required), the screen is not reported off and no secure app is reported.
PortalAccess portal_access(const PortalAccessInput *in);
const char *portal_access_name(int access);

typedef struct {
    int granted;
    unsigned epoch; // advances whenever access opens or closes; never 0
} PortalAccessSession;

void portal_access_session_init(PortalAccessSession *s); // starts closed
// Applies a fresh decision. Returns 1 if this revoked access (granted -> not granted).
int portal_access_session_apply(PortalAccessSession *s, PortalAccess access);
// Whether something captured at `epoch` may run now: access granted and not revoked since.
int portal_access_permits(const PortalAccessSession *s, unsigned epoch);

// ---- Visibility --------------------------------------------------------------

typedef struct {
    int enabled;           // master switch
    int killSwitch;        // kill switch file at launch
    int fault;             // fault fallback or launch guard
    int hostAttached;      // the portal view is inside a Cover Sheet view
    int coverSheetVisible; // Cover Sheet on screen
    int screenOn;          // display not blanked
    int accessGranted;     // portal_access() == PORTAL_ACCESS_GRANTED (iOS reports the device unlocked)
    int opening;           // a selected destination is opening (the Cover Sheet is being dismissed)
    int layoutMode;        // PortalLayoutMode
    int planDraws;         // render plan draws something
} PortalVisibilityInput;

typedef enum {
    PORTAL_VIS_VISIBLE = 0,
    PORTAL_VIS_DISABLED,
    PORTAL_VIS_KILL_SWITCH,
    PORTAL_VIS_FAULT,
    PORTAL_VIS_NO_HOST,
    PORTAL_VIS_SCREEN_OFF,
    PORTAL_VIS_NOT_COVER_SHEET, // the Cover Sheet is not on screen
    PORTAL_VIS_OPENING,
    PORTAL_VIS_NO_ROOM,
    PORTAL_VIS_LOW_POWER_HIDDEN,
    PORTAL_VIS_LOCKED,          // access not granted: nothing of Portal exists on screen
} PortalVisibility;

PortalVisibility portal_visibility(const PortalVisibilityInput *in);
const char *portal_visibility_name(int visibility);

// ---- Destinations and the pending protected action -----------------------------

typedef enum {
    PORTAL_DEST_NEXUS = 0,
    PORTAL_DEST_BACKGROUNDS,
    PORTAL_DEST_DEVICES,
    PORTAL_DEST_APPS,
    PORTAL_DEST_COUNT,
    PORTAL_DEST_APP_ITEM = 100, // a chosen app; `item` is its index
} PortalDestination;

typedef enum {
    PORTAL_AVAIL_AVAILABLE = 0,
    PORTAL_AVAIL_NOT_INSTALLED,       // companion package absent
    PORTAL_AVAIL_NEEDS_INTERFACE,     // installed, but without the interface Portal needs
    PORTAL_AVAIL_NOT_CONNECTED,       // Devices: no Connector / Origin integration exists yet
    PORTAL_AVAIL_NO_APPS,             // HCG apps: none chosen (or none still installed)
    PORTAL_AVAIL_LAUNCHER_UNAVAILABLE,// this iOS lacks the launcher Portal uses
} PortalAvailability;

typedef struct {
    int launcherAvailable;
    int nexusInstalled;
    int nexusOpenInterface;     // HCGNexusPortalInterface v1 present and active
    int animationCenterInstalled;
    int appCount;               // chosen apps that are installed
} PortalDestinationProbe;

PortalAvailability portal_destination_availability(int destination, const PortalDestinationProbe *probe);
// Whether selecting the destination runs an action (opens something). Devices does nothing
// yet; HCG Apps only shows its ring. Every action re-checks access right before it runs.
int portal_destination_performs_action(int destination);
const char *portal_destination_id(int destination);

// Opening dismisses the Cover Sheet first; the action waits for that, then runs.
#define PORTAL_PENDING_TIMEOUT 10.0

typedef struct {
    int awaiting;
    unsigned generation;   // of the current (or last) request; never 0 once used
    int destination;
    int item;
    double startedAt;
    unsigned accessEpoch;  // the access epoch the action was selected in
} PortalPending;

typedef struct {
    int perform;      // run exactly this action now
    int destination;
    int item;
} PortalPendingOutcome;

void portal_pending_init(PortalPending *p);
// Starts a request selected while access had `accessEpoch`. Returns its generation, or 0 if
// a request is already waiting (the second tap is ignored rather than replacing the first).
unsigned portal_pending_begin(PortalPending *p, int destination, int item, double now, unsigned accessEpoch);
// The preparation (Cover Sheet dismissal) finished. Only the generation that is waiting,
// finishing with success within the timeout, while `access` still permits its epoch (no
// relock since it was selected, and unlocked now), performs its action; everything else is
// discarded. Any outcome for the waiting generation clears it.
PortalPendingOutcome portal_pending_resolve(PortalPending *p, unsigned generation, int success, double now,
                                            const PortalAccessSession *access);
// Screen off, Portal disabled, fault: discard whatever is waiting.
void portal_pending_cancel(PortalPending *p);
// Expire a request that never completed.
int portal_pending_expire(PortalPending *p, double now);

// ---- Crash guard ----------------------------------------------------------
// Counted on every SpringBoard launch with Portal installed (enabled or not). A launch that
// stays up PORTAL_STABLE_AFTER_SECONDS resets the count. Returns 1 when Portal must do
// nothing this launch. Negative counts (corrupt preferences) never block.
int portal_launch_guard_blocks(long consecutiveUnstableLaunches, long maximum);

#ifdef __cplusplus
}
#endif

#endif
