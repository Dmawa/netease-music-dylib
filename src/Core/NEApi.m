#import "NEApi.h"

@implementation NESong
- (NSString *)description {
    return [NSString stringWithFormat:@"<NESong %@ %@ - %@>", self.songID, self.name, self.artist];
}
@end

@implementation NEPlaylist
@end

@implementation NEApi

+ (instancetype)shared {
    static NEApi *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NEApi new]; });
    return s;
}

- (BOOL)isLoggedIn { return [NESession shared].isLoggedIn; }

- (void)logout { [[NESession shared] clearCookies]; }

#pragma mark - 数据映射

/// 搜索/详情返回的艺术家是数组；榜单是 ar 字段
static NSString *NEArtistsString(NSArray *artists) {
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *a in artists) {
        if ([a isKindOfClass:[NSDictionary class]] && a[@"name"]) [names addObject:a[@"name"]];
    }
    return [names componentsJoinedByString:@"/"];
}

static NESong *NESongFromJSON(NSDictionary *d) {
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    NESong *s = [NESong new];
    id sid = d[@"id"];
    s.songID = sid ? [sid description] : @"";
    s.name   = d[@"name"] ?: @"";
    s.album  = d[@"album"][@"name"] ?: d[@"al"][@"name"] ?: @"";

    NSArray *artists = d[@"artists"] ?: d[@"ar"];
    if ([artists isKindOfClass:[NSArray class]]) s.artist = NEArtistsString(artists);
    if (!s.artist.length) s.artist = @"未知艺术家";

    s.coverURL = d[@"album"][@"picUrl"] ?: d[@"al"][@"picUrl"] ?: @"";

    NSNumber *dur = d[@"duration"] ?: d[@"dt"];
    if ([dur isKindOfClass:[NSNumber class]]) s.durationMs = dur.integerValue;

    // fee: 1=VIP 3=付费专辑 4=低价 8=非会员可试听
    NSNumber *fee = d[@"fee"];
    if ([fee isKindOfClass:[NSNumber class]]) {
        s.vipOnly = (fee.integerValue == 1 || fee.integerValue == 3);
    }
    return s.songID.length ? s : nil;
}

static NSArray<NESong *> *NESongsFromArray(NSArray *arr) {
    NSMutableArray *out = [NSMutableArray array];
    for (id item in arr) {
        NESong *s = NESongFromJSON(item);
        if (s) [out addObject:s];
    }
    return out;
}

#pragma mark - 登录

- (void)requestQRKey:(NEQRCodeBlock)complete {
    [[NESession shared] POST:@"/api/login/qrcode/unikey?type=1" params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSString *key = json[@"unikey"];
        if ([key isKindOfClass:[NSString class]] && key.length) complete(key, nil);
        else complete(nil, [NSError errorWithDomain:@"NEMusic" code:-10
                                           userInfo:@{NSLocalizedDescriptionKey: @"服务端未返回登录 key"}]);
    }];
}

- (void)pollQRCode:(NSString *)unikey complete:(NEPollBlock)complete {
    NSString *path = [NSString stringWithFormat:@"/api/login/qrcode/client/login?key=%@&type=1", unikey];
    [[NESession shared] POST:path params:nil complete:^(id json, NSError *error) {
        if (error) { complete(-1, nil, error); return; }
        NSInteger code = [json[@"code"] integerValue];
        NSString *nick = nil;
        if (code == 803) {
            // 成功后会下发 MUSIC_U；昵称随后异步取
            nick = json[@"nickname"];
        }
        complete(code, nick, nil);
    }];
}

- (void)fetchAccount:(void (^)(NSString *, NSString *, NSError *))complete {
    [[NESession shared] GET:@"/api/nuser/account/get" params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, nil, error); return; }
        NSDictionary *profile = json[@"profile"];
        if (![profile isKindOfClass:[NSDictionary class]]) { complete(nil, nil, nil); return; }
        complete(profile[@"nickname"] ?: @"", profile[@"avatarUrl"] ?: @"", nil);
    }];
}

#pragma mark - 内容

- (void)searchSongs:(NSString *)keyword limit:(NSInteger)limit complete:(NESongsBlock)complete {
    if (!keyword.length) {
        // 空关键词 → 用热歌榜当发现页
        [self fetchToplist:complete];
        return;
    }
    NSDictionary *params = @{@"s": keyword,
                             @"type": @1,
                             @"limit": @(limit > 0 ? limit : 30),
                             @"offset": @0};
    [[NESession shared] POST:@"/api/search/get" params:params complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSArray *songs = json[@"result"][@"songs"];
        complete([NSArray arrayWithArray:NESongsFromArray([songs isKindOfClass:[NSArray class]] ? songs : @[])], nil);
    }];
}

- (void)fetchToplist:(NESongsBlock)complete {
    // 3778678 = 热歌榜；detail 里带完整 tracks
    [self fetchPlaylistSongs:@"3778678" complete:complete];
}

