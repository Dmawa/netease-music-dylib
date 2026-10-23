#import "NEApi.h"

@implementation NESong
- (NSString *)description {
    return [NSString stringWithFormat:@"<NESong %@ %@ - %@>", self.songID, self.name, self.artist];
}
@end

@implementation NEPlaylist
@end

@implementation NERecommendItem
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

    // 不同接口给的字段不一样：
    //   cloudsearch/pc -> al.picUrl
    //   playlist/detail & song/detail -> album.picUrl
    //   search/get -> 只有 album.picId（缺加密串，拼不出来，只能留空）
    NSString *cover = d[@"al"][@"picUrl"];
    if (![cover isKindOfClass:[NSString class]] || !cover.length)
        cover = d[@"album"][@"picUrl"];
    if (![cover isKindOfClass:[NSString class]] || !cover.length)
        cover = d[@"picUrl"];
    if (![cover isKindOfClass:[NSString class]]) cover = @"";
    // 网易云有时给 http，iOS ATS 默认拦截，统一升级到 https
    if ([cover hasPrefix:@"http://"]) {
        cover = [@"https://" stringByAppendingString:[cover substringFromIndex:7]];
    }
    s.coverURL = cover;

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

- (void)pollQRCodeDetail:(NSString *)unikey complete:(NEPollDetailBlock)complete {
    NSString *path = [NSString stringWithFormat:
        @"/api/login/qrcode/client/login?key=%@&type=1", unikey];
    [[NESession shared] POST:path params:nil complete:^(id json, NSError *error) {
        if (error) { complete(-1, nil, nil, error); return; }

        NSInteger code = -1;
        if ([json isKindOfClass:[NSDictionary class]]) {
            code = [json[@"code"] integerValue];
        }
        NSString *nick = [json isKindOfClass:[NSDictionary class]] ? json[@"nickname"] : nil;
        NSArray *raw = [NESession shared].rawSetCookieLines ?: @[];

        // 803 时服务端会下发 MUSIC_U。这里再兜底检查一次：
        // 万一系统 Cookie 存储没同步，直接从原始 Set-Cookie 行里补写进 jar。
        if (code == 803) {
            for (NSString *line in raw) {
                if (![line isKindOfClass:[NSString class]]) continue;
                NSString *pair = [line componentsSeparatedByString:@";"].firstObject;
                NSRange eq = [pair rangeOfString:@"="];
                if (eq.location == NSNotFound || eq.location == 0) continue;
                NSString *name = [[pair substringToIndex:eq.location]
                                  stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                NSString *value = [[pair substringFromIndex:eq.location + 1]
                                   stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                if ([name isEqualToString:@"MUSIC_U"] && value.length) {
                    [[NESession shared] setCookieValue:value forName:@"MUSIC_U"];
                }
                if ([name isEqualToString:@"__csrf"] && value.length) {
                    [[NESession shared] setCookieValue:value forName:@"__csrf"];
                }
            }
        }
        complete(code, nick, raw, nil);
    }];
}

- (void)restoreSession:(void (^)(BOOL, NSString *, NSString *))complete {
    // 没有本地 Cookie：直接判定未登录
    if (![NESession shared].isLoggedIn) {
        complete(NO, nil, nil);
        return;
    }
    // 有 MUSIC_U：向服务端确认一次（可能已过期/被踢下线）
    [[NESession shared] GET:@"/api/nuser/account/get" params:nil complete:^(id json, NSError *error) {
        if (error) {
            // 网络失败不代表登录失效，保留本地 Cookie 下次再试
            complete([NESession shared].isLoggedIn, nil, nil);
            return;
        }
        NSDictionary *profile = json[@"profile"];
        if (![profile isKindOfClass:[NSDictionary class]]) {
            // 服务端明确说没登录 → 清掉失效 Cookie，避免一直用坏凭证
            [[NESession shared] clearCookies];
            complete(NO, nil, nil);
            return;
        }
        complete(YES, profile[@"nickname"] ?: @"", profile[@"avatarUrl"] ?: @"");
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
    // 注意：/api/search/get 只返回 album.picId（没有 picUrl，无法拼出图片地址），
    //        /api/cloudsearch/pc 才返回 al.picUrl，封面可直接使用。
    NSDictionary *params = @{@"s": keyword,
                             @"type": @1,
                             @"limit": @(limit > 0 ? limit : 30),
                             @"offset": @0};
    [[NESession shared] POST:@"/api/cloudsearch/pc" params:params complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSArray *songs = json[@"result"][@"songs"];
        complete([NSArray arrayWithArray:NESongsFromArray(
            [songs isKindOfClass:[NSArray class]] ? songs : @[])], nil);
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
    [self fetchAccount:^(NSString *nickname, NSString *avatar, NSError *error) {}];
    [[NESession shared] GET:@"/api/nuser/account/get" params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSNumber *uid = json[@"profile"][@"userId"];
        if (![uid isKindOfClass:[NSNumber class]]) { complete(@[], nil); return; }

        NSString *path = [NSString stringWithFormat:
            @"/api/user/playlist?uid=%@&limit=200&offset=0", uid];
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
                p.specialType = [d[@"specialType"] integerValue];
                NSNumber *cid = d[@"creator"][@"userId"];
                p.creatorID = [cid isKindOfClass:[NSNumber class]] ? cid.integerValue : 0;
                if (p.playlistID.length) [out addObject:p];
            }
            complete(out, nil);
        }];
    }];
}

- (void)fetchLikedPlaylist:(void (^)(NEPlaylist *, NSError *))complete {
    [self fetchMyPlaylists:^(NSArray<NEPlaylist *> *list, NSError *error) {
        if (error) { complete(nil, error); return; }
        for (NEPlaylist *p in list) {
            if (p.specialType == 5) { complete(p, nil); return; }
        }
        complete(nil, nil);
    }];
}

- (void)fetchMyCollectedPlaylists:(void (^)(NSArray<NEPlaylist *> *, NSError *))complete {
    [self fetchMyPlaylists:^(NSArray<NEPlaylist *> *list, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSMutableArray *out = [NSMutableArray array];
        for (NEPlaylist *p in list) {
            // 只保留普通歌单（排除「喜欢的音乐」和年度歌单 specialType=20）
            if (p.specialType == 0) [out addObject:p];
        }
        complete(out, nil);
    }];
}

#pragma mark - 发现页

- (void)fetchRecommendPlaylists:(NSInteger)limit complete:(void (^)(NSArray<NERecommendItem *> *, NSError *))complete {
    NSString *path = [NSString stringWithFormat:@"/api/personalized/playlist?limit=%ld", (long)MAX(1, limit)];
    [[NESession shared] GET:path params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSArray *arr = json[@"result"];
        NSMutableArray *out = [NSMutableArray array];
        if ([arr isKindOfClass:[NSArray class]]) {
            for (NSDictionary *d in arr) {
                if (![d isKindOfClass:[NSDictionary class]]) continue;
                NERecommendItem *it = [NERecommendItem new];
                it.itemID = [d[@"id"] description] ?: @"";
                it.title = d[@"name"] ?: @"";
                it.coverURL = d[@"picUrl"] ?: @"";
                it.kind = 0;
                NSNumber *cnt = d[@"trackCount"];
                it.subtitle = [cnt isKindOfClass:[NSNumber class]]
                    ? [NSString stringWithFormat:@"%ld 首", (long)cnt.integerValue] : @"";
                if (it.itemID.length) [out addObject:it];
            }
        }
        complete(out, nil);
    }];
}

