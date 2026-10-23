#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 应用内打开网易云官方网页登录。
/// 官方页面自己处理扫码 / 手机号 / 短信，成功后 MUSIC_U 会写进共享 Cookie 存储，
/// 宿主的 NESession 直接就能读到——绕过第三方客户端被风控的问题。
@interface NEWebLogin : UIViewController
@property (nonatomic, copy, nullable) void (^onSuccess)(void);
@property (nonatomic, copy, nullable) void (^onCancel)(void);
@end

NS_ASSUME_NONNULL_END
