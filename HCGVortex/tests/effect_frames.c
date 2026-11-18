//
//  effect_frames.c — dumps the REAL per-icon effect geometry as JSON for previews.
//
//      tests/build/effect_frames <effect> [frames] > frames.json
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
    const double W = 390.0, H = 844.0;
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

    VortexIconSlot slots[24];
    int n = 0;
    for (int row = 0; row < 6; row++)
        for (int col = 0; col < 4; col++, n++) {
            slots[n].homeX = -146.25 + col * 97.5;
            slots[n].homeY = -300.0 + row * 110.0;
        }
    vortex_tornado_rank(slots, n, 8.0);

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
            for (int i = 0; i < n; i++) {
                VortexIconVisual v = vortex_icon_effect_visual(kind, role, p, VortexNavigationForward, slots[i], W, H, &s, &ep);
                VortexTrace t = vortex_icon_effect_trace(kind, role, p, VortexNavigationForward, slots[i], W, H, &s, &ep);
                printf("%s{\"page\":%d,\"i\":%d,\"x\":%.2f,\"y\":%.2f,\"s\":%.4f,\"r\":%.4f,\"tx\":%.4f,\"ty\":%.4f,"
                       "\"z\":%.2f,\"o\":%.4f,\"trace\":{\"a\":%.4f,\"pts\":[",
                       (role == VortexPageRoleOutgoing && i == 0) ? "" : ",", role - 1, i, slots[i].homeX + v.tx,
                       slots[i].homeY + v.ty, v.scale, v.rotation, v.tiltX, v.tiltY, v.z, v.opacity, t.alpha);
                for (int q = 0; q < t.count; q++) printf("%s[%.2f,%.2f]", q ? "," : "", t.points[q].x, t.points[q].y);
                printf("]}}");
            }
        }
        printf("]}%s\n", f + 1 < frames ? "," : "");
    }
    printf("]}\n");
    return 0;
}