- (void)fetchRecommendNewSongs:(NSInteger)limit complete:(void (^)(NSArray<NERecommendItem *> *, NSError *))complete {
    NSString *path = [NSString stringWithFormat:@"/api/personalized/newsong?limit=%ld", (long)MAX(1, limit)];
    [[NESession shared] GET:path params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSArray *arr = json[@"result"];
        NSMutableArray *out = [NSMutableArray array];
        if ([arr isKindOfClass:[NSArray class]]) {
            for (NSDictionary *d in arr) {
                NSDictionary *song = d[@"song"];
                if (![song isKindOfClass:[NSDictionary class]]) song = d;
                if (![song isKindOfClass:[NSDictionary class]]) continue;
                NERecommendItem *it = [NERecommendItem new];
                it.itemID = [song[@"id"] description] ?: @"";
                it.title = song[@"name"] ?: @"";
                NSArray *ar = song[@"artists"];
                if (![ar isKindOfClass:[NSArray class]]) ar = song[@"ar"];
                it.subtitle = [ar isKindOfClass:[NSArray class]] ? NEArtistsString(ar) : @"";
                NSString *pic = song[@"picUrl"];
                if (![pic isKindOfClass:[NSString class]] || !pic.length)
                    pic = d[@"picUrl"];
                it.coverURL = pic ?: @"";
                it.kind = 1;
                if (it.itemID.length) [out addObject:it];
            }
        }
        complete(out, nil);
    }];
}

- (void)fetchToplists:(void (^)(NSArray<NERecommendItem *> *, NSError *))complete {
    [[NESession shared] GET:@"/api/toplist/detail" params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSArray *arr = json[@"list"];
        NSMutableArray *out = [NSMutableArray array];
        if ([arr isKindOfClass:[NSArray class]]) {
            for (NSDictionary *d in arr) {
                if (![d isKindOfClass:[NSDictionary class]]) continue;
                NERecommendItem *it = [NERecommendItem new];
                it.itemID = [d[@"id"] description] ?: @"";
                it.title = d[@"name"] ?: @"";
                it.coverURL = d[@"coverImgUrl"] ?: @"";
                it.subtitle = d[@"updateFrequency"] ?: @"";
                it.kind = 0;
                if (it.itemID.length) [out addObject:it];
            }
        }
        complete(out, nil);
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
    // 一次请求拿三种格式：lrc（整行）、tlyric（翻译）、yrc（逐字）
    NSString *path = [NSString stringWithFormat:
        @"/api/song/lyric?id=%@&lv=-1&tv=-1&yv=-1", song.songID];
    [[NESession shared] GET:path params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        if (![json isKindOfClass:[NSDictionary class]]) { complete(nil, nil); return; }

        NSString *lrc = json[@"lrc"][@"lyric"];
        NSString *tl  = json[@"tlyric"][@"lyric"];
        NSString *yrc = json[@"yrc"][@"lyric"];

        NELyric *lyric = [NELyric lyricWithLRC:(lrc.length ? lrc : nil)
                                       tlyric:(tl.length ? tl : nil)
                                          yrc:(yrc.length ? yrc : nil)];
        complete(lyric, nil);
    }];
}

@end