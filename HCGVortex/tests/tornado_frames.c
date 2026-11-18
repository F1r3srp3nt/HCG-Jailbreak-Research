//
//  tornado_frames.c — dumps the REAL Tornado geometry as JSON for previews.
//
//      tests/build/tornado_frames [frames] [intensity radius rotations direction depth iconSpin] > frames.json
//
//  Uses vortex_tornado_icon / vortex_nav-independent inputs exactly as the
//  engine does for a forward swipe (finger left) on a 390 x 844 pt page with a
//  full 4 x 6 grid on both pages. scripts/render_tornado_preview.py draws it.
//  This shows the geometry only; it is not a capture of SpringBoard.
//

#include "../src/VortexMath.h"
#include "../src/VortexTornado.h"

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    const double W = 390.0, H = 844.0;
    int frames = argc > 1 ? atoi(argv[1]) : 48;
    if (frames < 2) frames = 2;
    VortexTornadoParameters tp = vortex_tornado_defaults();
    if (argc > 7) {
        tp.intensity = atof(argv[2]);
        tp.radius = atof(argv[3]);
        tp.rotations = atof(argv[4]);
        tp.direction = (VortexSpinDirection)atoi(argv[5]);
        tp.depth = atoi(argv[6]);
        tp.iconSpin = atoi(argv[7]);
    }
    tp = vortex_tornado_sanitize(tp);
    VortexEffectParameters ep = vortex_default_parameters();

    VortexIconSlot slots[24];
    int n = 0;
    for (int row = 0; row < 6; row++)
        for (int col = 0; col < 4; col++, n++) {
            slots[n].homeX = -146.25 + col * 97.5;
            slots[n].homeY = -300.0 + row * 110.0;
        }
    vortex_tornado_rank(slots, n, 8.0);

    printf("{\"page\":[%.1f,%.1f],\"params\":{\"intensity\":%.2f,\"radius\":%.2f,\"rotations\":%.2f,\"direction\":%d,"
           "\"depth\":%d,\"iconSpin\":%d},\"frames\":[\n",
           W, H, tp.intensity, tp.radius, tp.rotations, (int)tp.direction, tp.depth, tp.iconSpin);
    for (int f = 0; f < frames; f++) {
        double p = (double)f / (frames - 1);
        VortexPageVisual pout = vortex_tornado_page(VortexPageRoleOutgoing, p, &ep);
        VortexPageVisual pin = vortex_tornado_page(VortexPageRoleIncoming, p, &ep);
        printf("{\"p\":%.4f,\"axis\":%.2f,\"pageOpacity\":[%.4f,%.4f],\"icons\":[", p,
               vortex_tornado_centre_x(p, VortexNavigationForward, W, &ep), pout.opacity, pin.opacity);
        for (int role = VortexPageRoleOutgoing; role <= VortexPageRoleIncoming; role++) {
            for (int i = 0; i < n; i++) {
                VortexIconVisual v = vortex_tornado_icon((VortexPageRole)role, p, VortexNavigationForward, slots[i], W, H, &tp, &ep);
                printf("%s{\"page\":%d,\"i\":%d,\"x\":%.2f,\"y\":%.2f,\"s\":%.4f,\"r\":%.4f,\"z\":%.2f,\"o\":%.4f}",
                       (role == VortexPageRoleOutgoing && i == 0) ? "" : ",", role == VortexPageRoleOutgoing ? 0 : 1, i,
                       slots[i].homeX + v.tx, slots[i].homeY + v.ty, v.scale, v.rotation, v.z, v.opacity);
            }
        }
        printf("]}%s\n", f + 1 < frames ? "," : "");
    }
    printf("]}\n");
    return 0;
}
