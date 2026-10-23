#import "NEImageCache.h"

@interface NEImageCache ()
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *memory;
@property (nonatomic, strong) NSURLSession *session;
/// URL -> 等待回调数组，避免同一张图重复下载
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray< void (^)(UIImage *) > *> *pending;
@property (nonatomic, strong) dispatch_queue_t lock;
@end

@implementation NEImageCache

+ (instancetype)shared {
    static NEImageCache *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NEImageCache new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _memory = [NSCache new];
        _memory.countLimit = 60;
        _pending = [NSMutableDictionary dictionary];
        _lock = dispatch_queue_create("com.dmawa.nemusic.imagecache", DISPATCH_QUEUE_SERIAL);

        NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
        c.timeoutIntervalForRequest = 15;
        c.HTTPMaximumConnectionsPerHost = 4;
        c.requestCachePolicy = NSURLRequestReturnCacheDataElseLoad;
        _session = [NSURLSession sessionWithConfiguration:c];
    }
    return self;
}

#pragma mark - 磁盘

- (NSString *)diskPathForKey:(NSString *)key {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    dir = [dir stringByAppendingPathComponent:@"NEMusicCovers"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                             withIntermediateDirectories:YES attributes:nil error:nil];
    // 用 key 的哈希做文件名，避免 URL 里的特殊字符
    NSUInteger h = key.hash;
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%lx.jpg", (unsigned long)h]];
}

#pragma mark - 对外

- (UIImage *)imageForKey:(NSString *)key {
    if (!key.length) return nil;
    UIImage *img = [self.memory objectForKey:key];
    if (img) return img;
    NSData *d = [NSData dataWithContentsOfFile:[self diskPathForKey:key]];
    if (d.length) {
        UIImage *disk = [UIImage imageWithData:d];
        if (disk) { [self.memory setObject:disk forKey:key]; return disk; }
    }
    return nil;
}

- (void)loadImageWithURL:(NSString *)url completion:(void (^)(UIImage *))completion {
    if (!url.length || !completion) return;

    UIImage *cached = [self imageForKey:url];
    if (cached) { completion(cached); return; }

    __block BOOL shouldStart = NO;
    dispatch_sync(self.lock, ^{
        NSMutableArray *waiters = self.pending[url];
        if (waiters) {
            [waiters addObject:[completion copy]];
        } else {
            self.pending[url] = [NSMutableArray arrayWithObject:[completion copy]];
            shouldStart = YES;
        }
    });
    if (!shouldStart) return;

    NSURL *u = [NSURL URLWithString:url];
    if (!u) { [self finishURL:url image:nil]; return; }

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:u
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        UIImage *img = nil;
        if (data.length && !err) {
            img = [UIImage imageWithData:data];
            if (img) {
                [self.memory setObject:img forKey:url];
                [data writeToFile:[self diskPathForKey:url] atomically:YES];
            }
        }
        [self finishURL:url image:img];
    }];
    [task resume];
}

- (void)finishURL:(NSString *)url image:(UIImage *)image {
    __block NSArray *waiters = nil;
    dispatch_sync(self.lock, ^{
        waiters = [self.pending[url] copy];
        [self.pending removeObjectForKey:url];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        for (void (^cb)(UIImage *) in waiters) cb(image);
    });
}

@end