//
//  VortexLog.h
//  HCG Vortex — Hakmi Capital Group
//
//  Unified logging only (os_log). Nothing is written to disk and nothing
//  leaves the device. View on a Mac with Console.app (filter "HCGVortex"),
//  or on device with `oslog` / `log stream --predicate 'subsystem == "com.hakmicapitalgroup.vortex"'`.
//

#import <Foundation/Foundation.h>
#import <os/log.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Toggled by the "Diagnostic Logging" preference. Errors are always logged.
extern BOOL VortexDiagnosticLoggingEnabled;
os_log_t VortexLogHandle(void);

#ifdef __cplusplus
}
#endif

#define VortexLogDebug(fmt, ...)                                                       \
    do {                                                                               \
        if (VortexDiagnosticLoggingEnabled)                                            \
            os_log(VortexLogHandle(), "[HCGVortex] " fmt, ##__VA_ARGS__);              \
    } while (0)

#define VortexLogInfo(fmt, ...) os_log(VortexLogHandle(), "[HCGVortex] " fmt, ##__VA_ARGS__)
#define VortexLogError(fmt, ...) os_log_error(VortexLogHandle(), "[HCGVortex] " fmt, ##__VA_ARGS__)
