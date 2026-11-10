#import <Foundation/Foundation.h>

typedef void (^APICompletion)(id result, NSError *error);

/**
 * 本地 API：路径与原来服务端的 /api/... 保持一致，但全部在手机内执行。
 * ViewController 不需要知道引擎的存在。
 */
@interface API : NSObject

+ (instancetype)shared;

/** 直接调用引擎动作（设置页等新代码用）。 */
- (void)callAction:(NSString *)action
            params:(NSDictionary *)params
        completion:(APICompletion)completion;

- (void)get:(NSString *)path query:(NSDictionary *)query completion:(APICompletion)completion;
- (void)post:(NSString *)path body:(NSDictionary *)body completion:(APICompletion)completion;

@end
