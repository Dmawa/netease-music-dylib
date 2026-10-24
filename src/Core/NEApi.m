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

/// 服务端常见 null/数字混用：统一转成安全字符串，避免 NSNull 进 UILabel 导致崩溃
static NSString *NEString(id v) {
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return @"";
}

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
    s.name   = NEString(d[@"name"]);
    NSString *albumName = @"";
    if ([d[@"album"] isKindOfClass:[NSDictionary class]]) albumName = NEString(d[@"album"][@"name"]);
    if (!albumName.length && [d[@"al"] isKindOfClass:[NSDictionary class]]) albumName = NEString(d[@"al"][@"name"]);
    s.album = albumName;

    NSArray *artists = d[@"artists"] ?: d[@"ar"];
    if ([artists isKindOfClass:[NSArray class]]) s.artist = NEArtistsString(artists);
    if (!s.artist.length) s.artist = @"未知艺术家";

    // 不同接口给的字段不一样：
    //   cloudsearch/pc -> al.picUrl
    //   playlist/detail & song/detail -> album.picUrl
    //   search/get -> 只有 album.picId（缺加密串，拼不出来，只能留空）
    NSString *cover = @"";
    if ([d[@"al"] isKindOfClass:[NSDictionary class]]) cover = NEString(d[@"al"][@"picUrl"]);
    if (!cover.length && [d[@"album"] isKindOfClass:[NSDictionary class]]) cover = NEString(d[@"album"][@"picUrl"]);
    if (!cover.length) cover = NEString(d[@"picUrl"]);
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
    // 官方 web 用的是 /weapi 加密接口；明文 /api 会被判成旧版客户端
    [[NESession shared] POSTWeapi:@"/weapi/login/qrcode/unikey"
                           params:@{@"type": @1}
                         complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSString *key = json[@"unikey"];
        if ([key isKindOfClass:[NSString class]] && key.length) complete(key, nil);
        else complete(nil, [NSError errorWithDomain:@"NEMusic" code:-10
                                           userInfo:@{NSLocalizedDescriptionKey: @"服务端未返回登录 key"}]);
    }];
}

- (void)pollQRCode:(NSString *)unikey complete:(NEPollBlock)complete {
    // 与官方一致：key 放在 POST body 里，不放 query
    [[NESession shared] POSTWeapi:@"/weapi/login/qrcode/client/login"
                           params:@{@"key": unikey ?: @"", @"type": @1}
                         complete:^(id json, NSError *error) {
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
    [[NESession shared] POSTWeapi:@"/weapi/login/qrcode/client/login"
                           params:@{@"key": unikey ?: @"", @"type": @1}
                         complete:^(id json, NSError *error) {
        if (error) { complete(-1, nil, nil, nil, error); return; }

        // 原始响应全量打日志：出现 8821 这类非标准状态码时能直接看到服务端说法
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[NELogin] poll raw = %@", json);
        }

        NSInteger code = -1;
        if ([json isKindOfClass:[NSDictionary class]]) {
            code = [json[@"code"] integerValue];
        }
        NSString *nick = [json isKindOfClass:[NSDictionary class]] ? json[@"nickname"] : nil;
        NSString *message = [json isKindOfClass:[NSDictionary class]] ? json[@"message"] : nil;
        if (![message isKindOfClass:[NSString class]]) message = nil;
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
        complete(code, nick, raw, message, nil);
    }];
}

- (void)restoreSession:(void (^)(BOOL, NSString *, NSString *))complete {
    // 没有本地 Cookie：直接判定未登录
    if (![NESession shared].isLoggedIn) {
        complete(NO, nil, nil);
        return;
    }
    // 有 MUSIC_U：向服务端确认一次（可能已过期/被踢下线）
    // 官方 803 之后用的是 /api/w/nuser/account/get，这里保持一致
    [[NESession shared] GET:@"/api/w/nuser/account/get" params:nil complete:^(id json, NSError *error) {
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
        complete(YES, NEString(profile[@"nickname"]), NEString(profile[@"avatarUrl"]));
    }];
}

- (void)fetchAccount:(void (^)(NSString *, NSString *, NSError *))complete {
    // 官方登录成功后查的是 /api/w/nuser/account/get
    [[NESession shared] GET:@"/api/w/nuser/account/get" params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, nil, error); return; }
        NSDictionary *profile = json[@"profile"];
        if (![profile isKindOfClass:[NSDictionary class]]) { complete(nil, nil, nil); return; }
        complete(NEString(profile[@"nickname"]), NEString(profile[@"avatarUrl"]), nil);
    }];
}

