//
//  PortalLog.m
//  HCG Portal — Hakmi Capital Group
//

#import "PortalLog.h"

BOOL PortalDiagnosticLoggingEnabled = NO;

os_log_t PortalLogHandle(void) {
    static os_log_t handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = os_log_create("com.hakmicapitalgroup.portal", "engine");
    });
    return handle;
}
