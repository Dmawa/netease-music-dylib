#import "NESession.h"

static NSString *const kNEUserAgent =
    @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    @"AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148";

@interface NESession ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *jar;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation NESession

+ (instancetype)shared {
    static NESession *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NESession new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _jar = [NSMutableDictionary dictionary];
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.HTTPCookieStorage = nil;          // 自己管，避免跟系统 Cookie 打架
        cfg.HTTPShouldSetCookies = NO;
        cfg.timeoutIntervalForRequest = 15;
        cfg.timeoutIntervalForResource = 30;
        cfg.HTTPAdditionalHeaders = @{@"User-Agent": kNEUserAgent};
        _session = [NSURLSession sessionWithConfiguration:cfg];
        [self loadFromDisk];
    }
    return self;
}

#pragma mark - 持久化

- (NSURL *)storeURL {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    dir = [dir stringByAppendingPathComponent:@"NEMusic"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                             withIntermediateDirectories:YES attributes:nil error:nil];
    return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"cookies.plist"]];
}

- (void)loadFromDisk {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfURL:[self storeURL]];
    if (d.count) [_jar addEntriesFromDictionary:d];
}

- (void)persist {
    [_jar writeToURL:[self storeURL] atomically:YES];
}

#pragma mark - Cookie

- (NSString *)cookieHeader {
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *k in self.jar) [pairs addObject:[NSString stringWithFormat:@"%@=%@", k, self.jar[k]]];
    return [pairs componentsJoinedByString:@"; "];
}

- (BOOL)isLoggedIn {
    return self.jar[@"MUSIC_U"].length > 0;
}

/// 手工解析 Set-Cookie，避免依赖被关闭的 HTTPCookieStorage
- (void)absorbResponseCookies:(NSURLResponse *)response {
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    if (![http isKindOfClass:[NSHTTPURLResponse class]]) return;

    NSDictionary *fields = http.allHeaderFields;
    for (id key in fields) {
        if (![[key description].lowercaseString isEqualToString:@"set-cookie"]) continue;
        id value = fields[key];
        NSArray *list = [value isKindOfClass:[NSArray class]] ? value : @[value];
        for (NSString *line in list) {
            NSString *pair = [line componentsSeparatedByString:@";"].firstObject;
            NSRange eq = [pair rangeOfString:@"="];
            if (eq.location == NSNotFound) continue;
            NSString *name  = [pair substringToIndex:eq.location];
            NSString *val   = [pair substringFromIndex:eq.location + 1];
            name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (name.length && val.length) self.jar[name] = val;
        }
    }
    [self persist];
}

- (void)clearCookies {
    [self.jar removeAllObjects];
    [self persist];
}

#pragma mark - 请求

- (NSMutableURLRequest *)requestWithPath:(NSString *)path
                                  params:(NSDictionary *)params
                                  method:(NSString *)method {
    NSString *full = [path hasPrefix:@"http"] ? path : [@"https://music.163.com" stringByAppendingString:path];
    NSURLComponents *comp = [NSURLComponents componentsWithString:full];
    NSMutableArray *items = [NSMutableArray array];

    if ([method isEqualToString:@"GET"] && params.count) {
        [params enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            [items addObject:[NSURLQueryItem queryItemWithName:[k description]
                                                          value:[v description]]];
        }];
        comp.queryItems = items;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:comp.URL];
    req.HTTPMethod = method;
    req.timeoutInterval = 15;
    [req setValue:kNEUserAgent forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"https://music.163.com/" forHTTPHeaderField:@"Referer"];
    [req setValue:@"https://music.163.com" forHTTPHeaderField:@"Origin"];
    if (self.cookieHeader.length) [req setValue:self.cookieHeader forHTTPHeaderField:@"Cookie"];

    if ([method isEqualToString:@"POST"]) {
        NSMutableArray *pairs = [NSMutableArray array];
        [params enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            NSString *esc = [NSString stringWithFormat:@"%@", v];
            // 简易 percent-escape，避免 + & = 破坏表单
            esc = [esc stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
            [pairs addObject:[NSString stringWithFormat:@"%@=%@", k, esc ?: @""]];
        }];
        [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        req.HTTPBody = [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
    }
    return req;
}

- (void)perform:(NSMutableURLRequest *)req complete:(NECompletion)complete {
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req
                                               completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (resp) [self absorbResponseCookies:resp];
        if (err) { dispatch_async(dispatch_get_main_queue(), ^{ complete(nil, err); }); return; }
        if (!data.length) {
            NSError *e = [NSError errorWithDomain:@"NEMusic" code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"服务端返回空数据"}];
            dispatch_async(dispatch_get_main_queue(), ^{ complete(nil, e); });
            return;
        }
        NSError *jsonErr = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!json) {
                NSError *e = jsonErr ?: [NSError errorWithDomain:@"NEMusic" code:-2
                                                       userInfo:@{NSLocalizedDescriptionKey: @"返回内容不是合法 JSON"}];
                complete(nil, e);
            } else {
                complete(json, nil);
            }
        });
    }];
    [task resume];
}

- (void)GET:(NSString *)path params:(NSDictionary *)params complete:(NECompletion)complete {
    [self perform:[self requestWithPath:path params:params method:@"GET"] complete:complete];
}

- (void)POST:(NSString *)path params:(NSDictionary *)params complete:(NECompletion)complete {
    [self perform:[self requestWithPath:path params:params method:@"POST"] complete:complete];
}

@end