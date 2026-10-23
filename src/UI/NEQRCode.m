#import "NEQRCode.h"

/*
 *  最小 QR 编码器：字节模式 / 纠错等级 M / 版本 1-10。
 *  按 ISO/IEC 18004 实现，生成结果可直接被 iOS 相机识别。
 */

typedef struct { int version, size, dataCodewords, ecPerBlock, blocks; } NEQRSpec;

static const NEQRSpec kSpecs[] = {
    { 1, 21,  16, 10, 1 }, { 2, 25,  28, 16, 1 }, { 3, 29,  44, 26, 1 },
    { 4, 33,  64, 18, 2 }, { 5, 37,  86, 24, 2 }, { 6, 41, 108, 16, 4 },
    { 7, 45, 124, 18, 4 }, { 8, 49, 154, 22, 4 }, { 9, 53, 182, 22, 5 },
    {10, 57, 216, 26, 5 },
};
/* 等级 M 的分块结构：v8/v9/v10 由「短块 + 长块」混合组成 */
typedef struct { int groups; int count[2]; int dataLen[2]; } NEQRBlockSpec;
static const NEQRBlockSpec kBlockSpecs[11] = {
    {0,{0,0},{0,0}},
    {1,{1,0},{16,0}}, {1,{1,0},{28,0}}, {1,{1,0},{44,0}}, {1,{2,0},{32,0}},
    {1,{2,0},{43,0}}, {1,{4,0},{27,0}}, {1,{4,0},{31,0}},
    {2,{2,2},{38,39}}, {2,{3,2},{36,37}}, {2,{4,1},{43,44}},
};
static const int kSpecCount = 10;
static const int kAlignTab[11][3] = {{0},{0},{6,18,0},{6,22,0},{6,26,0},{6,30,0},
                                     {6,34,0},{6,22,38},{6,24,42},{6,26,46},{6,28,50}};
static const int kAlignCnt[11] = {0,0,2,2,2,2,2,3,3,3,3};

static uint8_t gExp[512], gLog[256];

static void ne_gf_init(void) {
    static int done = 0;
    if (done) return;
    int x = 1;
    for (int i = 0; i < 255; i++) { gExp[i] = (uint8_t)x; gLog[x] = (uint8_t)i;
        x <<= 1; if (x & 0x100) x ^= 0x11D; }
    for (int i = 255; i < 512; i++) gExp[i] = gExp[i - 255];
    done = 1;
}
static uint8_t ne_mul(uint8_t a, uint8_t b) {
    if (!a || !b) return 0;
    return gExp[(gLog[a] + gLog[b]) % 255];
}

/* 生成 ecLen 个纠错码字（多项式系数按降幂保存，g[0] 恒为 1） */
static void ne_rs(const uint8_t *src, int len, uint8_t *ec, int ecLen) {
    ne_gf_init();
    uint8_t g[64]; for (int i = 0; i < 64; i++) g[i] = 0;
    g[ecLen - 1] = 1;                       /* 先置 x^0 = 1（降幂末位） */
    int glen = 1;                            /* 当前有效项数（从末尾往前） */

    /* 用「升幂数组」更直观：poly[i] 是 x^i 系数 */
    uint8_t poly[64]; for (int i = 0; i < 64; i++) poly[i] = 0;
    poly[0] = 1;
    for (int i = 0; i < ecLen; i++) {
        uint8_t a = gExp[i], nx[64];
        for (int k = 0; k < 64; k++) nx[k] = 0;
        for (int k = 0; k < 64 - 1; k++) {
            if (!poly[k]) continue;
            nx[k + 1] ^= poly[k];            /* * x */
            nx[k]     ^= ne_mul(poly[k], a); /* * a^i */
        }
        for (int k = 0; k < 64; k++) poly[k] = nx[k];
    }
    /* 转成降幂：g[0] 是最高次系数 */
    for (int i = 0; i <= ecLen; i++) g[i] = poly[ecLen - i];
    (void)glen;

    uint8_t rem[64]; for (int i = 0; i < 64; i++) rem[i] = 0;
    for (int i = 0; i < len; i++) {
        uint8_t f = src[i] ^ rem[0];
        for (int j = 0; j < ecLen - 1; j++) rem[j] = rem[j + 1];
        rem[ecLen - 1] = 0;
        for (int j = 0; j < ecLen; j++) rem[j] ^= ne_mul(g[j + 1], f);
    }
    memcpy(ec, rem, ecLen);
}

@implementation NEQRCode

