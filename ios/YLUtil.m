#import "YLUtil.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>

@implementation YLUtil

#pragma mark - decode

+ (NSStringEncoding)encodingForCharset:(NSString *)charset {
    if (!charset.length) {
        return 0;
    }
    NSString *name = [[charset stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    name = [name stringByTrimmingCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@"\"';>"]];
    if ([name isEqualToString:@"utf-8"] || [name isEqualToString:@"utf8"]) {
        return NSUTF8StringEncoding;
    }
    if ([name isEqualToString:@"gb2312"] || [name isEqualToString:@"gbk"] ||
        [name isEqualToString:@"gb18030"] || [name isEqualToString:@"cp936"]) {
        return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    }
    if ([name isEqualToString:@"big5"] || [name isEqualToString:@"big-5"]) {
        return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingBig5);
    }
    if ([name isEqualToString:@"utf-16"] || [name isEqualToString:@"utf-16le"]) {
        return NSUTF16LittleEndianStringEncoding;
    }
    CFStringEncoding cfEncoding = CFStringConvertIANACharSetNameToEncoding(
        (__bridge CFStringRef)name);
    if (cfEncoding != kCFStringEncodingInvalidId) {
        return CFStringConvertEncodingToNSStringEncoding(cfEncoding);
    }
    return 0;
}

+ (NSString *)decodeData:(NSData *)data charset:(NSString *)charset {
    if (!data.length) {
        return @"";
    }
    NSStringEncoding encoding = [self encodingForCharset:charset];
    if (!encoding) {
        return nil;
    }
    return [[NSString alloc] initWithData:data encoding:encoding];
}

+ (NSString *)decodeData:(NSData *)data {
    if (!data.length) {
        return @"";
    }
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSUInteger length = data.length;
    if (length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
        return [[NSString alloc] initWithData:[data subdataWithRange:
            NSMakeRange(3, length - 3)] encoding:NSUTF8StringEncoding] ?: @"";
    }
    if (length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF16LittleEndianStringEncoding];
        if (text) { return text; }
    }
    if (length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF16BigEndianStringEncoding];
        if (text) { return text; }
    }

    NSUInteger headLength = MIN(length, (NSUInteger)4096);
    NSString *head = [[NSString alloc] initWithData:[data subdataWithRange:
        NSMakeRange(0, headLength)] encoding:NSISOLatin1StringEncoding] ?: @"";

    NSRange marker = [head rangeOfString:@"charset=" options:NSCaseInsensitiveSearch];
    if (marker.location != NSNotFound) {
        NSUInteger start = marker.location + marker.length;
        NSMutableString *charset = [NSMutableString string];
        for (NSUInteger i = start; i < head.length && charset.length < 32; i += 1) {
            unichar ch = [head characterAtIndex:i];
            if (ch == '"' || ch == '\'' || ch == ';' || ch == '>' ||
                ch == ' ' || ch == '\n' || ch == '\r' || ch == '/') {
                break;
            }
            [charset appendFormat:@"%C", ch];
        }
        NSString *text = [self decodeData:data charset:charset];
        if (text.length) {
            return text;
        }
    }

    NSArray *encodings = @[
        @(NSUTF8StringEncoding),
        @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)),
        @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingBig5))
    ];
    for (NSNumber *number in encodings) {
        NSString *text = [[NSString alloc] initWithData:data encoding:(NSStringEncoding)number.unsignedIntegerValue];
        if (text) {
            return text;
        }
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

#pragma mark - encoding

+ (NSString *)base64Encode:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    return [data base64EncodedStringWithOptions:0];
}

+ (NSString *)base64Decode:(NSString *)text {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:text options:
        NSDataBase64DecodingIgnoreUnknownCharacters];
    if (!data) {
        return @"";
    }
    return [self decodeData:data];
}

+ (NSString *)md5:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i += 1) {
        [out appendFormat:@"%02x", digest[i]];
    }
    return out;
}

#pragma mark - json

+ (NSString *)jsonString:(id)object {
    if (!object) {
        return @"{}";
    }
    if (![NSJSONSerialization isValidJSONObject:object]) {
        return @"{}";
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    if (!data) {
        return @"{}";
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
}

+ (id)jsonObject:(NSString *)text {
    if (!text.length) {
        return nil;
    }
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return object;
}

+ (BOOL)writeJSON:(id)object toFile:(NSString *)path {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    if (!data) {
        return NO;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:
        [path stringByDeletingLastPathComponent]
        withIntermediateDirectories:YES attributes:nil error:NULL];
    return [data writeToFile:path atomically:YES];
}

@end
