#import "YLZip.h"
#import "YLUtil.h"
#import <zlib.h>

static uint16_t YLReadUInt16(const uint8_t *bytes, NSUInteger offset, NSUInteger length) {
    if (offset + 2 > length) {
        return 0;
    }
    return (uint16_t)(bytes[offset] | ((uint16_t)bytes[offset + 1] << 8));
}

static uint32_t YLReadUInt32(const uint8_t *bytes, NSUInteger offset, NSUInteger length) {
    if (offset + 4 > length) {
        return 0;
    }
    return (uint32_t)(bytes[offset] |
                      ((uint32_t)bytes[offset + 1] << 8) |
                      ((uint32_t)bytes[offset + 2] << 16) |
                      ((uint32_t)bytes[offset + 3] << 24));
}

static NSError *YLMakingError(NSString *message) {
    return [NSError errorWithDomain:@"YLZip" code:1
                            userInfo:@{NSLocalizedDescriptionKey: message ?: @"ZIP 错误"}];
}

@implementation YLZip

+ (NSDictionary *)readEntriesAtPath:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
    if (!data) {
        return nil;
    }
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger length = data.length;
    if (length < 22) {
        if (error) { *error = YLMakingError(@"文件太小，不是 zip"); }
        return nil;
    }

    NSInteger eocd = -1;
    NSInteger limit = (NSInteger)length - 22 - 65557;
    if (limit < 0) { limit = 0; }
    for (NSInteger i = (NSInteger)length - 22; i >= limit; i -= 1) {
        if (YLReadUInt32(bytes, (NSUInteger)i, length) == 0x06054b50) {
            if ((NSUInteger)i + 22 <= length) {
                eocd = i;
                break;
            }
        }
    }
    if (eocd < 0) {
        if (error) { *error = YLMakingError(@"找不到 zip 目录"); }
        return nil;
    }

    uint16_t total = YLReadUInt16(bytes, (NSUInteger)eocd + 10, length);
    uint32_t offset = YLReadUInt32(bytes, (NSUInteger)eocd + 16, length);
    if (offset == 0xFFFFFFFF) {
        if (error) { *error = YLMakingError(@"不支持 ZIP64"); }
        return nil;
    }

    NSMutableDictionary *entries = [NSMutableDictionary dictionary];
    NSUInteger entryOffset = offset;
    for (uint16_t i = 0; i < total; i += 1) {
        if (entryOffset > length || length - entryOffset < 46 ||
            YLReadUInt32(bytes, entryOffset, length) != 0x02014b50) {
            break;
        }
        uint16_t flags = YLReadUInt16(bytes, entryOffset + 8, length);
        uint16_t method = YLReadUInt16(bytes, entryOffset + 10, length);
        uint32_t compressed = YLReadUInt32(bytes, entryOffset + 20, length);
        uint32_t uncompressed = YLReadUInt32(bytes, entryOffset + 24, length);
        uint16_t nameLength = YLReadUInt16(bytes, entryOffset + 28, length);
        uint16_t extraLength = YLReadUInt16(bytes, entryOffset + 30, length);
        uint16_t commentLength = YLReadUInt16(bytes, entryOffset + 32, length);
        uint32_t localOffset = YLReadUInt32(bytes, entryOffset + 42, length);

        if (length - entryOffset - 46 < nameLength) {
            break;
        }
        NSData *nameData = [data subdataWithRange:NSMakeRange(entryOffset + 46, nameLength)];
        NSString *name;
        if (flags & 0x0800) {
            name = [[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];
        } else {
            name = [YLUtil decodeData:nameData];
        }
        if (!name.length) {
            name = [[NSString alloc] initWithData:nameData encoding:NSISOLatin1StringEncoding] ?: @"";
        }

        if (name.length && compressed != 0xFFFFFFFF && localOffset != 0xFFFFFFFF) {
            entries[name] = @{
                @"name": name,
                @"method": @(method),
                @"compressed": @(compressed),
                @"uncompressed": @(uncompressed),
                @"offset": @(localOffset)
            };
        }
        entryOffset += (NSUInteger)46 + nameLength + extraLength + commentLength;
    }
    return @{@"data": data, @"entries": entries};
}

