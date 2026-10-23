//  NEImageCache.h
//  封面图缓存：内存 + 磁盘，带并发去重
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NEImageCache : NSObject
+ (instancetype)shared;
/// 仅查内存缓存
- (nullable UIImage *)imageForKey:(NSString *)key;
/// 异步加载（内存 -> 磁盘 -> 网络），同一 URL 并发只发一次请求
- (void)loadImageWithURL:(NSString *)url completion:(void (^)(UIImage * _Nullable image))completion;
@end

NS_ASSUME_NONNULL_END