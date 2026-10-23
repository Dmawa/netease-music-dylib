//  NESession.h
//  网易云 HTTP 会话：Cookie 持久化 + 请求封装
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^NECompletion)(id _Nullable json, NSError * _Nullable error);

@interface NESession : NSObject

+ (instancetype)shared;

@property (nonatomic, copy, readonly) NSString *cookieHeader;
/// 依据 MUSIC_U 判定是否已登录
@property (nonatomic, assign, readonly) BOOL isLoggedIn;

- (void)GET:(NSString *)path
     params:(nullable NSDictionary<NSString *, id> *)params
   complete:(NECompletion)complete;

- (void)POST:(NSString *)path
      params:(nullable NSDictionary<NSString *, id> *)params
    complete:(NECompletion)complete;

/// 读取单个 cookie（如 MUSIC_U / __csrf）
- (nullable NSString *)valueForCookie:(NSString *)name;
/// 合并响应里的 Set-Cookie
- (void)absorbResponseCookies:(NSURLResponse *)response;
/// 退出登录
- (void)clearCookies;

@end

NS_ASSUME_NONNULL_END