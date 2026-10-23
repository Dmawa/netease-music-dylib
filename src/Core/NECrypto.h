//  NECrypto.h
//  网易云 weapi 请求体加密（AES-128-CBC 两层 + RSA-1024）
//
//  为什么需要：
//    官方 web 登录早就换成 /weapi/ 加密接口了。继续用明文的
//    /api/login/qrcode/* 也能拿到 key，但扫码确认时服务端会把它当成
//    旧版客户端，回 8821「请切换其他登录方式或升级新版本再试」。
//    这里的实现与官方前端 core.js 的 asrsea 完全一致。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NECrypto : NSObject

/// 生成 "params=...&encSecKey=..."（已按 urlencoded 编码），失败返回 nil
+ (nullable NSString *)weapiBodyWithData:(NSDictionary<NSString *, id> *)data;

@end

NS_ASSUME_NONNULL_END