- (void)fetchProfile:(void (^)(NSDictionary *, NSError *))complete {
    [[NESession shared] GET:@"/api/w/nuser/account/get" params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSDictionary *profile = json[@"profile"];
        if ([profile isKindOfClass:[NSDictionary class]]) complete(profile, nil);
        else complete(nil, nil);
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

/// 批量取歌曲详情（v6 playlist/detail 的 tracks 只给前 10 首，必须用 trackIds 补全）
- (void)fetchSongsByIDs:(NSArray<NSString *> *)ids complete:(NESongsBlock)complete {
    [self fetchSongsByIDs:ids offset:0 collected:[NSMutableArray array] complete:complete];
}

- (void)fetchSongsByIDs:(NSArray<NSString *> *)ids
                 offset:(NSInteger)offset
              collected:(NSMutableArray *)out
               complete:(NESongsBlock)complete {
    if (offset >= (NSInteger)ids.count) {
        complete([out copy], nil);
        return;
    }
    NSInteger n = MIN(200, (NSInteger)ids.count - offset);
    NSArray *chunk = [ids subarrayWithRange:NSMakeRange((NSUInteger)offset, (NSUInteger)n)];
    NSString *idsParam = [NSString stringWithFormat:@"[%@]", [chunk componentsJoinedByString:@","]];
    idsParam = [idsParam stringByReplacingOccurrencesOfString:@"[" withString:@"%5B"];
    idsParam = [idsParam stringByReplacingOccurrencesOfString:@"]" withString:@"%5D"];
    NSString *path = [NSString stringWithFormat:@"/api/song/detail?ids=%@", idsParam];

    __weak typeof(self) weakSelf = self;
    [[NESession shared] GET:path params:nil complete:^(id json, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (error) { complete([out copy], error); return; }

        NSMutableDictionary<NSString *, NESong *> *byID = [NSMutableDictionary dictionary];
        NSArray *arr = json[@"songs"];
        if ([arr isKindOfClass:[NSArray class]]) {
            for (NSDictionary *d in arr) {
                if (![d isKindOfClass:[NSDictionary class]]) continue;
                NESong *song = NESongFromJSON(d);
                if (song.songID.length) byID[song.songID] = song;
            }
        }
        for (NSString *sid in chunk) {
            NESong *song = byID[sid];
            if (song) [out addObject:song];
        }
        [self fetchSongsByIDs:ids offset:offset + n collected:out complete:complete];
    }];
}

- (void)fetchPlaylistSongs:(NSString *)playlistID complete:(NESongsBlock)complete {
    NSString *path = [NSString stringWithFormat:@"/api/v6/playlist/detail?id=%@", playlistID];
    __weak typeof(self) weakSelf = self;
    [[NESession shared] GET:path params:nil complete:^(id json, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (error) { complete(nil, error); return; }

        NSDictionary *pl = json[@"playlist"];
        NSArray *tracks = pl[@"tracks"];
        NSArray *trackIds = pl[@"trackIds"];

        // v6 只返回前 10 首 tracks，用 trackIds 全量补
        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        if ([trackIds isKindOfClass:[NSArray class]]) {
            for (id t in trackIds) {
                id ident = [t isKindOfClass:[NSDictionary class]] ? t[@"id"] : nil;
                if (ident && [ident respondsToSelector:@selector(description)]) {
                    [ids addObject:[ident description]];
                }
            }
        }
        if (ids.count &&
            (![tracks isKindOfClass:[NSArray class]] || tracks.count < ids.count)) {
            [self fetchSongsByIDs:ids complete:complete];
            return;
        }
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
                p.name = NEString(d[@"name"]);
                p.coverURL = NEString(d[@"coverImgUrl"]);
                p.trackCount = [d[@"trackCount"] integerValue];
                p.specialType = [d[@"specialType"] integerValue];
                NSDictionary *creatorInfo = [d[@"creator"] isKindOfClass:[NSDictionary class]] ? d[@"creator"] : nil;
                NSNumber *cid = creatorInfo[@"userId"];
                p.creatorID = [cid isKindOfClass:[NSNumber class]] ? cid.integerValue : 0;
                p.creatorName = NEString(creatorInfo[@"nickname"]);
                p.playCount = [d[@"playCount"] integerValue];
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

- (void)fetchDailyRecommendSongs:(NESongsBlock)complete {
    // v3 接口；老的 /api/recommend/songs 已经 404，不要再用
    [[NESession shared] GET:@"/api/v3/discovery/recommend/songs" params:nil
                  complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSArray *daily = json[@"data"][@"dailySongs"];
        if (![daily isKindOfClass:[NSArray class]]) daily = json[@"recommend"];
        if (![daily isKindOfClass:[NSArray class]]) { complete(@[], nil); return; }
        complete([NSArray arrayWithArray:NESongsFromArray(daily)], nil);
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
                it.itemID = d[@"id"] ? [d[@"id"] description] : @"";
                it.title = NEString(d[@"name"]);
                it.coverURL = NEString(d[@"picUrl"]);
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
                it.itemID = song[@"id"] ? [song[@"id"] description] : @"";
                it.title = NEString(song[@"name"]);
                NSArray *ar = song[@"artists"];
                if (![ar isKindOfClass:[NSArray class]]) ar = song[@"ar"];
                it.subtitle = [ar isKindOfClass:[NSArray class]] ? NEArtistsString(ar) : @"";
                NSString *pic = NEString(song[@"picUrl"]);
                if (!pic.length) pic = NEString(d[@"picUrl"]);
                it.coverURL = pic;
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
                it.itemID = d[@"id"] ? [d[@"id"] description] : @"";
                it.title = NEString(d[@"name"]);
                it.coverURL = NEString(d[@"coverImgUrl"]);
                it.subtitle = NEString(d[@"updateFrequency"]);
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

- (void)fetchCommentsForSongID:(NSString *)songID limit:(NSInteger)limit
                         complete:(void (^)(NSArray<NSDictionary *> *, NSInteger, NSError *))complete {
    if (!songID.length) {
        complete(nil, 0, [NSError errorWithDomain:@"NEMusic" code:-30
                                          userInfo:@{NSLocalizedDescriptionKey: @"歌曲 ID 为空"}]);
        return;
    }
    NSString *path = [NSString stringWithFormat:
        @"/api/v1/resource/comments/R_SO_4_%@?limit=%ld&offset=0",
        songID, (long)MAX(1, limit)];
    [[NESession shared] GET:path params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, 0, error); return; }
        if (![json isKindOfClass:[NSDictionary class]]) { complete(@[], 0, nil); return; }

        NSMutableArray *all = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSString *key in @[@"hotComments", @"comments"]) {
            NSArray *arr = json[key];
            if (![arr isKindOfClass:[NSArray class]]) continue;
            for (NSDictionary *c in arr) {
                if (![c isKindOfClass:[NSDictionary class]]) continue;
                id cid = c[@"commentId"];
                if (cid && [seen containsObject:cid]) continue;
                if (cid) [seen addObject:cid];
                [all addObject:c];
            }
        }
        complete(all, [json[@"total"] integerValue], nil);
    }];
}

- (void)fetchSongLikeState:(NSString *)songID
                  complete:(void (^)(NSInteger, BOOL, NSError *))complete {
    if (!songID.length) { complete(0, NO, nil); return; }
    [[NESession shared] GET:@"/api/song/like/get" params:@{@"id": songID}
                  complete:^(id json, NSError *error) {
        if (error) { complete(0, NO, error); return; }
        NSDictionary *data = [json[@"data"] isKindOfClass:[NSDictionary class]] ? json[@"data"] : json;
        NSInteger count = [data[@"likedCount"] integerValue];
        BOOL liked = [data[@"liked"] boolValue];
        complete(count, liked, nil);
    }];
}

- (void)likeSongID:(NSString *)songID liked:(BOOL)liked complete:(void (^)(BOOL, NSError *))complete {
    if (![self isLoggedIn]) {
        complete(NO, [NSError errorWithDomain:@"NEMusic" code:-31
                                    userInfo:@{NSLocalizedDescriptionKey: @"请先登录"}]);
        return;
    }
    NSString *path = @"/api/song/like/change";
    [[NESession shared] GET:path
                     params:@{@"id": songID, @"like": liked ? @"true" : @"false"}
                   complete:^(id json, NSError *error) {
        if (error) { complete(NO, error); return; }
        NSInteger code = [json[@"code"] integerValue];
        if (code == 200) { complete(YES, nil); return; }
        NSString *msg = json[@"message"] ?: @"操作失败";
        complete(NO, [NSError errorWithDomain:@"NEMusic" code:code
                                    userInfo:@{NSLocalizedDescriptionKey: msg}]);
    }];
}

- (void)fetchMineHeaderWithUserID:(NSString *)uid
                         complete:(void (^)(NSDictionary *, NSError *))complete {
    if (!uid.length) { complete(nil, nil); return; }
    NSDictionary *params = @{@"isVisitor": @"false", @"userId": uid};
    [[NESession shared] GET:@"/api/mine/rn/header/info/get" params:params
                  complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }
        NSDictionary *header = json[@"data"][@"headerInfo"];
        if ([header isKindOfClass:[NSDictionary class]]) complete(header, nil);
        else complete(nil, nil);
    }];
}

- (void)fetchUserDetailWithUID:(NSString *)uid
                      complete:(void (^)(NSInteger, NSInteger, NSError *))complete {
    if (!uid.length) { complete(0, 0, nil); return; }
    NSString *path = [NSString stringWithFormat:@"/api/v1/user/detail/%@", uid];
    [[NESession shared] GET:path params:nil complete:^(id json, NSError *error) {
        if (error) { complete(0, 0, error); return; }
        complete([json[@"level"] integerValue], [json[@"listenSongs"] integerValue], nil);
    }];
}

- (void)fetchHeartModeSongsWithSeed:(NSString *)seedID limit:(NSInteger)limit
                           complete:(NESongsBlock)complete {
    if (!seedID.length) seedID = @"347230";
    NSString *path = [NSString stringWithFormat:
        @"/api/playmode/intelligence/list?id=%@&startMusicId=%@&count=%ld",
        seedID, seedID, (long)MAX(1, limit)];
    [[NESession shared] GET:path params:nil complete:^(id json, NSError *error) {
        if (error) { complete(nil, error); return; }

        NSArray *arr = nil;
        id data = json[@"data"];
        if ([data isKindOfClass:[NSArray class]]) arr = data;
        else if ([data isKindOfClass:[NSDictionary class]]) {
            arr = data[@"songInfo"] ?: data[@"songs"] ?: data[@"list"];
        }
        if (![arr isKindOfClass:[NSArray class]] || !arr.count) {
            NSString *msg = json[@"message"] ?: @"心动模式需要登录后使用";
            complete(nil, [NSError errorWithDomain:@"NEMusic" code:-32
                                         userInfo:@{NSLocalizedDescriptionKey: msg}]);
            return;
        }
        complete([NSArray arrayWithArray:NESongsFromArray(arr)], nil);
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