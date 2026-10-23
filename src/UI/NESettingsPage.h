//  NESettingsPage.h
//  设置页：账号信息、VIP、消息、关于、退出登录
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol NESettingsPageDelegate <NSObject>
- (void)settingsPageDidClose:(id)page;
- (void)settingsPageDidLogout:(id)page;
@end

@interface NESettingsPage : UIView
@property (nonatomic, weak, nullable) id<NESettingsPageDelegate> delegate;
- (void)reloadData;
@end

NS_ASSUME_NONNULL_END
