//  NEProfilePage.h
//  「我的」页：头像昵称 + 我喜欢的音乐 + 我的歌单
#import <UIKit/UIKit.h>
#import "NEApi.h"

NS_ASSUME_NONNULL_BEGIN

@protocol NEProfilePageDelegate <NSObject>
/// 点开某个歌单
- (void)profilePage:(id)page didSelectPlaylist:(NEPlaylist *)playlist;
@end

@interface NEProfilePage : UIView
@property (nonatomic, weak, nullable) id<NEProfilePageDelegate> delegate;
- (void)reloadData;
@end

NS_ASSUME_NONNULL_END