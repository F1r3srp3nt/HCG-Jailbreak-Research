//
//  effect_frames.c — dumps the REAL per-icon effect geometry as JSON for previews.
//
//      tests/build/effect_frames <effect> [frames] [device] > frames.json
//      "device": the recorded iPhone 11 Pro Max layout (414 x 896 pt; outgoing
//      page with 10 icons, incoming page with 24) instead of 390 x 844, 24 + 24.
//      effect: tornado | tornado-subtle | tornado-scifi | orbital | warp | holographic | circuit-flow | magnetic
//
//  A forward swipe (finger left) on a 390 x 844 pt page with a full 4 x 6 grid
//  on both pages, default settings. scripts/render_effect_preview.py draws it.
//  This shows the geometry only; it is not a capture of SpringBoard.
//

#include "../src/VortexIconEffects.h"
#include "../src/VortexMath.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    int device = argc > 3 && !strcmp(argv[3], "device");
    const double W = device ? 414.0 : 390.0, H = device ? 896.0 : 844.0;
    const char *name = argc > 1 ? argv[1] : "tornado";
    int frames = argc > 2 ? atoi(argv[2]) : 61;
    if (frames < 2) frames = 2;
    static const char *kinds[] = { "tornado", "orbital", "warp", "holographic", "circuit-flow", "magnetic" };
    VortexIconEffectSettings s = vortex_icon_settings_defaults();
    int kind = -1;
    if (!strcmp(name, "tornado-subtle")) { kind = 0; s.tornado = vortex_tornado_preset(VortexTornadoPresetSubtle); }
    else if (!strcmp(name, "tornado-scifi")) { kind = 0; s.tornado = vortex_tornado_preset(VortexTornadoPresetSciFi); }
    for (int k = 0; k < VortexIconEffectCount && kind < 0; k++) if (!strcmp(name, kinds[k])) kind = k;
    if (kind < 0) { fprintf(stderr, "unknown effect %s\n", name); return 2; }
    VortexEffectParameters ep = vortex_default_parameters();

    /* Two pages: slots[0] outgoing, slots[1] incoming, each ranked on its own as the engine does. */
    VortexIconSlot slots[2][24];
    int counts[2] = { device ? 10 : 24, 24 };
    double colPitch = device ? 103.5 : 97.5, rowPitch = device ? 117.0 : 110.0;
    for (int pg = 0; pg < 2; pg++) {
        for (int k = 0; k < counts[pg]; k++) {
            slots[pg][k].homeX = -1.5 * colPitch + (k % 4) * colPitch;
            slots[pg][k].homeY = -2.5 * rowPitch - (device ? 40.0 : 0.0) + (k / 4) * rowPitch;
        }
        vortex_tornado_rank(slots[pg], counts[pg], 8.0);
    }

    printf("{\"effect\":\"%s\",\"page\":[%.1f,%.1f],\"frames\":[\n", name, W, H);
    for (int f = 0; f < frames; f++) {
        double p = (double)f / (frames - 1);
        printf("{\"p\":%.4f,\"pages\":[", p);
        for (int role = VortexPageRoleOutgoing; role <= VortexPageRoleIncoming; role++) {
            VortexPageVisual pv = vortex_icon_effect_page(kind, role, p, VortexNavigationForward, &ep);
            printf("%s{\"dx\":%.4f,\"dy\":%.4f,\"o\":%.4f}", role == VortexPageRoleOutgoing ? "" : ",",
                   pv.translation.x, pv.translation.y, isnan(pv.opacity) ? 1.0 : pv.opacity);
        }
        printf("],\"icons\":[");
        for (int role = VortexPageRoleOutgoing; role <= VortexPageRoleIncoming; role++) {
            int pg = role - 1;
            for (int i = 0; i < counts[pg]; i++) {
                VortexIconSlot sl = slots[pg][i];
                VortexIconVisual v = vortex_icon_effect_visual(kind, role, p, VortexNavigationForward, sl, W, H, &s, &ep);
                VortexTrace t = vortex_icon_effect_trace(kind, role, p, VortexNavigationForward, sl, W, H, &s, &ep);
                printf("%s{\"page\":%d,\"i\":%d,\"x\":%.2f,\"y\":%.2f,\"s\":%.4f,\"r\":%.4f,\"tx\":%.4f,\"ty\":%.4f,"
                       "\"z\":%.2f,\"o\":%.4f,\"trace\":{\"a\":%.4f,\"pts\":[",
                       (role == VortexPageRoleOutgoing && i == 0) ? "" : ",", role - 1, i, sl.homeX + v.tx,
                       sl.homeY + v.ty, v.scale, v.rotation, v.tiltX, v.tiltY, v.z, v.opacity, t.alpha);
                for (int q = 0; q < t.count; q++) printf("%s[%.2f,%.2f]", q ? "," : "", t.points[q].x, t.points[q].y);
                printf("]}}");
            }
        }
        printf("]}%s\n", f + 1 < frames ? "," : "");
    }
    printf("]}\n");
    return 0;
}
