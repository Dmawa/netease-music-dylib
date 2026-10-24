#import "NEFeedPage.h"
#import "NEUITheme.h"
#import "NEImageCache.h"

@interface NEFeedPage () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *feedTitle;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) NSDictionary *params;
@property (nonatomic, strong) NSArray<NSString *> *arrayKeys;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy, nullable) NEFeedLoader loader;
@end

@implementation NEFeedPage

- (instancetype)initWithTitle:(NSString *)title
                         path:(NSString *)path
                       params:(NSDictionary *)params
                    arrayKeys:(NSArray<NSString *> *)arrayKeys {
    if ((self = [super initWithFrame:CGRectZero])) {
        _feedTitle = [title copy];
        _path = [path copy];
        _params = [params copy];
        _arrayKeys = arrayKeys.count ? arrayKeys : @[@"data.blocks", @"data.list", @"data", @"list", @"result"];
        self.backgroundColor = UIColor.clearColor;
        [self build];
    }
    return self;
}

- (instancetype)initWithTitle:(NSString *)title loader:(NEFeedLoader)loader {
    if ((self = [super initWithFrame:CGRectZero])) {
        _feedTitle = [title copy];
        _loader = [loader copy];
        _arrayKeys = @[@"data"];
        self.backgroundColor = UIColor.clearColor;
        [self build];
    }
    return self;
}

- (void)build {
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor = UIColor.clearColor;
    _table.separatorColor = NE_STROKE;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = 62;
    _table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [self addSubview:_table];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _table.frame = self.bounds;
}

- (void)reload {
    self.status = @"加载中…";
    [self.table reloadData];

    __weak typeof(self) weakSelf = self;
    if (self.loader) {
        self.loader(^(NSArray *items, NSError *error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self applyRawItems:items error:error message:nil];
        });
        return;
    }

    [[NESession shared] GET:self.path params:self.params complete:^(id json, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSArray *arr = error ? @[] : [self findArrayIn:json];
        NSString *message = [json isKindOfClass:[NSDictionary class]] &&
                            [json[@"message"] isKindOfClass:[NSString class]] ? json[@"message"] : nil;
        [self applyRawItems:arr error:error message:message];
    }];
}

- (void)applyRawItems:(NSArray *)arr error:(NSError *)error message:(NSString *)message {
    if (error) {
        self.status = error.localizedDescription;
        self.items = @[];
        [self.table reloadData];
        return;
    }
    NSMutableArray *rows = [NSMutableArray array];
    for (id obj in arr) {
        if ([obj isKindOfClass:[NSDictionary class]]) [rows addObject:obj];
    }
    self.items = rows;
    self.status = rows.count ? nil : (message.length ? message : @"没有内容");
    [self.table reloadData];
}

- (NSArray *)findArrayIn:(id)json {
    for (NSString *keyPath in self.arrayKeys) {
        id cur = json;
        BOOL ok = YES;
        for (NSString *key in [keyPath componentsSeparatedByString:@"."]) {
            if (![cur isKindOfClass:[NSDictionary class]] || !cur[key]) { ok = NO; break; }
            cur = cur[key];
        }
        if (ok && [cur isKindOfClass:[NSArray class]]) return cur;
    }
    return @[];
}

#pragma mark - 表

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return MAX((NSInteger)self.items.count, 1);
}

- (NSString *)textForKeys:(NSDictionary *)d keys:(NSArray *)keys {
    for (NSString *k in keys) {
        id v = d[k];
        if ([v isKindOfClass:[NSString class]] && [v length]) return v;
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"feed";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.backgroundColor = UIColor.clearColor;
        cell.textLabel.textColor = NE_TEXT;
        cell.detailTextLabel.textColor = NE_TEXT_DIM;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    if (!self.items.count) {
        cell.textLabel.text = self.status ?: @"暂无内容";
        cell.detailTextLabel.text = @"";
        cell.imageView.image = nil;
        return cell;
    }

    NSDictionary *d = self.items[(NSUInteger)ip.row];
    NSString *title = [self textForKeys:d keys:@[@"title", @"name", @"programName", @"voiceName", @"nickname"]] ?: @"";
    NSString *sub = [self textForKeys:d keys:@[@"subTitle", @"subtitle", @"desc", @"description", @"artistName", @"artist"]] ?: @"";
    NSString *cover = [self textForKeys:d keys:@[@"coverUrl", @"coverURL", @"cover", @"picUrl", @"avatarUrl", @"iconUrl"]];

    cell.textLabel.text = title;
    cell.detailTextLabel.text = sub;
    cell.imageView.image = nil;
    if (cover.length) {
        __weak typeof(cell) weakCell = cell;
        [[NEImageCache shared] loadImageWithURL:cover completion:^(UIImage *img) {
            if (img) weakCell.imageView.image = img;
        }];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.row >= (NSInteger)self.items.count) return;
    if (self.onTapItem) self.onTapItem(self.items[(NSUInteger)ip.row]);
}

@end
