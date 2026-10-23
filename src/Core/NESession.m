#import "NESession.h"
#import "NECrypto.h"

/// 用桌面浏览器 UA：官方 QR 登录是 web 客户端的流程，
/// 移动端 UA 会被当成旧版客户端（扫码后回 8821）
static NSString *const kNEUserAgent =
    @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    @"AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

/// 登录态相关的关键 Cookie
static NSString *const kCookieMusicU = @"MUSIC_U";
static NSString *const kCookieCsrf   = @"__csrf";

@interface NESession ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *jar;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *rawSetCookieLines;
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
        _lock = [NSLock new];

        // 注意：必须保留 HTTPCookieStorage 并允许接收 Cookie。
        // 之前把它设为 nil / HTTPShouldSetCookies=NO，
        // 导致 NSURLSession 根本不把 Set-Cookie 写进 allHeaderFields，
        // 登录成功后 MUSIC_U 永远拿不到 —— 这是登录失效的根因。
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        cfg.HTTPShouldSetCookies = YES;
        cfg.timeoutIntervalForRequest = 20;
        cfg.timeoutIntervalForResource = 40;
        cfg.HTTPAdditionalHeaders = @{@"User-Agent": kNEUserAgent};
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        cfg.URLCache = nil;
        _session = [NSURLSession sessionWithConfiguration:cfg
                                 delegate:nil
                            delegateQueue:nil];
        [self loadFromDisk];
    }
    return self;
}

#pragma mark - 持久化

- (NSString *)storeDir {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    dir = [dir stringByAppendingPathComponent:@"NEMusic"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                             withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSString *)cookiePath {
    return [[self storeDir] stringByAppendingPathComponent:@"cookies.plist"];
}

- (void)loadFromDisk {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[self cookiePath]];
    if ([d isKindOfClass:[NSDictionary class]] && d.count) {
        [self.lock lock];
        [self.jar addEntriesFromDictionary:d];
        [self.lock unlock];
    }
}

- (void)persist {
    NSDictionary *snap;
    [self.lock lock];
    snap = [self.jar copy];
    [self.lock unlock];
    if (snap.count) {
        [snap writeToFile:[self cookiePath] atomically:YES];
    } else {
        [[NSFileManager defaultManager] removeItemAtPath:[self cookiePath] error:nil];
    }
}

#pragma mark - Cookie

- (NSString *)cookieHeader {
    [self.lock lock];
    NSMutableArray *pairs = [NSMutableArray array];
    // 把 MUSIC_U / __csrf 放前面，避免被长 Cookie 串截断
    NSArray *priority = @[kCookieMusicU, kCookieCsrf];
    for (NSString *k in priority) {
        if (self.jar[k].length) [pairs addObject:[NSString stringWithFormat:@"%@=%@", k, self.jar[k]]];
    }
    for (NSString *k in self.jar) {
        if ([priority containsObject:k]) continue;
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", k, self.jar[k]]];
    }
    [self.lock unlock];
    return [pairs componentsJoinedByString:@"; "];
}

/// 从系统 Cookie 存储里找（NSURLSession 会把 Set-Cookie 写进去）
- (NSString *)systemCookieValue:(NSString *)name {
    NSArray<NSHTTPCookie *> *cookies =
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies];
    for (NSHTTPCookie *c in cookies) {
        if ([c.name isEqualToString:name] &&
            [c.domain containsString:@"music.163.com"] && c.value.length) {
            return c.value;
        }
    }
    return nil;
}

- (BOOL)isLoggedIn {
    [self.lock lock];
    BOOL ok = self.jar[kCookieMusicU].length > 0;
    [self.lock unlock];
    if (ok) return YES;
    // 兜底：系统 Cookie 存储里可能已经有了（首次登录那一次）
    NSString *v = [self systemCookieValue:kCookieMusicU];
    if (v.length) {
        [self setCookie:kCookieMusicU value:v];
        [self persist];
        return YES;
    }
    return NO;
}

- (NSString *)valueForCookie:(NSString *)name {
    [self.lock lock];
    NSString *v = self.jar[name];
    [self.lock unlock];
    if (v.length) return v;
    NSString *sys = [self systemCookieValue:name];
    if (sys.length) {
        [self setCookie:name value:sys];
        [self persist];
    }
    return sys;
}

