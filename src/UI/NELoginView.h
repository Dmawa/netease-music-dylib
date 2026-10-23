//  NELoginView.h
//  扫码登录界面：自适应尺寸、二维码过期重取、状态提示
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol NELoginViewDelegate <NSObject>
/// 登录成功（此时 MUSIC_U 已确认落盘）
- (void)loginViewDidLogin:(id)view nickname:(nullable NSString *)nickname;
/// 用户点了关闭
- (void)loginViewDidCancel:(id)view;
@end

@interface NELoginView : UIView
@property (nonatomic, weak, nullable) id<NELoginViewDelegate> delegate;
/// 开始拉取二维码并轮询
- (void)start;
/// 停止轮询（界面关闭时调用，避免后台请求）
- (void)stop;
@end

NS_ASSUME_NONNULL_END