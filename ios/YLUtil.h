#import <Foundation/Foundation.h>

@interface YLUtil : NSObject

/** 按 BOM / <meta charset> / UTF-8 / GB18030 / Big5 的顺序尝试解码。 */
+ (NSString *)decodeData:(NSData *)data;
+ (NSString *)decodeData:(NSData *)data charset:(NSString *)charset;

+ (NSString *)base64Encode:(NSString *)text;
+ (NSString *)base64Decode:(NSString *)text;
+ (NSString *)md5:(NSString *)text;

+ (NSString *)jsonString:(id)object;
+ (id)jsonObject:(NSString *)text;

+ (BOOL)writeJSON:(id)object toFile:(NSString *)path;

@end