/*
 *  原来用 allHeaderFields 里找 "set-cookie" 是不可靠的：
 *  HTTP/2 下多个 Set-Cookie 会被合并成一个字符串，
 *  且键名大小写、数组/字符串类型都不稳定。
 *  这里改用 NSHTTPCookie 的解析规则手工处理每一段。
 */
- (void)absorbResponseCookies:(NSURLResponse *)response {
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    if (![http isKindOfClass:[NSHTTPURLResponse class]]) return;

    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    // 方式 1：标准字段（可能被合并）
    for (id key in http.allHeaderFields) {
        NSString *k = [key isKindOfClass:[NSString class]] ? key : [key description];
        if ([k caseInsensitiveCompare:@"Set-Cookie"] != NSOrderedSame) continue;
        id v = http.allHeaderFields[key];
        if ([v isKindOfClass:[NSArray class]]) {
            [lines addObjectsFromArray:v];
        } else if ([v isKindOfClass:[NSString class]]) {
            [lines addObject:v];
        }
    }

    // 方式 2：NSHTTPCookie 解析（更稳，能正确处理合并后的串）
    NSArray<NSHTTPCookie *> *parsed =
        [NSHTTPCookie cookiesWithResponseHeaderFields:http.allHeaderFields
                                               forURL:http.URL];
    for (NSHTTPCookie *c in parsed) {
        if (c.name.length && c.value.length) {
            [self setCookie:c.name value:c.value];
        }
    }

    BOOL changed = NO;
    for (NSString *raw in lines) {
        // 一段里可能塞了多个 cookie（用 ", " 连接），尽量拆开
        for (NSString *chunk in [self splitCookieHeader:raw]) {
            NSString *pair = [chunk componentsSeparatedByString:@";"].firstObject;
            NSRange eq = [pair rangeOfString:@"="];
            if (eq.location == NSNotFound || eq.location == 0) continue;
            NSString *name = [[pair substringToIndex:eq.location]
                              stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSString *value = [[pair substringFromIndex:eq.location + 1]
                               stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (name.length && value.length) {
                [self setCookie:name value:value];
                changed = YES;
            }
        }
    }
    self.rawSetCookieLines = [lines copy];
    if (changed) [self persist];
}

/// 把可能被合并的 Set-Cookie 拆开：只在 ", xxx=" 且后面紧跟知名 cookie 名时拆
- (NSArray<NSString *> *)splitCookieHeader:(NSString *)raw {
    if ([raw rangeOfString:@","].location == NSNotFound) return @[raw];

    NSMutableArray *out = [NSMutableArray array];
    NSArray *parts = [raw componentsSeparatedByString:@","];
    NSMutableString *cur = [NSMutableString string];
    for (NSString *p in parts) {
        NSString *t = [p stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        // 形如 "NMTID=xxx" / "MUSIC_U=yyy"：以 name= 开头则视为新 cookie
        NSRange eq = [t rangeOfString:@"="];
        BOOL looksLikeCookie = NO;
        if (eq.location != NSNotFound && eq.location > 0 && eq.location < 24) {
            NSString *name = [t substringToIndex:eq.location];
            if ([name rangeOfCharacterFromSet:
                 [NSCharacterSet characterSetWithCharactersInString:@" ;"]].location == NSNotFound) {
                looksLikeCookie = YES;
            }
        }
        if (looksLikeCookie && cur.length) {
            [out addObject:cur];
            cur = [NSMutableString stringWithString:t];
        } else if (looksLikeCookie) {
            cur = [NSMutableString stringWithString:t];
        } else {
            if (cur.length) [cur appendString:@", "];
            [cur appendString:t];
        }
    }
    if (cur.length) [out addObject:cur];
    return out;
}

- (void)setCookie:(NSString *)name value:(NSString *)value {
    [self.lock lock];
    self.jar[name] = value;
    [self.lock unlock];
}

- (void)setCookieValue:(NSString *)value forName:(NSString *)name {
    if (!name.length || !value.length) return;
    [self setCookie:name value:value];
    [self persist];
}

- (void)clearCookies {
    [self.lock lock];
    [self.jar removeAllObjects];
    [self.lock unlock];
    [[NSFileManager defaultManager] removeItemAtPath:[self cookiePath] error:nil];
}

#pragma mark - 请求

- (NSMutableURLRequest *)requestWithPath:(NSString *)path
                                  params:(NSDictionary *)params
                                  method:(NSString *)method {
    NSString *full = [path hasPrefix:@"http"] ? path
                    : [@"https://music.163.com" stringByAppendingString:path];

    NSMutableURLRequest *req;
    if ([method isEqualToString:@"GET"] && params.count) {
        NSURLComponents *comp = [NSURLComponents componentsWithString:full];
        NSMutableArray *items = [NSMutableArray array];
        [params enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            [items addObject:[NSURLQueryItem queryItemWithName:[k description]
                                                         value:[v description]]];
        }];
        comp.queryItems = items;
        req = [NSMutableURLRequest requestWithURL:comp.URL];
    } else {
        req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:full]];
    }

    req.HTTPMethod = method;
    req.timeoutInterval = 15;
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [req setValue:kNEUserAgent forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"https://music.163.com/" forHTTPHeaderField:@"Referer"];
    [req setValue:@"https://music.163.com" forHTTPHeaderField:@"Origin"];

    // 关键：确保 MUSIC_U 一定在请求头里。
    // 首次登录时它可能只落在系统 Cookie 存储中，需要通过 valueForCookie 同步过来。
    [self valueForCookie:kCookieMusicU];
    [self valueForCookie:kCookieCsrf];

    NSString *cookie = [self cookieHeader];
    if (cookie.length) [req setValue:cookie forHTTPHeaderField:@"Cookie"];

    if ([method isEqualToString:@"POST"]) {
        NSMutableArray *pairs = [NSMutableArray array];
        [params enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            NSString *s = [NSString stringWithFormat:@"%@", v];
            NSString *esc = [s stringByAddingPercentEncodingWithAllowedCharacters:
                             [NSCharacterSet URLQueryAllowedCharacterSet]];
            // URLQueryAllowed 会放过 & 和 =，必须再转义
            esc = [esc stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
            esc = [esc stringByReplacingOccurrencesOfString:@"=" withString:@"%3D"];
            esc = [esc stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
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

        if (err) {
            dispatch_async(dispatch_get_main_queue(), ^{ complete(nil, err); });
            return;
        }
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
                complete(nil, jsonErr ?: [NSError errorWithDomain:@"NEMusic" code:-2
                                                        userInfo:@{NSLocalizedDescriptionKey: @"返回非 JSON"}]);
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

#pragma mark - weapi

- (void)POSTWeapi:(NSString *)path params:(NSDictionary *)params complete:(NECompletion)complete {
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    if (params) [data addEntriesFromDictionary:params];
    // 官方前端加密前会补 csrf_token（未登录时为空串）
    data[@"csrf_token"] = [self valueForCookie:kCookieCsrf] ?: @"";

    NSString *body = [NECrypto weapiBodyWithData:data];
    if (!body.length) {
        NSError *e = [NSError errorWithDomain:@"NEMusic" code:-3
                                    userInfo:@{NSLocalizedDescriptionKey: @"请求加密失败"}];
        dispatch_async(dispatch_get_main_queue(), ^{ complete(nil, e); });
        return;
    }

    NSString *full = [path hasPrefix:@"http"] ? path
                    : [@"https://music.163.com" stringByAppendingString:path];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:full]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 20;
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [req setValue:kNEUserAgent forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"https://music.163.com/" forHTTPHeaderField:@"Referer"];
    [req setValue:@"https://music.163.com" forHTTPHeaderField:@"Origin"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    [self valueForCookie:kCookieMusicU];
    [self valueForCookie:kCookieCsrf];
    NSString *cookie = [self cookieHeader];
    if (cookie.length) [req setValue:cookie forHTTPHeaderField:@"Cookie"];

    req.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    [self perform:req complete:complete];
}

- (void)POST:(NSString *)path params:(NSDictionary *)params complete:(NECompletion)complete {
    [self perform:[self requestWithPath:path params:params method:@"POST"] complete:complete];
}

@end