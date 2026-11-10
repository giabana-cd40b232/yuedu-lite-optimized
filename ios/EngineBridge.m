#import "EngineBridge.h"
#import "YLFontManager.h"
#import "YLStore.h"
#import "YLUtil.h"
#import "YLZip.h"
#import <JavaScriptCore/JavaScriptCore.h>

static void *kEngineQueueKey = &kEngineQueueKey;

static NSString *YLDocumentsPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.firstObject ?: NSTemporaryDirectory();
}

static NSNumber *YLNumber(BOOL value) {
    return value ? @YES : @NO;
}

static NSString *YLJSONError(NSString *message) {
    return [YLUtil jsonString:@{@"error": message ?: @"未知错误"}];
}

static NSString *YLString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if (value == nil || value == [NSNull null]) {
        return @"";
    }
    return [value description] ?: @"";
}

static void YLEnsureParent(NSString *path) {
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
}

// iOS 9.3.6 自带的根证书库比较旧：Let's Encrypt（ISRG Root X1）、
// 部分商业 CA 的交叉签名、以及自签证书都会被系统判成“服务器证书无效”，
// 导致 WebDAV 同步完全连不上。这里对服务器信任评估直接放行。
@interface YLTrustDelegate : NSObject <NSURLSessionDelegate>
@end

@implementation YLTrustDelegate

- (void)URLSession:(NSURLSession *)session
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition,
                                  NSURLCredential *))completionHandler {
    NSString *method = challenge.protectionSpace.authenticationMethod;
    if ([method isEqualToString:NSURLAuthenticationMethodServerTrust] &&
        challenge.protectionSpace.serverTrust != NULL) {
        completionHandler(NSURLSessionAuthChallengeUseCredential,
            [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
        return;
    }
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

@end

static NSURLSession *YLHTTPSession(void) {
    static NSURLSession *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 60;
        config.timeoutIntervalForResource = 300;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        config.HTTPShouldUsePipelining = NO;
        YLTrustDelegate *delegate = [[YLTrustDelegate alloc] init];
        session = [NSURLSession sessionWithConfiguration:config
                                               delegate:delegate
                                          delegateQueue:nil];
    });
    return session;
}

static NSString *YLFetch(NSString *url, NSString *optionsJSON) {
    NSDictionary *options = [YLUtil jsonObject:optionsJSON];
    if (![options isKindOfClass:[NSDictionary class]]) {
        options = @{};
    }
    NSURL *target = [NSURL URLWithString:YLString(url)];
    if (!target) {
        // 中文文件名 / 空格等未编码字符：只在原始字符串解析失败时补编码，
        // 避免对已经 %E4%.. 形式编码过的 URL 二次编码。
        NSString *escaped = [YLString(url) stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet URLQueryAllowedCharacterSet]];
        target = escaped ? [NSURL URLWithString:escaped] : nil;
    }
    if (!target) {
        return YLJSONError(@"URL 不合法");
    }

    double timeout = [options[@"timeout"] doubleValue];
    if (timeout <= 0) { timeout = 30.0; }
    BOOL binary = [options[@"binary"] boolValue];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:target];
    request.timeoutInterval = timeout;
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    request.HTTPMethod = YLString(options[@"method"]).length
        ? [YLString(options[@"method"]) uppercaseString] : @"GET";

    NSDictionary *headers = options[@"headers"];
    BOOL hasUserAgent = NO;
    if ([headers isKindOfClass:[NSDictionary class]]) {
        for (NSString *name in headers) {
            NSString *value = YLString(headers[name]);
            [request setValue:value forHTTPHeaderField:name];
            if ([name caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame) {
                hasUserAgent = YES;
            }
        }
    }
    if (!hasUserAgent) {
        [request setValue:@"yuedu-lite/1.5 (iPhone; iOS)"
       forHTTPHeaderField:@"User-Agent"];
    }

    id body = options[@"body"];
    if (body != nil && body != [NSNull null]) {
        NSString *text = [body isKindOfClass:[NSString class]]
            ? body : [YLUtil jsonString:body];
        request.HTTPBody = [text dataUsingEncoding:NSUTF8StringEncoding];
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *responseData = nil;
    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSError *responseError = nil;

    NSURLSession *session = YLHTTPSession();
    NSURLSessionDataTask *task =
        [session dataTaskWithRequest:request
                  completionHandler:^(NSData *data,
                                      NSURLResponse *response,
                                      NSError *error) {
        responseData = data;
        responseError = error;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            httpResponse = (NSHTTPURLResponse *)response;
        }
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];

    long waited = dispatch_semaphore_wait(semaphore,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 15.0) * NSEC_PER_SEC)));
    if (waited != 0) {
        [task cancel];
        return YLJSONError(@"请求超时");
    }
    if (responseError) {
        return YLJSONError(responseError.localizedDescription ?: @"网络请求失败");
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"ok"] = @YES;
    result[@"status"] = @(httpResponse ? httpResponse.statusCode : 0);
    NSDictionary *responseHeaders = httpResponse.allHeaderFields ?: @{};
    NSMutableDictionary *cleanHeaders = [NSMutableDictionary dictionary];
    for (id key in responseHeaders) {
        cleanHeaders[YLString(key)] = YLString(responseHeaders[key]);
    }
    result[@"headers"] = cleanHeaders;

    NSData *data = responseData ?: [NSData data];
    if (binary) {
        result[@"base64"] = [data base64EncodedStringWithOptions:0] ?: @"";
    } else {
        result[@"text"] = [YLUtil decodeData:data];
    }
    return [YLUtil jsonString:result];
}

