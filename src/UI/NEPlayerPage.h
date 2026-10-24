//  NEPlayerPage.h
//  播放页：封面 + 歌词 + 进度 + 控制。iPad 与 iPhone 自适应布局。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NEPlayerPage : UIView
- (void)refresh;
/// 点左上角收起按钮（由面板负责切回上一个页签并恢复导航栏）
@property (nonatomic, copy, nullable) void (^onCollapse)(void);
@end

NS_ASSUME_NONNULL_END