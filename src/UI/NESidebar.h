//  NESidebar.h
//  左侧竖排导航（图标 + 文字），还原网易云桌面/横屏版式
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NESidebarItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *iconName;      // SF Symbol
@property (nonatomic, copy, nullable) NSString *iconNameSelected;
@property (nonatomic, assign) NSInteger tag;
@end

@protocol NESidebarDelegate <NSObject>
- (void)sidebar:(id)sidebar didSelectIndex:(NSInteger)index;
@end

@interface NESidebar : UIView
@property (nonatomic, weak, nullable) id<NESidebarDelegate> delegate;
@property (nonatomic, strong) NSArray<NESidebarItem *> *items;
@property (nonatomic, assign) NSInteger selectedIndex;
/// 窄屏（< 720）时只显示图标，宽度变窄
@property (nonatomic, assign) BOOL compact;
- (void)reload;
@end

NS_ASSUME_NONNULL_END