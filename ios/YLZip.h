#import <Foundation/Foundation.h>

/** 极简 ZIP 读取器（store / deflate），够读 EPUB 和阅读备份 zip。 */
@interface YLZip : NSObject

+ (NSArray *)entryNamesAtPath:(NSString *)path;
+ (NSData *)dataForEntry:(NSString *)entry
               inArchive:(NSString *)path
                   error:(NSError **)error;

@end