+ (NSArray<NSArray<NSNumber *> *> *)matrixWithText:(NSString *)text {
    NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8.length || utf8.length > 160) return nil;
    int n = (int)utf8.length;

    const NEQRSpec *spec = NULL;
    for (int i = 0; i < kSpecCount; i++) {
        if (n <= kSpecs[i].dataCodewords - 2) { spec = &kSpecs[i]; break; }
    }
    if (!spec) return nil;

    int S = spec->size;
    uint8_t *mod = calloc(S * S, 1);
    uint8_t *res = calloc(S * S, 1);
    if (!mod || !res) { free(mod); free(res); return nil; }
#define P(r,c) ((r)*S+(c))
#define SETR(r,c) do { int _r=(r),_c=(c); if(_r>=0&&_r<S&&_c>=0&&_c<S) res[P(_r,_c)]=1; } while(0)
#define SETMK(r,c,v) do { int _r=(r),_c=(c); if(_r>=0&&_r<S&&_c>=0&&_c<S) { mod[P(_r,_c)]=(v); res[P(_r,_c)]=1; } } while(0)

    /* ---- 1. 定位图案 + 分隔符 ---- */
    for (int t = 0; t < 3; t++) {
        int r0 = (t == 2) ? S - 7 : 0;
        int c0 = (t == 1) ? S - 7 : 0;
        for (int i = -1; i <= 7; i++) {
            for (int j = -1; j <= 7; j++) {
                int r = r0 + i, c = c0 + j;
                if (r < 0 || r >= S || c < 0 || c >= S) continue;
                int on = 0;
                if (i >= 0 && i <= 6 && j >= 0 && j <= 6) {
                    on = (i == 0 || i == 6 || j == 0 || j == 6 ||
                          (i >= 2 && i <= 4 && j >= 2 && j <= 4));
                }
                SETMK(r, c, on);
            }
        }
    }

    /* ---- 2. 定时图案 ---- */
    for (int i = 8; i < S - 8; i++) {
        SETMK(6, i, (i % 2) == 0);
        SETMK(i, 6, (i % 2) == 0);
    }

    /* ---- 3. 对齐图案 ---- */
    if (spec->version >= 2) {
        int cnt = kAlignCnt[spec->version];
        for (int a = 0; a < cnt; a++) {
            for (int b = 0; b < cnt; b++) {
                int cr = kAlignTab[spec->version][a];
                int cc = kAlignTab[spec->version][b];
                /* 与定位图案重叠则跳过 */
                if ((cr <= 8 && cc <= 8) || (cr <= 8 && cc >= S - 9) ||
                    (cr >= S - 9 && cc <= 8)) continue;
                for (int i = -2; i <= 2; i++)
                    for (int j = -2; j <= 2; j++)
                        SETMK(cr + i, cc + j,
                              (abs(i) == 2 || abs(j) == 2 || (i == 0 && j == 0)));
            }
        }
    }

    /* ---- 4. 格式信息占位（15 位 x2 + 固定暗模块） ---- */
    static const int fmtA[15][2] = {
        {8,0},{8,1},{8,2},{8,3},{8,4},{8,5},{8,7},{8,8},
        {7,8},{5,8},{4,8},{3,8},{2,8},{1,8},{0,8}
    };
    for (int i = 0; i < 15; i++) SETR(fmtA[i][0], fmtA[i][1]);
    for (int i = 0; i < 7; i++)  SETR(S - 1 - i, 8);
    for (int i = 0; i < 8; i++)  SETR(8, S - 8 + i);
    SETMK(S - 8, 8, 1);   /* 固定的暗模块 */

    /* ---- 5. 版本信息占位（v>=7） ---- */
    if (spec->version >= 7) {
        for (int i = 0; i < 6; i++)
            for (int j = 0; j < 3; j++)
                { SETR(S - 11 + j, i); SETR(i, S - 11 + j); }
    }

    /* ---- 6. 数据位流 ---- */
    int cap = spec->dataCodewords;
    int totalBits = cap * 8;
    uint8_t *bits = calloc(totalBits, 1);
    int bp = 0;
    for (int i = 3; i >= 0; i--) bits[bp++] = (4 >> i) & 1;      /* 字节模式 */
    for (int i = 7; i >= 0; i--) bits[bp++] = (n >> i) & 1;      /* 长度 */
    const uint8_t *b = utf8.bytes;
    for (int i = 0; i < n; i++)
        for (int k = 7; k >= 0; k--) bits[bp++] = (b[i] >> k) & 1;

    int left = totalBits - bp;
    for (int i = 0; i < left && i < 4; i++) bits[bp++] = 0;      /* 终止符 */
    while (bp % 8) bits[bp++] = 0;
    uint8_t pad = 0xEC;
    while (bp < totalBits) {
        for (int k = 7; k >= 0; k--) bits[bp++] = (pad >> k) & 1;
        pad = (pad == 0xEC) ? 0x11 : 0xEC;
    }

    uint8_t *cw = calloc(cap, 1);
    for (int i = 0; i < cap; i++) {
        uint8_t v = 0;
        for (int k = 0; k < 8; k++) v = (uint8_t)((v << 1) | bits[i * 8 + k]);
        cw[i] = v;
    }

    /* ---- 7. 纠错 + 交织 ---- */
    /* 按分块结构切分：先短块组，后长块组 */
    NEQRBlockSpec bs = kBlockSpecs[spec->version];
    int nBlocks = bs.count[0] + bs.count[1];
    int ecLen = spec->ecPerBlock;

    int blkData[16], blkOff[16], nb = 0, off = 0;
    for (int g = 0; g < bs.groups; g++)
        for (int i = 0; i < bs.count[g]; i++) {
            blkData[nb] = bs.dataLen[g];
            blkOff[nb]  = off;
            off += bs.dataLen[g];
            nb++;
        }

    uint8_t *ecc = calloc((size_t)nBlocks * ecLen, 1);
    for (int i = 0; i < nb; i++)
        ne_rs(cw + blkOff[i], blkData[i], ecc + i * ecLen, ecLen);

    /* 交织：数据按列取（短块先取完），纠错按块轮转 */
    int tcw = cap + nBlocks * ecLen;
    uint8_t *fin = calloc(tcw, 1);
    int fp = 0;
    int maxData = 0;
    for (int i = 0; i < nb; i++) if (blkData[i] > maxData) maxData = blkData[i];
    for (int col = 0; col < maxData; col++)
        for (int i = 0; i < nb; i++)
            if (col < blkData[i]) fin[fp++] = cw[blkOff[i] + col];
    for (int col = 0; col < ecLen; col++)
        for (int i = 0; i < nb; i++) fin[fp++] = ecc[i * ecLen + col];

    /* ---- 8. 蛇形放置 ---- */
    int bi = 0, up = 1;
    for (int col = S - 1; col > 0; col -= 2) {
        if (col == 6) col--;
        for (int k = 0; k < S; k++) {
            int r = up ? (S - 1 - k) : k;
            for (int c = 0; c < 2; c++) {
                int cc = col - c;
                if (res[P(r, cc)]) continue;
                int bit = (bi < tcw * 8) ? ((fin[bi / 8] >> (7 - (bi % 8))) & 1) : 0;
                bi++;
                mod[P(r, cc)] = (uint8_t)bit;
            }
        }
        up = !up;
    }

    /* ---- 9. 掩码：8 种全试，按标准惩罚分取最优 ---- */
    uint8_t *best = malloc(S * S);
    int bestScore = INT_MAX, bestMask = 0;
    uint8_t *tmp = malloc(S * S);

    for (int mask = 0; mask < 8; mask++) {
        memcpy(tmp, mod, S * S);
        for (int r = 0; r < S; r++) {
            for (int c = 0; c < S; c++) {
                if (res[P(r, c)]) continue;
                int inv = 0;
                switch (mask) {
                    case 0: inv = ((r + c) % 2) == 0; break;
                    case 1: inv = (r % 2) == 0; break;
                    case 2: inv = (c % 3) == 0; break;
                    case 3: inv = ((r + c) % 3) == 0; break;
                    case 4: inv = ((r / 2 + c / 3) % 2) == 0; break;
                    case 5: inv = (((r * c) % 2) + ((r * c) % 3)) == 0; break;
                    case 6: inv = (((((r * c) % 2) + ((r * c) % 3)) % 2)) == 0; break;
                    case 7: inv = (((((r + c) % 2) + ((r * c) % 3)) % 2)) == 0; break;
                }
                if (inv) tmp[P(r, c)] ^= 1;
            }
        }

        int score = 0;
        /* 规则1：行/列连续同色 ≥5 */
        for (int r = 0; r < S; r++) {
            int run = 1;
            for (int c = 1; c < S; c++) {
                if (tmp[P(r,c)] == tmp[P(r,c-1)]) {
                    run++;
                    if (run == 5) score += 3; else if (run > 5) score++;
                } else run = 1;
            }
        }
        for (int c = 0; c < S; c++) {
            int run = 1;
            for (int r = 1; r < S; r++) {
                if (tmp[P(r,c)] == tmp[P(r-1,c)]) {
                    run++;
                    if (run == 5) score += 3; else if (run > 5) score++;
                } else run = 1;
            }
        }
        /* 规则2：2x2 同色块 */
        for (int r = 0; r < S - 1; r++)
            for (int c = 0; c < S - 1; c++) {
                uint8_t v = tmp[P(r,c)];
                if (v == tmp[P(r,c+1)] && v == tmp[P(r+1,c)] && v == tmp[P(r+1,c+1)])
                    score += 3;
            }
        /* 规则3：1:1:3:1:1 模式 */
        static const int pat[11] = {1,0,1,1,1,0,1,0,0,0,0};
        for (int r = 0; r < S; r++)
            for (int c = 0; c + 11 <= S; c++) {
                int ok = 1;
                for (int k = 0; k < 11; k++) if (tmp[P(r,c+k)] != pat[k]) { ok = 0; break; }
                if (ok) score += 40;
                ok = 1;
                for (int k = 0; k < 11; k++) if (tmp[P(r,c+k)] != pat[10-k]) { ok = 0; break; }
                if (ok) score += 40;
            }
        for (int c = 0; c < S; c++)
            for (int r = 0; r + 11 <= S; r++) {
                int ok = 1;
                for (int k = 0; k < 11; k++) if (tmp[P(r+k,c)] != pat[k]) { ok = 0; break; }
                if (ok) score += 40;
                ok = 1;
                for (int k = 0; k < 11; k++) if (tmp[P(r+k,c)] != pat[10-k]) { ok = 0; break; }
                if (ok) score += 40;
            }
        /* 规则4：黑白比例偏离 50% */
        int dark = 0;
        for (int i = 0; i < S * S; i++) dark += tmp[i] ? 1 : 0;
        int ratio = (dark * 100) / (S * S);
        score += (abs(ratio - 50) / 5) * 10;

        if (score < bestScore) {
            bestScore = score;
            bestMask = mask;
            memcpy(best, tmp, S * S);
        }
    }
    free(tmp);

    /* ---- 10. 写入格式信息（等级 M = 0b00，MSB 优先） ---- */
    int data5 = (0 << 3) | bestMask;
    int v = data5 << 10;
    for (int i = 4; i >= 0; i--)
        if ((v >> (10 + i)) & 1) v ^= 0x537 << i;
    int fmt = ((data5 << 10) | (v & 0x3FF)) ^ 0x5412;

    for (int i = 0; i < 15; i++) {
        int bit = (fmt >> (14 - i)) & 1;    /* MSB 优先 */
        best[P(fmtA[i][0], fmtA[i][1])] = (uint8_t)bit;
    }
    /* 副本 B：自 (S-1,8) 向上 7 格，再 (8,S-8) 向右 8 格，整体 MSB 优先 */
    for (int i = 0; i < 7; i++)
        best[P(S - 1 - i, 8)] = (uint8_t)((fmt >> (14 - i)) & 1);
    for (int i = 0; i < 8; i++)
        best[P(8, S - 8 + i)] = (uint8_t)((fmt >> (7 - i)) & 1);
    best[P(S - 8, 8)] = 1;

    /* ---- 11. 版本信息（v>=7） ---- */
    if (spec->version >= 7) {
        int vd = spec->version << 12, vv = vd;
        for (int i = 5; i >= 0; i--)
            if ((vv >> (12 + i)) & 1) vv ^= 0x1F25 << i;
        int vb = vd | (vv & 0xFFF);
        for (int i = 0; i < 18; i++) {
            int bit = (vb >> i) & 1;
            int r = i / 3, c = i % 3;
            best[P(r, S - 11 + c)] = (uint8_t)bit;
            best[P(S - 11 + c, r)] = (uint8_t)bit;
        }
    }

    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:S];
    for (int r = 0; r < S; r++) {
        NSMutableArray *row = [NSMutableArray arrayWithCapacity:S];
        for (int c = 0; c < S; c++)
            [row addObject:@(best[P(r, c)] ? YES : NO)];
        [rows addObject:row];
    }

    free(mod); free(res); free(bits); free(cw); free(ecc); free(fin); free(best);
#undef P
#undef SETR
#undef SETMK
    return rows;
}

+ (UIImage *)imageWithText:(NSString *)text size:(CGFloat)size {
    NSArray *m = [self matrixWithText:text];
    if (!m.count) return nil;
    NSInteger n = m.count;
    NSInteger scale = MAX(2, (NSInteger)(size / (n + 8)));
    NSInteger dim = (n + 8) * scale;

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    fmt.opaque = YES;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(dim, dim) format:fmt]
            imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef g = ctx.CGContext;
        CGContextSetFillColorWithColor(g, UIColor.whiteColor.CGColor);
        CGContextFillRect(g, CGRectMake(0, 0, dim, dim));
        CGContextSetFillColorWithColor(g, UIColor.blackColor.CGColor);
        for (NSInteger r = 0; r < n; r++)
            for (NSInteger c = 0; c < n; c++)
                if ([m[r][c] boolValue])
                    CGContextFillRect(g, CGRectMake((c + 4) * scale, (r + 4) * scale, scale, scale));
    }];
}

@end