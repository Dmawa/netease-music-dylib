#import "NESidebar.h"
#import "NEUITheme.h"

/// 单个导航项：上图标下文字，选中时图标/文字高亮 + 左侧指示条
@interface NESidebarCell : UIControl
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIView *indicator;
@property (nonatomic, assign) BOOL compact;
- (void)configureWithItem:(NESidebarItem *)item selected:(BOOL)selected;
@end

@implementation NESidebarCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_icon];

        _label = [UILabel new];
        _label.font = [UIFont systemFontOfSize:11];
        _label.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_label];

        _indicator = [[UIView alloc] initWithFrame:CGRectZero];
        _indicator.backgroundColor = NE_BRAND;
        _indicator.layer.cornerRadius = 1.5;
        _indicator.hidden = YES;
        [self addSubview:_indicator];
    }
    return self;
}

- (void)configureWithItem:(NESidebarItem *)item selected:(BOOL)selected {
    UIColor *c = selected ? NE_TEXT : NEColor(0xFFFFFF, 0.50);
    NSString *iconName = selected ? (item.iconNameSelected ?: item.iconName) : item.iconName;
    _icon.image = [UIImage systemImageNamed:iconName ?: @"circle"];
    _icon.tintColor = c;
    _label.text = item.title;
    _label.textColor = c;
    _indicator.hidden = !selected;
    self.label.font = [UIFont systemFontOfSize:11 weight:selected ? UIFontWeightSemibold : UIFontWeightRegular];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat iconSize = self.compact ? 20 : 22;
    _indicator.frame = CGRectMake(0, (h - 16) / 2, 3, 16);
    _icon.frame = CGRectMake((w - iconSize) / 2, 12, iconSize, iconSize);
    _label.frame = CGRectMake(2, CGRectGetMaxY(_icon.frame) + 5, w - 4, 14);
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.65 : 1.0;
}
@end

#pragma mark - 侧边栏

@interface NESidebar ()
@property (nonatomic, strong) UIView *bg;
@property (nonatomic, strong) NSMutableArray<NESidebarCell *> *cells;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, assign) CGFloat lastWidth;
@end

@implementation NESidebar

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _cells = [NSMutableArray array];

        _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _scroll.showsVerticalScrollIndicator = NO;
        [self addSubview:_scroll];
    }
    return self;
}

- (void)setItems:(NSArray<NESidebarItem *> *)items {
    _items = items;
    [self reload];
}

- (void)setCompact:(BOOL)compact {
    _compact = compact;
    [self reload];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self reload];
}

- (void)reload {
    for (NESidebarCell *c in self.cells) [c removeFromSuperview];
    [self.cells removeAllObjects];

    CGFloat w = self.bounds.size.width;
    CGFloat itemH = self.compact ? 52 : 62;
    CGFloat y = 8;
    for (NSInteger i = 0; i < (NSInteger)self.items.count; i++) {
        NESidebarItem *item = self.items[i];
        NESidebarCell *cell = [[NESidebarCell alloc] initWithFrame:CGRectMake(0, y, w, itemH)];
        cell.compact = self.compact;
        cell.tag = 5000 + i;
        [cell configureWithItem:item selected:(i == self.selectedIndex)];
        [cell addTarget:self action:@selector(cellTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:cell];
        [self.cells addObject:cell];
        y += itemH + 2;
    }
    _scroll.contentSize = CGSizeMake(w, y + 10);
}

- (void)cellTapped:(NESidebarCell *)cell {
    NSInteger idx = cell.tag - 5000;
    if (idx < 0 || idx >= (NSInteger)self.items.count) return;
    self.selectedIndex = idx;
    if ([self.delegate respondsToSelector:@selector(sidebar:didSelectIndex:)]) {
        [self.delegate sidebar:self didSelectIndex:idx];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scroll.frame = self.bounds;
    // 只在宽度变化时重建，否则 reload -> layout -> reload 会无限递归
    if (fabs(self.lastWidth - self.bounds.size.width) > 0.5) {
        self.lastWidth = self.bounds.size.width;
        [self reload];
    }
}

@end