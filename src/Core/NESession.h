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

/// weapi（AES-128-CBC + RSA-1024）：官方 web 的登录接口走这套，
/// 明文 /api/login/qrcode/* 会被当成旧版客户端（扫码后回 8821）
- (void)POSTWeapi:(NSString *)path
           params:(nullable NSDictionary<NSString *, id> *)params
         complete:(NECompletion)complete;

/// 读取单个 cookie（如 MUSIC_U / __csrf）
- (nullable NSString *)valueForCookie:(NSString *)name;
/// 合并响应里的 Set-Cookie
- (void)absorbResponseCookies:(NSURLResponse *)response;
/// 最近一次响应里的原始 Set-Cookie 行（诊断用）
@property (nonatomic, copy, readonly) NSArray<NSString *> *rawSetCookieLines;
/// 直接写入一个 cookie（登录成功后兜底用）
- (void)setCookieValue:(NSString *)value forName:(NSString *)name;
/// 退出登录
- (void)clearCookies;

@end

NS_ASSUME_NONNULL_END