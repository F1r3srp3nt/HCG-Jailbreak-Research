//
//  PortalLog.h
//  HCG Portal — Hakmi Capital Group
//
//  Unified logging only (os_log). Nothing is written to disk by the logger and
//  nothing leaves the device. On the device:
//    log stream --predicate 'subsystem == "com.hakmicapitalgroup.portal"'
//

#import <Foundation/Foundation.h>
#import <os/log.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Toggled by the "Diagnostic Logging" preference. Errors are always logged.
extern BOOL PortalDiagnosticLoggingEnabled;
os_log_t PortalLogHandle(void);

#ifdef __cplusplus
}
#endif

#define PortalLogDebug(fmt, ...)                                              \
    do {                                                                      \
        if (PortalDiagnosticLoggingEnabled)                                   \
            os_log(PortalLogHandle(), "[HCGPortal] " fmt, ##__VA_ARGS__);     \
    } while (0)

#define PortalLogInfo(fmt, ...) os_log(PortalLogHandle(), "[HCGPortal] " fmt, ##__VA_ARGS__)
#define PortalLogError(fmt, ...) os_log_error(PortalLogHandle(), "[HCGPortal] " fmt, ##__VA_ARGS__)
