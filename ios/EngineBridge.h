#import <Foundation/Foundation.h>

/**
 * JavaScriptCore 桥：
 *  - 加载 engine-core.js + engine.js
 *  - 提供 YLNative（网络 / 文件 / 编码 / ZIP）
 *  - 串行执行，避免多线程同时改 JSON 存储
 */
@interface EngineBridge : NSObject

+ (instancetype)shared;

/** 同步调用；会切到引擎自己的串行队列。返回引擎的 JSON 字符串。 */
- (NSString *)callAction:(NSString *)action params:(NSDictionary *)params;

@end
