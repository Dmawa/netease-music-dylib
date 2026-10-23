#import "NECrypto.h"
#import <CommonCrypto/CommonCryptor.h>
#import <Security/Security.h>

/// 第一层 AES 的固定密钥、固定 IV（与官方前端一致）
static NSString *const kNEWeapiPresetKey = @"0CoJUm6Qyw8W8jud";
static NSString *const kNEWeapiIV        = @"0102030405060708";
static NSString *const kNEWeapiCharset   = @"abcdefghijklmnopqrstuvwxyz0123456789";

/// RSA-1024 模数：官方前端 asrsea 里的同一串（已去掉前导 00，正好 128 字节）
static NSString *const kNEWeapiModulusHex =
    @"e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b72515"
    @"2b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ec"
    @"bda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d8"
    @"13cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7";

@implementation NECrypto

#pragma mark - 工具

+ (NSData *)dataFromHex:(NSString *)hex {
    NSMutableData *out = [NSMutableData dataWithCapacity:hex.length / 2];
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
        unsigned int v = 0;
        [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&v];
        uint8_t b = (uint8_t)v;
        [out appendBytes:&b length:1];
    }
    return out;
}

+ (NSString *)reversed:(NSString *)s {
    NSMutableString *r = [NSMutableString stringWithCapacity:s.length];
    for (NSInteger i = (NSInteger)s.length - 1; i >= 0; i--) {
        [r appendFormat:@"%C", [s characterAtIndex:(NSUInteger)i]];
    }
    return r;
}

#pragma mark - AES

+ (NSString *)aesBase64:(NSString *)text key:(NSString *)key {
    NSData *inData = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!inData) return nil;

    size_t outLen = inData.length + kCCBlockSizeAES128;
    uint8_t *buf = malloc(outLen);
    if (!buf) return nil;

    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
                                 key.UTF8String, kCCKeySizeAES128, kNEWeapiIV.UTF8String,
                                 inData.bytes, inData.length,
                                 buf, outLen, &moved);
    NSString *result = nil;
    if (st == kCCSuccess && moved > 0) {
        result = [[NSData dataWithBytes:buf length:moved] base64EncodedStringWithOptions:0];
    }
    free(buf);
    return result;
}

#pragma mark - RSA（raw RSA，等价于前端的 modPow）

+ (NSString *)rsaHexForSecretKey:(NSString *)secKey {
    NSData *mod = [self dataFromHex:kNEWeapiModulusHex];
    if (mod.length != 128) {
        NSLog(@"[NECrypto] 模数长度异常: %lu", (unsigned long)mod.length);
        return nil;
    }

    // PKCS#1 RSAPublicKey 的 DER：SEQUENCE { INTEGER n, INTEGER e }
    NSMutableData *der = [NSMutableData data];
    const uint8_t head[] = {0x30, 0x81, 0x89, 0x02, 0x81, 0x81, 0x00};
    [der appendBytes:head length:sizeof(head)];
    [der appendData:mod];
    const uint8_t exp[] = {0x02, 0x03, 0x01, 0x00, 0x01};   // 65537
    [der appendBytes:exp length:sizeof(exp)];

    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType:       (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeyClass:      (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits: @1024,
    };
    CFErrorRef keyErr = NULL;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)der,
                                         (__bridge CFDictionaryRef)attrs, &keyErr);
    if (!key) {
        NSLog(@"[NECrypto] RSA 公钥构造失败: %@", keyErr);
        return nil;
    }

    // 前端把 secKey 反转后当成大整数：等价于 16 字节倒序、左侧补零到 128 字节
    NSMutableData *input = [NSMutableData dataWithLength:128];
    NSData *keyBytes = [[self reversed:secKey] dataUsingEncoding:NSASCIIStringEncoding];
    if (keyBytes.length > 128) keyBytes = [keyBytes subdataWithRange:NSMakeRange(0, 128)];
    memcpy((uint8_t *)input.mutableBytes + (128 - keyBytes.length), keyBytes.bytes, keyBytes.length);

    CFErrorRef encErr = NULL;
    CFDataRef enc = SecKeyCreateEncryptedData(key, kSecKeyAlgorithmRSAEncryptionRaw,
                                              (__bridge CFDataRef)input, &encErr);
    CFRelease(key);
    if (!enc) {
        NSLog(@"[NECrypto] RSA 加密失败: %@", encErr);
        return nil;
    }

    NSData *out = (__bridge_transfer NSData *)enc;
    NSMutableString *hex = [NSMutableString stringWithCapacity:out.length * 2];
    const uint8_t *p = out.bytes;
    for (NSUInteger i = 0; i < out.length; i++) [hex appendFormat:@"%02x", p[i]];
    return hex;
}

#pragma mark - 对外

+ (NSString *)weapiBodyWithData:(NSDictionary<NSString *, id> *)data {
    NSError *jsonErr = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:0 error:&jsonErr];
    if (!jsonData) {
        NSLog(@"[NECrypto] JSON 序列化失败: %@", jsonErr);
        return nil;
    }
    NSString *text = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    if (!text) return nil;

    uint8_t rnd[16];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(rnd), rnd) != errSecSuccess) return nil;
    unichar chars[16];
    for (int i = 0; i < 16; i++) chars[i] = [kNEWeapiCharset characterAtIndex:rnd[i] % 36];
    NSString *secKey = [NSString stringWithCharacters:chars length:16];

    // 前端是两层 AES：先 presetKey，再随机 secKey
    NSString *inner = [self aesBase64:text key:kNEWeapiPresetKey];
    if (!inner) return nil;
    NSString *params = [self aesBase64:inner key:secKey];
    if (!params) return nil;

    NSString *encSecKey = [self rsaHexForSecretKey:secKey];
    if (!encSecKey) return nil;

    // base64 里的 + / = 必须转义
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *escaped = [params stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    if (!escaped) return nil;

    return [NSString stringWithFormat:@"params=%@&encSecKey=%@", escaped, encSecKey];
}

@end
