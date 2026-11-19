//
//  HaloLog.h
//  HCG Halo — Hakmi Capital Group
//
//  Unified logging only (os_log). Nothing is written to disk by the logger
//  and nothing leaves the device. View with Console.app on a Mac, or on the
//  device: log stream --predicate 'subsystem == "com.hakmicapitalgroup.halo"'
//

#import <Foundation/Foundation.h>
#import <os/log.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Toggled by the "Diagnostic Logging" preference. Errors are always logged.
extern BOOL HaloDiagnosticLoggingEnabled;
os_log_t HaloLogHandle(void);

#ifdef __cplusplus
}
#endif

#define HaloLogDebug(fmt, ...)                                              \
    do {                                                                    \
        if (HaloDiagnosticLoggingEnabled)                                   \
            os_log(HaloLogHandle(), "[HCGHalo] " fmt, ##__VA_ARGS__);       \
    } while (0)

#define HaloLogInfo(fmt, ...) os_log(HaloLogHandle(), "[HCGHalo] " fmt, ##__VA_ARGS__)
#define HaloLogError(fmt, ...) os_log_error(HaloLogHandle(), "[HCGHalo] " fmt, ##__VA_ARGS__)
