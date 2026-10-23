#import "NEPlaylistSheet.h"
#import "NEUITheme.h"
#import "NEPlayer.h"

@interface NEPlaylistSheet () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UISegmentedControl *segment;
@property (nonatomic, strong) UIButton *clearBtn;
@property (nonatomic, assign) NSInteger mode;   // 0=当前播放 1=历史播放
@end

@implementation NEPlaylistSheet

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = NE_PANEL;

    CGFloat W = self.view.bounds.size.width;

    _segment = [[UISegmentedControl alloc] initWithItems:@[@"当前播放", @"历史播放"]];
    _segment.frame = CGRectMake(18, 14, 150, 30);
    _segment.selectedSegmentIndex = 0;
    _segment.tintColor = NE_BRAND;
    [_segment addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_segment];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, 18, W - 140, 26)];
    _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _titleLabel.textColor = NE_TEXT;
    [self.view addSubview:_titleLabel];

    _clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_clearBtn setTitle:@"清空" forState:UIControlStateNormal];
    _clearBtn.frame = CGRectMake(W - 120, 18, 44, 26);
    [_clearBtn addTarget:self action:@selector(clearTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_clearBtn];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    close.frame = CGRectMake(W - 72, 18, 60, 26);
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    _table = [[UITableView alloc] initWithFrame:CGRectMake(0, 60, W, self.view.bounds.size.height - 60)
                                         style:UITableViewStylePlain];
    _table.backgroundColor = UIColor.clearColor;
    _table.separatorColor = NE_STROKE;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = 54;
    _table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_table];

    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 34, W, 20)];
    footer.text = @"一边听边推荐，越听越精准";
    footer.textColor = NE_TEXT_DIM;
    footer.font = [UIFont systemFontOfSize:11];
    footer.textAlignment = NSTextAlignmentCenter;
    footer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:footer];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadQueue)
                                                 name:NEPlayerQueueChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadQueue)
                                                 name:NEPlayerTrackChangedNotification object:nil];
    [self reloadQueue];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)segmentChanged {
    self.mode = self.segment.selectedSegmentIndex;
    self.clearBtn.hidden = (self.mode == 1);
    [self reloadQueue];
}

- (void)reloadQueue {
    NEPlayer *p = [NEPlayer shared];
    NSUInteger count = (self.mode == 0) ? p.queue.count : p.history.count;
    self.titleLabel.text = [NSString stringWithFormat:@"%@ %lu",
                            self.mode == 0 ? @"当前播放" : @"历史播放", (unsigned long)count];
    self.titleLabel.hidden = YES;   // 顶部用分段控件更清楚
    [self.table reloadData];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)clearTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空播放列表"
        message:@"确定清空当前播放列表？" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) {
        [[NEPlayer shared] clearQueue];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 表

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    NEPlayer *p = [NEPlayer shared];
    return (NSInteger)(self.mode == 0 ? p.queue.count : p.history.count);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"queue";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.backgroundColor = UIColor.clearColor;
        cell.textLabel.textColor = NE_TEXT;
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.detailTextLabel.textColor = NE_TEXT_DIM;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UIButton *remove = [UIButton buttonWithType:UIButtonTypeSystem];
        [remove setTitle:@"✕" forState:UIControlStateNormal];
        [remove setTitleColor:NE_TEXT_DIM forState:UIControlStateNormal];
        remove.frame = CGRectMake(0, 0, 40, 40);
        cell.accessoryView = remove;
    }

    NEPlayer *p = [NEPlayer shared];
    BOOL historyMode = (self.mode == 1);
    NSArray<NESong *> *list = historyMode ? p.history : p.queue;
    if (ip.row >= (NSInteger)list.count) return cell;
    NESong *song = list[(NSUInteger)ip.row];
    BOOL current = !historyMode && (ip.row == p.currentIndex);
    cell.textLabel.text = [NSString stringWithFormat:@"%@%@%@",
                           current ? @"▶ " : @"",
                           song.vipOnly ? @"VIP  " : @"",
                           song.name ?: @""];
    cell.textLabel.textColor = current ? NE_BRAND : NE_TEXT;
    cell.detailTextLabel.text = song.artist ?: @"";
    cell.accessoryView.hidden = historyMode;
    if (!historyMode) {
        UIButton *removeBtn = (UIButton *)cell.accessoryView;
        removeBtn.tag = ip.row;
        [removeBtn removeTarget:self action:@selector(removeTapped:) forControlEvents:UIControlEventTouchUpInside];
        [removeBtn addTarget:self action:@selector(removeTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NEPlayer *p = [NEPlayer shared];
    if (self.mode == 0) {
        [p playAtIndex:ip.row];
    } else {
        if (ip.row >= (NSInteger)p.history.count) return;
        [p playQueue:@[p.history[(NSUInteger)ip.row]] atIndex:0];
    }
    [self reloadQueue];
}

- (void)removeTapped:(UIButton *)sender {
    [[NEPlayer shared] removeSongAtIndex:sender.tag];
    [self reloadQueue];
}

@end
