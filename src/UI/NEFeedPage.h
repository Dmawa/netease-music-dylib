//  NEFeedPage.h
//  通用信息流页：给一个接口路径，按常见字段渲染成封面列表（播客 / 笔记用）
#import <UIKit/UIKit.h>
#import "NESession.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^NEFeedTapBlock)(NSDictionary *item);

@interface NEFeedPage : UIView
/// arrayKeys：按顺序尝试从响应里取数组，如 @[@"data.blocks", @"data", @"list"]
- (instancetype)initWithTitle:(NSString *)title
                         path:(NSString *)path
                       params:(nullable NSDictionary<NSString *, id> *)params
                    arrayKeys:(NSArray<NSString *> *)arrayKeys;
- (void)reload;
@property (nonatomic, copy, nullable) NEFeedTapBlock onTapItem;
@end

NS_ASSUME_NONNULL_END
