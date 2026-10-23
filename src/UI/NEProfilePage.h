//  NEProfilePage.h
//  「我的」页：账号横幅（头像/昵称/VIP/关注/粉丝/等级/听歌量）+ 歌单列表
#import <UIKit/UIKit.h>
#import "NEApi.h"

NS_ASSUME_NONNULL_BEGIN

@protocol NEProfilePageDelegate <NSObject>
/// 点开某个歌单
- (void)profilePage:(id)page didSelectPlaylist:(NEPlaylist *)playlist;
/// 点右上角三条杠（设置）
- (void)profilePageDidTapSettings:(id)page;
/// 「我喜欢的音乐」右侧的心动模式
- (void)profilePageDidRequestHeartMode:(id)page;
@end

@interface NEProfilePage : UIView
@property (nonatomic, weak, nullable) id<NEProfilePageDelegate> delegate;
- (void)reloadData;
@end

NS_ASSUME_NONNULL_END