- (void)fetchPlaylistDetail:(NSString *)playlistID complete:(NESongsBlock)complete {
    [self fetchPlaylistSongs:playlistID complete:complete];
}

- (void)fetchPlaylistSongs:(NSString *)playlistID complete:(NESongsBlock)complete {
    NSString *path = [NSString stringWithFormat:@"/api/v6/playlist/detail?id=%@", playlistID];
    [[NESession shared] GET:path params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSDictionary *pl = json[@"playlist"];
        NSArray *tracks = pl[@"tracks"];
        if (![tracks isKindOfClass:[NSArray class]]) {
            complete(@[], nil);
            return;
        }
        complete([NSArray arrayWithArray:NESongsFromArray(tracks)], nil);
    }];
}

- (void)fetchMyPlaylists:(void (^)(NSArray<NEPlaylist *> *, NSError *))complete {
    [[NESession shared] GET:@"/api/nuser/account/get" params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSNumber *uid = json[@"profile"][@"userId"];
        if (![uid isKindOfClass:[NSNumber class]]) {
            complete(@[], nil);
            return;
        }
        NSString *path = [NSString stringWithFormat:@"/api/user/playlist?uid=%@&limit=50&offset=0", uid];
        [[NESession shared] GET:path params:nil complete:^(id json2, NSError *error2) {
            if (error2) { complete(nil, error2); return; }
            NSMutableArray *out = [NSMutableArray array];
            for (NSDictionary *d in json2[@"playlist"]) {
                if (![d isKindOfClass:[NSDictionary class]]) continue;
                NEPlaylist *p = [NEPlaylist new];
                p.playlistID = [d[@"id"] description] ?: @"";
                p.name = d[@"name"] ?: @"";
                p.coverURL = d[@"coverImgUrl"] ?: @"";
                p.trackCount = [d[@"trackCount"] integerValue];
                if (p.playlistID.length) [out addObject:p];
            }
            complete(out, nil);
        }];
    }];
}

#pragma mark - 播放

- (void)resolveStreamURLForSong:(NESong *)song
                       complete:(void (^)(NSString *, NSError *))complete {
    if (!song.songID.length) {
        complete(nil, [NSError errorWithDomain:@"NEMusic" code:-20
                                     userInfo:@{NSLocalizedDescriptionKey: @"歌曲 ID 为空"}]);
        return;
    }
    NSString *ids = [NSString stringWithFormat:@"[%@]", song.songID];
    NSString *path = [NSString stringWithFormat:
        @"/api/song/enhance/player/url/v1?ids=%@&level=exhigh&encodeType=mp3", ids];
    // 括号不能进 query，必须编码
    path = [path stringByReplacingOccurrencesOfString:@"[" withString:@"%5B"];
    path = [path stringByReplacingOccurrencesOfString:@"]" withString:@"%5D"];

    [[NESession shared] POST:path params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSDictionary *first = [json[@"data"] isKindOfClass:[NSArray class]] ? json[@"data"][0] : nil;
        NSString *url = first[@"url"];
        if ([url isKindOfClass:[NSString class]] && url.length) {
            song.streamURL = url;
            complete(url, nil);
            return;
        }
        // url 为 null：版权受限或需要登录
        NSString *msg = [NEApi shared].isLoggedIn ? @"该歌曲无版权或需要会员" : @"请先登录以获取播放地址";
        complete(nil, [NSError errorWithDomain:@"NEMusic" code:-21
                                     userInfo:@{NSLocalizedDescriptionKey: msg}]);
    }];
}

- (void)fetchLyricForSong:(NESong *)song complete:(NELyricBlock)complete {
    NSString *path = [NSString stringWithFormat:@"/api/song/lyric?id=%@&lv=-1&tv=-1", song.songID];
    [[NESession shared] GET:path params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSString *lrc = json[@"lrc"][@"lyric"];
        if (![lrc isKindOfClass:[NSString class]]) { complete(@[], nil); return; }

        NSMutableArray *lines = [NSMutableArray array];
        for (NSString *raw in [lrc componentsSeparatedByString:@"\n"]) {
            // 形如 [00:12.570]难以忘记初次见你
            if (![raw hasPrefix:@"["]) continue;
            NSRange close = [raw rangeOfString:@"]"];
            if (close.location == NSNotFound) continue;
            NSString *stamp = [raw substringWithRange:NSMakeRange(1, close.location - 1)];
            NSString *text  = [raw substringFromIndex:close.location + 1];
            NSArray *parts = [stamp componentsSeparatedByString:@":"];
            if (parts.count < 2) continue;
            double sec = ((NSString *)parts[0]).doubleValue * 60.0
                       + ((NSString *)parts[1]).doubleValue;
            if (!text.length) continue;
            [lines addObject:@{@"t": @(sec), @"text": text}];
        }
        complete(lines, nil);
    }];
}

@end