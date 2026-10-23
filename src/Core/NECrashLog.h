//  NECrashLog.h
//  未捕获异常记录：崩溃后下次启动可在「设置 → 关于 → 上次崩溃」里查看
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

void NECrashLogInstall(void);
NSString * _Nullable NECrashLogLast(void);
void NECrashLogClear(void);

NS_ASSUME_NONNULL_END
