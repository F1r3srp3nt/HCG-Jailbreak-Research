//
//  HACLog.h
//  HCG Animation Center — Hakmi Capital Group
//
//  Unified logging only (os_log). Nothing is written to disk by the logger
//  and nothing leaves the device. On the device:
//    log stream --predicate 'subsystem == "com.hakmicapitalgroup.animationcenter"'
//

#import <Foundation/Foundation.h>
#import <os/log.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Toggled by the "Diagnostic Logging" preference. Errors are always logged.
extern BOOL HACDiagnosticLoggingEnabled;
os_log_t HACLogHandle(void);

#ifdef __cplusplus
}
#endif

#define HACLogDebug(fmt, ...)                                                \
    do {                                                                     \
        if (HACDiagnosticLoggingEnabled)                                     \
            os_log(HACLogHandle(), "[HCGAnimationCenter] " fmt, ##__VA_ARGS__); \
    } while (0)

#define HACLogInfo(fmt, ...) os_log(HACLogHandle(), "[HCGAnimationCenter] " fmt, ##__VA_ARGS__)
#define HACLogError(fmt, ...) os_log_error(HACLogHandle(), "[HCGAnimationCenter] " fmt, ##__VA_ARGS__)
