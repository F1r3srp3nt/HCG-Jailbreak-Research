//
//  HaloLog.m
//  HCG Halo — Hakmi Capital Group
//

#import "HaloLog.h"

BOOL HaloDiagnosticLoggingEnabled = NO;

os_log_t HaloLogHandle(void) {
    static os_log_t handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = os_log_create("com.hakmicapitalgroup.halo", "engine");
    });
    return handle;
}
