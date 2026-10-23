#import "NEPlaylistSheet.h"
#import "NEUITheme.h"
#import "NEPlayer.h"

@interface NEPlaylistSheet () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation NEPlaylistSheet

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = NE_PANEL;

    CGFloat W = self.view.bounds.size.width;

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, 18, W - 140, 26)];
    _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _titleLabel.textColor = NE_TEXT;
    [self.view addSubview:_titleLabel];

    UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:@"清空" forState:UIControlStateNormal];
    clear.frame = CGRectMake(W - 120, 18, 44, 26);
    [clear addTarget:self action:@selector(clearTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:clear];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    close.frame = CGRectMake(W - 72, 18, 60, 26);
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    _table = [[UITableView alloc] initWithFrame:CGRectMake(0, 56, W, self.view.bounds.size.height - 56)
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

- (void)reloadQueue {
    NEPlayer *p = [NEPlayer shared];
    self.titleLabel.text = [NSString stringWithFormat:@"当前播放 %lu", (unsigned long)p.queue.count];
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
    return (NSInteger)[NEPlayer shared].queue.count;
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
    if (ip.row >= (NSInteger)p.queue.count) return cell;
    NESong *song = p.queue[(NSUInteger)ip.row];
    BOOL current = (ip.row == p.currentIndex);
    cell.textLabel.text = [NSString stringWithFormat:@"%@%@%@",
                           current ? @"▶ " : @"",
                           song.vipOnly ? @"VIP  " : @"",
                           song.name ?: @""];
    cell.textLabel.textColor = current ? NE_BRAND : NE_TEXT;
    cell.detailTextLabel.text = song.artist ?: @"";
    UIButton *removeBtn = (UIButton *)cell.accessoryView;
    removeBtn.tag = ip.row;
    [removeBtn removeTarget:self action:@selector(removeTapped:) forControlEvents:UIControlEventTouchUpInside];
    [removeBtn addTarget:self action:@selector(removeTapped:) forControlEvents:UIControlEventTouchUpInside];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [[NEPlayer shared] playAtIndex:ip.row];
    [self reloadQueue];
}

- (void)removeTapped:(UIButton *)sender {
    [[NEPlayer shared] removeSongAtIndex:sender.tag];
    [self reloadQueue];
}

@end
