//  NEQRCode.h
//  极简 QR 码生成器（字节模式，自动选版本 1-10，纠错等级 M）。
//  只依赖 Foundation/CoreGraphics，不引入第三方库。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NEQRCode : NSObject
/// 生成二维码图片；size 为期望边长（像素）
+ (nullable UIImage *)imageWithText:(NSString *)text size:(CGFloat)size;
/// 返回模块矩阵（YES=黑），便于自测
+ (nullable NSArray<NSArray<NSNumber *> *> *)matrixWithText:(NSString *)text;
@end

NS_ASSUME_NONNULL_END