// 直接把响应体落到文件：EPUB / 备份包动辄几 MB，走 base64 在 JS 里来回搬运
// 会占满 iPhone 4S 的内存并导致下载失败，这里用 NSURLSessionDownloadTask 流式写盘。
static NSString *YLDownloadToFile(NSString *url, NSString *optionsJSON, NSString *destination) {
    NSDictionary *options = [YLUtil jsonObject:optionsJSON];
    if (![options isKindOfClass:[NSDictionary class]]) { options = @{}; }

    NSString *text = YLString(url);
    NSURL *target = [NSURL URLWithString:text];
    if (!target) {
        NSString *escaped = [text stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet URLQueryAllowedCharacterSet]];
        target = escaped ? [NSURL URLWithString:escaped] : nil;
    }
    if (!target) { return YLJSONError(@"URL 不合法"); }

    double timeout = [options[@"timeout"] doubleValue];
    if (timeout <= 0) { timeout = 180.0; }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:target];
    request.timeoutInterval = timeout;
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    request.HTTPMethod = @"GET";

    NSDictionary *headers = options[@"headers"];
    if ([headers isKindOfClass:[NSDictionary class]]) {
        for (NSString *name in headers) {
            [request setValue:YLString(headers[name]) forHTTPHeaderField:name];
        }
    }

    NSString *path = YLString(destination);
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSInteger status = 0;
    __block NSError *responseError = nil;
    __block unsigned long long size = 0;

    NSURLSessionDownloadTask *task = [YLHTTPSession() downloadTaskWithRequest:request
        completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error) {
            responseError = error;
        } else {
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                status = [(NSHTTPURLResponse *)response statusCode];
            }
            if (location) {
                NSFileManager *manager = [NSFileManager defaultManager];
                YLEnsureParent(path);
                [manager removeItemAtPath:path error:NULL];
                NSError *moveError = nil;
                if ([manager moveItemAtURL:location
                                     toURL:[NSURL fileURLWithPath:path]
                                     error:&moveError]) {
                    NSDictionary *attributes = [manager attributesOfItemAtPath:path
                                                                          error:NULL];
                    size = [attributes[NSFileSize] unsignedLongLongValue];
                } else {
                    responseError = moveError;
                }
            }
        }
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];

    long waited = dispatch_semaphore_wait(semaphore,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 20.0) * NSEC_PER_SEC)));
    if (waited != 0) {
        [task cancel];
        return YLJSONError(@"下载超时");
    }
    if (responseError) {
        return YLJSONError(responseError.localizedDescription ?: @"下载失败");
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"ok"] = @YES;
    result[@"status"] = @(status);
    result[@"size"] = @(size);
    result[@"path"] = path;
    return [YLUtil jsonString:result];
}

@interface EngineBridge ()
@property (nonatomic, strong) JSContext *context;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation EngineBridge

+ (instancetype)shared {
    static EngineBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[EngineBridge alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.local.yuedulite.engine", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_queue, kEngineQueueKey, (__bridge void *)self, NULL);
        dispatch_sync(_queue, ^{
            [self setupContext];
        });
    }
    return self;
}

#pragma mark - setup

- (BOOL)evaluateScriptNamed:(NSString *)name {
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"js"];
    if (!path) {
        NSLog(@"[engine] 找不到 %@.js", name);
        return NO;
    }
    NSString *source = [NSString stringWithContentsOfFile:path
                                                 encoding:NSUTF8StringEncoding
                                                    error:NULL];
    if (!source.length) {
        NSLog(@"[engine] 读取 %@.js 失败", name);
        return NO;
    }
    [self.context evaluateScript:source withSourceURL:[NSURL fileURLWithPath:path]];
    if (self.context.exception) {
        NSLog(@"[engine] %@.js 出错: %@", name, self.context.exception);
        self.context.exception = nil;
        return NO;
    }
    return YES;
}

