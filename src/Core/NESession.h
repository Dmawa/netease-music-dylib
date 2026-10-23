//  NESession.h
//  网易云 HTTP 会话：Cookie 持久化 + 请求封装
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^NECompletion)(id _Nullable json, NSError * _Nullable error);

@interface NESession : NSObject

+ (instancetype)shared;

/// 已持久化的 Cookie 串，可直接塞进请求头
@property (nonatomic, copy, readonly) NSString *cookieHeader;
/// 是否已拿到有效登录态（依据 MUSIC_U 判定）
@property (nonatomic, assign, readonly) BOOL isLoggedIn;

/// GET：自动附带 Cookie / 网易云要求的 UA 与 Referer
- (void)GET:(NSString *)path
     params:(nullable NSDictionary<NSString *, id> *)params
   complete:(NECompletion)complete;

/// POST：application/x-www-form-urlencoded
- (void)POST:(NSString *)path
      params:(nullable NSDictionary<NSString *, id> *)params
    complete:(NECompletion)complete;

/// 直接把服务端下发的 Set-Cookie 合并进来
- (void)absorbResponseCookies:(NSURLResponse *)response;
/// 清空登录态
- (void)clearCookies;

@end

NS_ASSUME_NONNULL_END