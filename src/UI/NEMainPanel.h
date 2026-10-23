//  NEMainPanel.h
//  面板内容：登录 / 搜索 / 列表 / 播放器。整体可被替换而不影响 Core。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NEMainPanel : UIView
/// 由外部（悬浮窗）创建后安装
- (void)start;
@end

NS_ASSUME_NONNULL_END