- (void)setupContext {
    self.context = [[JSContext alloc] init];
    __weak EngineBridge *weakSelf = self;
    self.context.exceptionHandler = ^(JSContext *context, JSValue *exception) {
        NSLog(@"[engine] JS 异常: %@", exception);
        context.exception = nil;
    };

    JSValue *native = [JSValue valueWithNewObjectInContext:self.context];

    native[@"docsDir"] = ^NSString *(void) {
        return YLDocumentsPath();
    };
    native[@"storeRoot"] = ^NSString *(void) {
        return [YLStore shared].rootPath ?: @"";
    };
    native[@"booksDir"] = ^NSString *(void) {
        return [YLStore shared].booksPath ?: @"";
    };
    native[@"fontsDir"] = ^NSString *(void) {
        return [YLStore shared].fontsPath ?: @"";
    };
    native[@"inboxDir"] = ^NSString *(void) {
        return [YLStore shared].inboxPath ?: @"";
    };
    native[@"coversDir"] = ^NSString *(void) {
        return [YLStore shared].coversPath ?: @"";
    };
    native[@"setStoreRoot"] = ^NSString *(NSString *path) {
        YLStore *store = [YLStore shared];
        NSString *reason = nil;
        if (![store setRootPath:YLString(path) error:&reason]) {
            return [YLUtil jsonString:@{
                @"ok": @NO,
                @"error": reason ?: @"无法使用该目录"
            }];
        }
        return [YLUtil jsonString:@{
            @"ok": @YES,
            @"root": store.rootPath ?: @"",
            @"booksDir": store.booksPath ?: @"",
            @"fontsDir": store.fontsPath ?: @"",
            @"inboxDir": store.inboxPath ?: @"",
            @"coversDir": store.coversPath ?: @""
        }];
    };
    native[@"fonts"] = ^NSString *(void) {
        return [YLUtil jsonString:[[YLFontManager shared] fonts] ?: @[]];
    };
    native[@"reloadFonts"] = ^{
        [[YLFontManager shared] reload];
    };
    native[@"readText"] = ^NSString *(NSString *path) {
        NSString *text = [NSString stringWithContentsOfFile:YLString(path)
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL];
        return text ?: @"";
    };
    // 本地/云端 TXT 直接在本机解码，避免把整本书 base64 搬进 JS，
    // iPhone 4S 上大文件很容易因此被系统杀掉。
    native[@"readTextFile"] = ^NSString *(NSString *path) {
        NSData *data = [NSData dataWithContentsOfFile:YLString(path)];
        if (!data) { return nil; }
        return [YLUtil decodeData:data] ?: @"";
    };
    native[@"writeText"] = ^NSNumber *(NSString *path, NSString *text) {
        YLEnsureParent(YLString(path));
        NSData *data = [YLString(text) dataUsingEncoding:NSUTF8StringEncoding];
        return YLNumber([data writeToFile:YLString(path) atomically:YES]);
    };
    native[@"readBase64"] = ^NSString *(NSString *path) {
        NSData *data = [NSData dataWithContentsOfFile:YLString(path)];
        return data ? [data base64EncodedStringWithOptions:0] : @"";
    };
    native[@"writeBase64"] = ^NSNumber *(NSString *path, NSString *base64) {
        YLEnsureParent(YLString(path));
        NSData *data = [[NSData alloc] initWithBase64EncodedString:YLString(base64)
                                                           options:NSDataBase64DecodingIgnoreUnknownCharacters];
        if (!data) { return @NO; }
        return YLNumber([data writeToFile:YLString(path) atomically:YES]);
    };
    native[@"exists"] = ^NSNumber *(NSString *path) {
        return YLNumber([[NSFileManager defaultManager] fileExistsAtPath:YLString(path)]);
    };
    native[@"remove"] = ^NSNumber *(NSString *path) {
        NSError *error = nil;
        BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:YLString(path) error:&error];
        return YLNumber(ok || error.code == NSFileNoSuchFileError);
    };
    native[@"mkdir"] = ^NSNumber *(NSString *path) {
        NSError *error = nil;
        BOOL ok = [[NSFileManager defaultManager] createDirectoryAtPath:YLString(path)
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&error];
        return YLNumber(ok || error.code == NSFileWriteFileExistsError);
    };
    native[@"listDir"] = ^NSString *(NSString *path) {
        NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:YLString(path)
                                                                             error:NULL];
        return [YLUtil jsonString:names ?: @[]];
    };
    native[@"fileSize"] = ^NSNumber *(NSString *path) {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:YLString(path)
                                                                                    error:NULL];
        return attributes[NSFileSize] ?: @0;
    };
    native[@"fetch"] = ^NSString *(NSString *url, NSString *options) {
        return YLFetch(url, options);
    };
    native[@"downloadTo"] = ^NSString *(NSString *url, NSString *options, NSString *path) {
        return YLDownloadToFile(url, options, path);
    };
    native[@"copy"] = ^NSNumber *(NSString *from, NSString *to) {
        YLEnsureParent(YLString(to));
        NSFileManager *manager = [NSFileManager defaultManager];
        [manager removeItemAtPath:YLString(to) error:NULL];
        return YLNumber([manager copyItemAtPath:YLString(from)
                                          toPath:YLString(to)
                                           error:NULL]);
    };
    native[@"base64Encode"] = ^NSString *(NSString *text) {
        return [YLUtil base64Encode:YLString(text)];
    };
    native[@"base64Decode"] = ^NSString *(NSString *text) {
        return [YLUtil base64Decode:YLString(text)];
    };
    native[@"decodeText"] = ^NSString *(NSString *base64) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:YLString(base64)
                                                           options:NSDataBase64DecodingIgnoreUnknownCharacters];
        return data ? [YLUtil decodeData:data] : @"";
    };
    native[@"md5"] = ^NSString *(NSString *text) {
        return [YLUtil md5:YLString(text)];
    };
    native[@"zipList"] = ^NSString *(NSString *path) {
        return [YLUtil jsonString:[YLZip entryNamesAtPath:YLString(path)]];
    };
    native[@"zipReadText"] = ^NSString *(NSString *path, NSString *entry) {
        NSData *data = [YLZip dataForEntry:YLString(entry) inArchive:YLString(path) error:NULL];
        return data ? [YLUtil decodeData:data] : @"";
    };
    native[@"zipReadBase64"] = ^NSString *(NSString *path, NSString *entry) {
        NSData *data = [YLZip dataForEntry:YLString(entry) inArchive:YLString(path) error:NULL];
        return data ? [data base64EncodedStringWithOptions:0] : @"";
    };
    native[@"now"] = ^NSNumber *(void) {
        return @([[NSDate date] timeIntervalSince1970] * 1000.0);
    };
    native[@"defer"] = ^(double seconds, JSValue *callback) {
        if (!callback || callback.isUndefined || callback.isNull) { return; }
        dispatch_queue_t queue = weakSelf.queue;
        if (!queue) { return; }
        int64_t delay = (int64_t)(MAX(0.0, seconds) * NSEC_PER_SEC);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay), queue, ^{
            if (callback.isUndefined || callback.isNull) { return; }
            [callback callWithArguments:@[]];
        });
    };
    native[@"log"] = ^(NSString *text) {
        NSLog(@"[engine] %@", YLString(text));
    };

    self.context[@"YLNative"] = native;

    BOOL coreReady = [self evaluateScriptNamed:@"engine-core"];
    BOOL engineReady = [self evaluateScriptNamed:@"engine"];
    if (!coreReady || !engineReady) {
        NSLog(@"[engine] 初始化失败 core=%d engine=%d", coreReady, engineReady);
    } else {
        JSValue *yl = self.context[@"YL"];
        NSLog(@"[engine] 已就绪: %@", [yl[@"version"] toString]);
    }
}

