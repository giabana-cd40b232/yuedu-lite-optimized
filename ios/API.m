#import "API.h"
#import "EngineBridge.h"
#import "YLUtil.h"

@interface API ()
@property (nonatomic, strong) dispatch_queue_t queue;
- (void)fail:(APICompletion)completion message:(NSString *)message;
@end

@implementation API

+ (instancetype)shared {
    static API *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[API alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.local.yuedulite.api", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - engine

- (void)callAction:(NSString *)action
            params:(NSDictionary *)params
        completion:(APICompletion)completion {
    NSDictionary *clean = [params isKindOfClass:[NSDictionary class]] ? params : @{};
    dispatch_async(self.queue, ^{
        NSString *json = [[EngineBridge shared] callAction:action params:clean];
        id parsed = [YLUtil jsonObject:json];
        NSDictionary *result = [parsed isKindOfClass:[NSDictionary class]] ? parsed : nil;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!completion) {
                return;
            }
            if (!result) {
                completion(nil, [NSError errorWithDomain:@"yuedu" code:1
                    userInfo:@{NSLocalizedDescriptionKey: @"引擎返回无法解析"}]);
                return;
            }
            id message = result[@"error"];
            if (message && message != [NSNull null]) {
                completion(nil, [NSError errorWithDomain:@"yuedu" code:2
                    userInfo:@{NSLocalizedDescriptionKey: [message description]}]);
                return;
            }
            completion(result, nil);
        });
    });
}

- (void)fail:(APICompletion)completion message:(NSString *)message {
    if (completion) {
        completion(nil, [NSError errorWithDomain:@"yuedu" code:3
            userInfo:@{NSLocalizedDescriptionKey: message ?: @"未知错误"}]);
    }
}

#pragma mark - old-style paths

- (void)get:(NSString *)path query:(NSDictionary *)query completion:(APICompletion)completion {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    for (NSString *key in query) {
        id value = query[key];
        if (value != nil && value != [NSNull null]) {
            params[key] = value;
        }
    }

    NSString *action = nil;
    if ([path isEqualToString:@"/api/ping"]) {
        action = @"ping";
    } else if ([path isEqualToString:@"/api/sources"]) {
        action = @"sources.list";
    } else if ([path isEqualToString:@"/api/shelf"]) {
        action = @"shelf.list";
    } else if ([path isEqualToString:@"/api/search"]) {
        action = @"search";
    } else if ([path isEqualToString:@"/api/book"]) {
        action = @"book.info";
    } else if ([path isEqualToString:@"/api/toc"]) {
        action = @"toc";
    } else if ([path isEqualToString:@"/api/content"]) {
        action = @"content";
    } else if ([path isEqualToString:@"/api/progress"]) {
        action = @"progress.get";
    } else if ([path isEqualToString:@"/api/cloud/books"]) {
        action = @"cloud.list";
    } else if ([path isEqualToString:@"/api/settings"]) {
        action = @"settings.get";
    } else if ([path isEqualToString:@"/api/webdav/config"]) {
        action = @"webdav.config";
    } else if ([path isEqualToString:@"/api/store"]) {
        action = @"store.get";
    } else if ([path isEqualToString:@"/api/export/legado"]) {
        action = @"export.legado";
    }

    if (!action) {
        [self fail:completion message:[NSString stringWithFormat:@"未知接口: %@", path]];
        return;
    }
    [self callAction:action params:params completion:completion];
}

- (void)post:(NSString *)path body:(NSDictionary *)body completion:(APICompletion)completion {
    NSDictionary *params = [body isKindOfClass:[NSDictionary class]] ? body : @{};
    NSString *action = nil;

    if ([path isEqualToString:@"/api/sources"]) {
        action = @"sources.save";
    } else if ([path isEqualToString:@"/api/shelf"]) {
        NSDictionary *book = params[@"book"];
        if ([book isKindOfClass:[NSDictionary class]]) {
            params = @{@"book": book};
        }
        action = @"shelf.add";
    } else if ([path isEqualToString:@"/api/shelf/remove"]) {
        action = @"shelf.remove";
    } else if ([path isEqualToString:@"/api/progress"]) {
        action = @"progress.save";
    } else if ([path isEqualToString:@"/api/sync/pull"]) {
        action = @"sync.pull";
    } else if ([path isEqualToString:@"/api/sync/push"]) {
        action = @"sync.push";
    } else if ([path isEqualToString:@"/api/sync/pullBook"]) {
        action = @"sync.pullBook";
    } else if ([path isEqualToString:@"/api/sync/pushBook"]) {
        action = @"sync.pushBook";
    } else if ([path isEqualToString:@"/api/sync/test"]) {
        action = @"sync.test";
    } else if ([path isEqualToString:@"/api/cloud/fetch"]) {
        action = @"cloud.fetch";
    } else if ([path isEqualToString:@"/api/cloud/import"]) {
        action = @"cloud.import";
    } else if ([path isEqualToString:@"/api/settings"]) {
        action = @"settings.save";
    } else if ([path isEqualToString:@"/api/store/root"]) {
        action = @"store.setRoot";
    } else if ([path isEqualToString:@"/api/local/import"]) {
        action = @"local.import";
    } else if ([path isEqualToString:@"/api/local/importPath"]) {
        action = @"local.importPath";
    } else if ([path isEqualToString:@"/api/backup/importPath"]) {
        action = @"backup.importPath";
    } else if ([path isEqualToString:@"/api/inbox/scan"]) {
        action = @"inbox.scan";
    } else if ([path isEqualToString:@"/api/cache/clear"]) {
        action = @"cache.clear";
    } else if ([path isEqualToString:@"/api/stats/add"]) {
        action = @"stats.add";
    } else if ([path isEqualToString:@"/api/cache/info"]) {
        action = @"cache.info";
    } else if ([path isEqualToString:@"/api/stats"]) {
        action = @"stats.get";
    } else if ([path isEqualToString:@"/api/bookmark/list"]) {
        action = @"bookmark.list";
    } else if ([path isEqualToString:@"/api/bookmark/add"]) {
        action = @"bookmark.add";
    } else if ([path isEqualToString:@"/api/bookmark/remove"]) {
        action = @"bookmark.remove";
    } else if ([path isEqualToString:@"/api/bookmark/clear"]) {
        action = @"bookmark.clear";
    }

    if (!action) {
        [self fail:completion message:[NSString stringWithFormat:@"未知接口: %@", path]];
        return;
    }
    [self callAction:action params:params completion:completion];
}

@end
