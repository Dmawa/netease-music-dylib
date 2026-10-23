#import "NECrashLog.h"

static NSString *const kNECrashKey = @"NELastCrashInfo";

static void NEUncaughtExceptionHandler(NSException *exception) {
    @try {
        NSString *stack = [[exception callStackSymbols] componentsJoinedByString:@"\n"];
        NSString *info = [NSString stringWithFormat:@"%@\n%@\n%@",
                          exception.name ?: @"Exception",
                          exception.reason ?: @"",
                          stack ?: @""];
        [[NSUserDefaults standardUserDefaults] setObject:info forKey:kNECrashKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } @catch (__unused NSException *e) {
    }
}

void NECrashLogInstall(void) {
    NSSetUncaughtExceptionHandler(&NEUncaughtExceptionHandler);
}

NSString *NECrashLogLast(void) {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kNECrashKey];
}

void NECrashLogClear(void) {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kNECrashKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
