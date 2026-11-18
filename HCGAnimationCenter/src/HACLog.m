//
//  HACLog.m
//  HCG Animation Center — Hakmi Capital Group
//

#import "HACLog.h"

BOOL HACDiagnosticLoggingEnabled = NO;

os_log_t HACLogHandle(void) {
    static os_log_t handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = os_log_create("com.hakmicapitalgroup.animationcenter", "engine");
    });
    return handle;
}