#pragma mark - call

- (NSString *)performAction:(NSString *)action params:(NSDictionary *)params {
    if (!self.context) {
        return YLJSONError(@"引擎未初始化");
    }
    JSValue *yl = self.context[@"YL"];
    JSValue *handle = yl[@"handle"];
    if (handle.isUndefined || handle.isNull) {
        return YLJSONError(@"引擎未加载");
    }
    NSString *paramsJSON = [YLUtil jsonString:[params isKindOfClass:[NSDictionary class]]
        ? params : @{}];
    self.context.exception = nil;
    JSValue *value = [handle callWithArguments:@[action ?: @"", paramsJSON]];
    if (self.context.exception) {
        NSString *message = [self.context.exception toString];
        self.context.exception = nil;
        return YLJSONError(message.length ? message : @"引擎异常");
    }
    if (value.isUndefined || value.isNull) {
        return YLJSONError(@"引擎无返回");
    }
    return [value toString] ?: YLJSONError(@"引擎返回异常");
}

- (NSString *)callAction:(NSString *)action params:(NSDictionary *)params {
    __block NSString *output = nil;
    void (^work)(void) = ^{
        output = [self performAction:action params:params];
    };
    if (dispatch_get_specific(kEngineQueueKey)) {
        work();
    } else {
        dispatch_sync(self.queue, work);
    }
    return output ?: YLJSONError(@"引擎调用失败");
}

@end