+ (NSArray *)entryNamesAtPath:(NSString *)path {
    NSDictionary *archive = [self readEntriesAtPath:path error:NULL];
    if (!archive) {
        return @[];
    }
    return [[archive[@"entries"] allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSData *)inflate:(NSData *)data expected:(NSUInteger)expected error:(NSError **)error {
    // 防止压缩炸弹把 4S 的内存吃光
    static const NSUInteger kMaxInflateSize = 64 * 1024 * 1024;
    if (expected > kMaxInflateSize) {
        if (error) { *error = YLMakingError(@"解压后文件过大"); }
        return nil;
    }
    NSUInteger capacity = expected > 0 ? expected : MAX(data.length * 4, (NSUInteger)65536);
    NSMutableData *output = [NSMutableData dataWithLength:capacity];
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    int status = inflateInit2(&stream, -MAX_WBITS);
    if (status != Z_OK) {
        if (error) { *error = YLMakingError(@"zlib 初始化失败"); }
        return nil;
    }
    stream.next_in = (Bytef *)data.bytes;
    stream.avail_in = (uInt)data.length;
    stream.next_out = (Bytef *)output.mutableBytes;
    stream.avail_out = (uInt)output.length;

    do {
        if (stream.total_out > kMaxInflateSize) {
            inflateEnd(&stream);
            if (error) { *error = YLMakingError(@"解压后文件过大"); }
            return nil;
        }
        if (stream.avail_out == 0) {
            NSUInteger used = output.length;
            [output increaseLengthBy:65536];
            stream.next_out = (Bytef *)output.mutableBytes + used;
            stream.avail_out = 65536;
        }
        status = inflate(&stream, Z_NO_FLUSH);
    } while (status == Z_OK);

    NSUInteger produced = stream.total_out;
    inflateEnd(&stream);
    if (status != Z_STREAM_END) {
        if (error) { *error = YLMakingError(@"解压失败"); }
        return nil;
    }
    output.length = produced;
    return output;
}

+ (NSData *)dataForEntry:(NSString *)entry
               inArchive:(NSString *)path
                   error:(NSError **)error {
    NSDictionary *archive = [self readEntriesAtPath:path error:error];
    if (!archive) {
        return nil;
    }
    NSDictionary *info = archive[@"entries"][entry];
    if (!info) {
        if (error) { *error = YLMakingError([NSString stringWithFormat:@"zip 中没有 %@", entry]); }
        return nil;
    }
    NSData *data = archive[@"data"];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger length = data.length;
    NSUInteger offset = [info[@"offset"] unsignedIntegerValue];
    if (offset > length || length - offset < 30 ||
        YLReadUInt32(bytes, offset, length) != 0x04034b50) {
        if (error) { *error = YLMakingError(@"zip 本地头损坏"); }
        return nil;
    }
    uint16_t nameLength = YLReadUInt16(bytes, offset + 26, length);
    uint16_t extraLength = YLReadUInt16(bytes, offset + 28, length);
    NSUInteger start = offset + 30 + nameLength + extraLength;
    NSUInteger compressed = [info[@"compressed"] unsignedIntegerValue];
    if (start > length || length - start < compressed) {
        if (error) { *error = YLMakingError(@"zip 数据越界"); }
        return nil;
    }
    NSData *payload = [data subdataWithRange:NSMakeRange(start, compressed)];
    uint16_t method = (uint16_t)[info[@"method"] unsignedIntegerValue];
    if (method == 0) {
        return payload;
    }
    if (method == 8) {
        NSUInteger expected = [info[@"uncompressed"] unsignedIntegerValue];
        return [self inflate:payload expected:expected error:error];
    }
    if (error) {
        *error = YLMakingError([NSString stringWithFormat:@"不支持的压缩方式 %u", method]);
    }
    return nil;
}

@end
