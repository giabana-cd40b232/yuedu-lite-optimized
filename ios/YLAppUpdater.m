#import "YLAppUpdater.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <math.h>
#import <signal.h>
#import <spawn.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>

extern char **environ;

// iOS 9.3.6 根证书库旧，GitHub / 自签证书都可能校验失败，直接放行服务器信任。
@interface YLUpdaterTrustDelegate : NSObject <NSURLSessionDelegate>
@end

@implementation YLUpdaterTrustDelegate

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

@interface YLAppUpdater ()
+ (void)checkSources:(NSArray *)sources index:(NSInteger)index lastError:(NSError *)lastError completion:(void (^)(NSDictionary *, NSError *))completion;
+ (NSString *)tagFromUrl:(NSString *)url;
+ (NSString *)latestTagFromHtml:(NSString *)html repo:(NSString *)repo;
+ (NSString *)ipaAssetUrlFromHtml:(NSString *)html host:(NSString *)host repo:(NSString *)repo;
+ (NSString *)buildFromHtml:(NSString *)html tag:(NSString *)tag;
+ (BOOL)installPackageAtPath:(NSString *)path error:(NSError **)error;
@end

// 主仓库 (GitHub)；Gitee 镜像可能在不同 owner 下（如导入到个人账号）
static NSArray *YLUpdateSources(void) {
    return @[
        @{@"host": @"https://gitee.com",  @"repo": @"jyz2574461147/yuedu-lite"},
        @{@"host": @"https://gitee.com",  @"repo": @"Daniel123999/yuedu-lite"},
        @{@"host": @"https://github.com", @"repo": @"Daniel123999/yuedu-lite"}
    ];
}

static NSURLSession *YLUpdaterSession(void) {
    static NSURLSession *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 25;
        config.timeoutIntervalForResource = 300;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        session = [NSURLSession sessionWithConfiguration:config
                                                delegate:[[YLUpdaterTrustDelegate alloc] init]
                                           delegateQueue:nil];
    });
    return session;
}

#pragma mark - 传输进度

// iOS 9 没有 block 版 NSTimer，用 target/selector 轮询 task 的字节数。
@interface YLTransferProgress : NSObject
@property (nonatomic, weak) NSURLSessionTask *task;
@property (nonatomic, copy) void (^handler)(double);
@property (nonatomic, assign) BOOL upload;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation YLTransferProgress

- (void)start {
    self.timer = [NSTimer timerWithTimeInterval:0.25 target:self
                                        selector:@selector(tick:)
                                        userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)tick:(NSTimer *)timer {
    NSURLSessionTask *task = self.task;
    if (!task) { [self stop]; return; }
    int64_t expected = self.upload ? task.countOfBytesExpectedToSend
                                   : task.countOfBytesExpectedToReceive;
    int64_t done = self.upload ? task.countOfBytesSent : task.countOfBytesReceived;
    if (expected > 0 && self.handler) {
        double fraction = (double)done / (double)expected;
        if (fraction < 0) { fraction = 0; }
        if (fraction > 1) { fraction = 1; }
        self.handler(fraction);
    }
}

@end

#pragma mark - 本机安装

// 运行可执行文件并等待结束（最多 120 秒），捕获 stdout/stderr。
static BOOL YLRunAndWait(NSString *executable, NSArray *arguments,
                         NSString **output, NSInteger *exitCode) {
    if (!executable.length ||
        ![[NSFileManager defaultManager] isExecutableFileAtPath:executable]) {
        return NO;
    }
    int fds[2];
    if (pipe(fds) != 0) { return NO; }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, fds[0]);
    posix_spawn_file_actions_addclose(&actions, fds[1]);

    NSMutableArray *all = [NSMutableArray arrayWithObject:executable];
    [all addObjectsFromArray:arguments ?: @[]];
    char **argv = (char **)calloc(all.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < all.count; i += 1) {
        argv[i] = strdup([[all[i] description] UTF8String]);
    }
    argv[all.count] = NULL;

    pid_t pid = 0;
    int spawnResult = posix_spawn(&pid, [executable fileSystemRepresentation],
                                  &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(fds[1]);
    for (NSUInteger i = 0; i < all.count; i += 1) { free(argv[i]); }
    free(argv);

    if (spawnResult != 0) {
        close(fds[0]);
        if (output) {
            *output = [NSString stringWithFormat:
                @"posix_spawn(%@) = %d", executable, spawnResult];
        }
        if (exitCode) { *exitCode = -1; }
        return NO;
    }

    int status = 0;
    BOOL exited = NO;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120.0];
    while ([deadline timeIntervalSinceNow] > 0) {
        pid_t waited = waitpid(pid, &status, WNOHANG);
        if (waited == pid) { exited = YES; break; }
        if (waited < 0 && errno != EINTR) { break; }
        usleep(120000);
    }
    if (!exited) {
        kill(pid, SIGKILL);
        waitpid(pid, &status, 0);
    }

    NSMutableData *data = [NSMutableData data];
    char buffer[1024];
    ssize_t got = 0;
    while ((got = read(fds[0], buffer, sizeof(buffer))) > 0) {
        [data appendBytes:buffer length:(NSUInteger)got];
    }
    close(fds[0]);

    if (output) {
        *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    }
    if (exitCode) {
        *exitCode = (exited && WIFEXITED(status)) ? WEXITSTATUS(status) : -1;
    }
    return YES;
}

// 启动后不等待（用于退出前拉起重启脚本）。
static BOOL YLSpawnDetached(NSString *executable, NSArray *arguments) {
    if (!executable.length ||
        ![[NSFileManager defaultManager] isExecutableFileAtPath:executable]) {
        return NO;
    }
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    NSMutableArray *all = [NSMutableArray arrayWithObject:executable];
    [all addObjectsFromArray:arguments ?: @[]];
    char **argv = (char **)calloc(all.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < all.count; i += 1) {
        argv[i] = strdup([[all[i] description] UTF8String]);
    }
    argv[all.count] = NULL;

    pid_t pid = 0;
    int spawnResult = posix_spawn(&pid, [executable fileSystemRepresentation],
                                  &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    for (NSUInteger i = 0; i < all.count; i += 1) { free(argv[i]); }
    free(argv);
    return spawnResult == 0;
}

typedef int (*YLMIInstallFunction)(CFStringRef, CFDictionaryRef, void *, void *);

@interface YLLSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)installApplication:(NSURL *)url withOptions:(NSDictionary *)options;
@end

// iOS 9 上 MobileInstallation 仍然可用，Filza 等工具也走这个接口。
static int YLInstallWithMobileInstallation(NSString *path) {
    static void *handle = NULL;
    static YLMIInstallFunction installFunction = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/"
                        "MobileInstallation.framework/MobileInstallation",
                        RTLD_LAZY);
        if (handle) {
            installFunction = (YLMIInstallFunction)dlsym(handle,
                "MobileInstallationInstall");
        }
    });
    if (!installFunction) { return -404; }

    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSDictionary *options = @{
        @"ApplicationType": @"User",
        @"BundleIdentifier": bundleId,
        @"IsUserInitiated": @YES
    };
    return installFunction((__bridge CFStringRef)path,
                           (__bridge CFDictionaryRef)options, NULL, NULL);
}

static NSInteger YLCompareVersion(NSString *a, NSString *b) {
    NSArray *left = [(a ?: @"") componentsSeparatedByString:@"."];
    NSArray *right = [(b ?: @"") componentsSeparatedByString:@"."];
    NSInteger count = MAX((NSInteger)left.count, (NSInteger)right.count);
    for (NSInteger i = 0; i < count; i += 1) {
        NSInteger x = i < (NSInteger)left.count ? [left[i] integerValue] : 0;
        NSInteger y = i < (NSInteger)right.count ? [right[i] integerValue] : 0;
        if (x != y) { return x > y ? 1 : -1; }
    }
    return 0;
}

@implementation YLAppUpdater

+ (void)checkForUpdateWithCompletion:(void (^)(NSDictionary *, NSError *))completion {
    [self checkSources:YLUpdateSources() index:0 lastError:nil completion:completion];
}

// 依次尝试 Gitee 镜像(jyz2574461147) → Gitee 同名 → GitHub，单次超时 20s
+ (void)checkSources:(NSArray *)sources
               index:(NSInteger)index
           lastError:(NSError *)lastError
          completion:(void (^)(NSDictionary *, NSError *))completion {
    if (index >= (NSInteger)sources.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, lastError ?: [NSError errorWithDomain:@"yuedu.update" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"无法检查更新（网络超时或镜像不可达）。请确认 Gitee 镜像仓库为公开且已同步 Release+IPA"}]);
        });
        return;
    }
    NSDictionary *src = sources[index];
    NSString *host = src[@"host"] ?: @"";
    NSString *repo = src[@"repo"] ?: @"";
    NSString *page = [NSString stringWithFormat:@"%@/%@/releases/latest", host, repo];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:page]];
    request.timeoutInterval = 20;
    [[YLUpdaterSession() dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data.length) {
                [self checkSources:sources index:index + 1 lastError:error completion:completion];
                return;
            }
            NSString *finalUrl = response.URL.absoluteString ?: @"";
            NSString *tag = [self tagFromUrl:finalUrl] ?: response.URL.lastPathComponent;
            NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!tag.length || [tag isEqualToString:@"releases"] || [tag isEqualToString:@"latest"]) {
                tag = [self latestTagFromHtml:html repo:repo];
            }
            NSString *ipaUrl = [self ipaAssetUrlFromHtml:html host:host repo:repo];
            if (!ipaUrl.length && tag.length) {
                ipaUrl = [NSString stringWithFormat:@"%@/%@/releases/download/%@/YueduLite.ipa",
                          host, repo, tag];
            }
            if (!tag.length || [tag isEqualToString:@"releases"]) {
                [self checkSources:sources index:index + 1 lastError:error completion:completion];
                return;
            }
            NSString *version = [tag hasPrefix:@"v"] || [tag hasPrefix:@"V"]
                ? [tag substringFromIndex:1] : tag;
            NSString *remoteBuild = [self buildFromHtml:html tag:tag];
            NSString *full = version;
            if (remoteBuild.length) { full = [NSString stringWithFormat:@"%@.%@", version, remoteBuild]; }
            NSDictionary *info = @{
                @"tag": tag, @"version": version, @"fullVersion": full,
                @"build": remoteBuild ?: @"", @"name": tag,
                @"notes": @"", @"ipaUrl": ipaUrl ?: @"", @"host": host
            };
            dispatch_async(dispatch_get_main_queue(), ^{ completion(info, nil); });
        }] resume];
}

+ (NSString *)tagFromUrl:(NSString *)url {
    if (!url.length) { return nil; }
    NSRange r = [url rangeOfString:@"/releases/tag/"];
    if (r.location != NSNotFound) {
        NSString *tail = [url substringFromIndex:r.location + r.length];
        return [[tail componentsSeparatedByCharactersInSet:
            [NSCharacterSet characterSetWithCharactersInString:@"?#/"]] firstObject];
    }
    return nil;
}

+ (NSString *)latestTagFromHtml:(NSString *)html repo:(NSString *)repo {
    if (!html.length) { return nil; }
    NSString *needle = [NSString stringWithFormat:@"/%@/releases/tag/", repo];
    NSRange found = [html rangeOfString:needle];
    if (found.location == NSNotFound) { return nil; }
    NSRange tail = NSMakeRange(found.location + found.length,
                               MIN((NSUInteger)60, html.length - found.location - found.length));
    NSString *t = [html substringWithRange:tail];
    t = [[t componentsSeparatedByCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@"\"'?#/ \n\r\t"]] firstObject];
    if (t.length && ([t hasPrefix:@"v"] || [t hasPrefix:@"V"] ||
        [t rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location != NSNotFound)) {
        return t;
    }
    return nil;
}

// 从 release 页面提取 build 号（如 "build 19" / "Build 19"），用于与本地 CFBundleVersion 比较
+ (NSString *)buildFromHtml:(NSString *)html tag:(NSString *)tag {
    if (!html.length) { return nil; }
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"[Bb]uild\\s*([0-9]+)"
                                                                        options:0 error:&err];
    if (err) { return nil; }
    // 优先在 tag 附近找，但简单起见取页面中第一个 "build N"（release 页通常只有当前版本）
    NSTextCheckingResult *m = [re firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    if (m && m.numberOfRanges > 1) {
        NSString *b = [html substringWithRange:[m rangeAtIndex:1]];
        if (b.length) { return b; }
    }
    return nil;
}

// 在 release 页面 HTML 里找第一个 .ipa 资源的下载地址（兼容 GitHub/Gitee）
+ (NSString *)ipaAssetUrlFromHtml:(NSString *)html host:(NSString *)host repo:(NSString *)repo {
    if (!html.length) { return nil; }
    NSArray *needles = @[
        [NSString stringWithFormat:@"/%@/releases/download/", repo],
        [NSString stringWithFormat:@"%@/%@/releases/download/", host, repo]
    ];
    for (NSString *needle in needles) {
        NSRange search = NSMakeRange(0, html.length);
        while (search.location < html.length) {
            NSRange found = [html rangeOfString:needle options:0 range:search];
            if (found.location == NSNotFound) { break; }
            NSRange tail = NSMakeRange(found.location, html.length - found.location);
            NSRange end = [html rangeOfString:@"\"" options:0 range:tail];
            NSRange sq = [html rangeOfString:@"'" options:0 range:tail];
            if (sq.location != NSNotFound && (end.location == NSNotFound || sq.location < end.location)) end = sq;
            NSRange q = [html rangeOfString:@"?" options:0 range:tail];
            if (q.location != NSNotFound && (end.location == NSNotFound || q.location < end.location)) end = q;
            if (end.location == NSNotFound) { break; }
            NSString *asset = [html substringWithRange:NSMakeRange(found.location, end.location - found.location)];
            if ([[asset lowercaseString] hasSuffix:@".ipa"]) {
                if ([asset hasPrefix:@"http"]) return asset;
                if ([asset hasPrefix:@"//"]) return [@"https:" stringByAppendingString:asset];
                return [host stringByAppendingString:asset];
            }
            search.location = found.location + 1;
            search.length = html.length - search.location;
        }
    }
    // 宽松兜底：任意包含 .ipa 且含 releases/download 的链接
    NSRange search = NSMakeRange(0, html.length);
    while (search.location < html.length) {
        NSRange ipa = [html rangeOfString:@".ipa" options:NSCaseInsensitiveSearch range:search];
        if (ipa.location == NSNotFound) { break; }
        NSUInteger start = ipa.location;
        while (start > 0 && [html characterAtIndex:start-1] != '"' && [html characterAtIndex:start-1] != '\'' && [html characterAtIndex:start-1] != '>' && start > ipa.location - 300) start--;
        NSString *cand = [html substringWithRange:NSMakeRange(start, ipa.location + 4 - start)];
        if ([cand rangeOfString:@"releases"].location != NSNotFound || [cand rangeOfString:@"download"].location != NSNotFound) {
            if ([cand hasPrefix:@"http"]) return cand;
            if ([cand hasPrefix:@"/"]) return [host stringByAppendingString:cand];
        }
        search.location = ipa.location + 4;
        search.length = html.length - search.location;
    }
    return nil;
}

+ (BOOL)isReleaseNewer:(NSDictionary *)releaseInfo {
    if (![releaseInfo isKindOfClass:[NSDictionary class]]) { return NO; }
    NSDictionary *bundle = [[NSBundle mainBundle] infoDictionary];
    NSString *localVersion = bundle[@"CFBundleShortVersionString"] ?: @"";
    NSString *localBuild = bundle[@"CFBundleVersion"] ?: @"";
    NSString *remoteVersion = [releaseInfo[@"version"] description] ?: @"";
    NSString *remoteBuild = [releaseInfo[@"build"] description] ?: @"";
    if ([remoteBuild isEqualToString:@"(null)"]) { remoteBuild = @""; }
    NSInteger versionCompare = YLCompareVersion(remoteVersion, localVersion);
    if (versionCompare > 0) { return YES; }
    if (versionCompare < 0) { return NO; }
    if (remoteBuild.length && [remoteBuild integerValue] > [localBuild integerValue]) {
        return YES;
    }
    return NO;
}

+ (void)installRelease:(NSDictionary *)releaseInfo
              progress:(void (^)(NSString *))progress
      downloadProgress:(void (^)(double))downloadProgress
            completion:(void (^)(NSError *))completion {
    NSString *ipaUrl = [releaseInfo[@"ipaUrl"] description];
    if (!ipaUrl.length || [ipaUrl isEqualToString:@"(null)"]) {
        completion([NSError errorWithDomain:@"yuedu.update" code:5
            userInfo:@{NSLocalizedDescriptionKey: @"缺少 IPA 下载地址（Release 里没有找到 YueduLite.ipa）"}]);
        return;
    }

    NSString *tag = [releaseInfo[@"tag"] description] ?: @"latest";
    tag = [[tag componentsSeparatedByCharactersInSet:
        [[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@""];
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"yuedu-update-%@.ipa", tag.length ? tag : @"latest"]];
    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:NULL];

    if (progress) { progress(@"正在下载更新… 0%"); }
    NSMutableURLRequest *download = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:ipaUrl]];
    download.timeoutInterval = 30;
    YLTransferProgress *poller = [[YLTransferProgress alloc] init];
    poller.upload = NO;
    poller.handler = ^(double fraction) {
        if (downloadProgress) { downloadProgress(fraction); }
        if (progress) {
            progress([NSString stringWithFormat:@"正在下载更新… %ld%%",
                (long)lround(fraction * 100.0)]);
        }
    };
    NSURLSessionDownloadTask *downloadTask =
        [YLUpdaterSession() downloadTaskWithRequest:download
        completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            [poller stop];
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            if (!error && http && http.statusCode / 100 != 2) {
                error = [NSError errorWithDomain:@"yuedu.update" code:6
                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"IPA 下载失败 (HTTP %ld)", (long)http.statusCode]}];
            }
            if (error || !location) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(error ?: [NSError errorWithDomain:@"yuedu.update" code:6
                        userInfo:@{NSLocalizedDescriptionKey: @"IPA 下载失败"}]);
                });
                return;
            }
            [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:NULL];
            NSError *moveError = nil;
            if (![[NSFileManager defaultManager] moveItemAtURL:location
                                                         toURL:[NSURL fileURLWithPath:tmpPath]
                                                         error:&moveError]) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(moveError); });
                return;
            }
            if (downloadProgress) { downloadProgress(1.0); }
            if (progress) { progress(@"正在安装更新…"); }

            // 安装会阻塞（通常 5~30 秒），放到后台线程避免界面卡死。
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSError *installError = nil;
                BOOL installed = [self installPackageAtPath:tmpPath error:&installError];
                if (installed) {
                    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:NULL];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (installed) {
                        completion(nil);
                    } else {
                        completion(installError ?: [NSError errorWithDomain:@"yuedu.update" code:7
                            userInfo:@{NSLocalizedDescriptionKey: @"安装失败，请确认已安装 AppSync Unified"}] );
                    }
                });
            });
        }];
    poller.task = downloadTask;
    [poller start];
    [downloadTask resume];
}

+ (BOOL)installPackageAtPath:(NSString *)path error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        if (error) {
            *error = [NSError errorWithDomain:@"yuedu.update" code:8
                userInfo:@{NSLocalizedDescriptionKey: @"安装包不存在（下载未完成）"}];
        }
        return NO;
    }

    // 1) 优先 ipainstaller：直接传 IPA 路径即可安装。
    NSString *lastLog = @"";
    NSArray *binaries = @[
        @"/usr/bin/ipainstaller",
        @"/usr/local/bin/ipainstaller",
        @"/var/jb/usr/bin/ipainstaller"
    ];
    for (NSString *binary in binaries) {
        if (![fm isExecutableFileAtPath:binary]) { continue; }
        NSInteger exitCode = -1;
        NSString *log = @"";
        BOOL launched = YLRunAndWait(binary, @[path], &log, &exitCode);
        if (launched && exitCode == 0) { return YES; }
        lastLog = log.length ? log : lastLog;
        break;
    }

    // 2) 退回 MobileInstallation（与 Filza 使用同一安装接口）
    int miResult = YLInstallWithMobileInstallation(path);
    if (miResult == 0) { return YES; }

    // 3) 再试 LSApplicationWorkspace（iOS 8+ 的公开安装入口）
    dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
           RTLD_LAZY);
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (workspaceClass) {
        id workspace = [(id)workspaceClass performSelector:@selector(defaultWorkspace)];
        SEL installSelector = @selector(installApplication:withOptions:);
        if (workspace && [workspace respondsToSelector:installSelector]) {
            typedef BOOL (*YLInstallApplicationIMP)(id, SEL, NSURL *, NSDictionary *);
            YLInstallApplicationIMP install = (YLInstallApplicationIMP)
                [workspace methodForSelector:installSelector];
            NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
            NSURL *url = [NSURL fileURLWithPath:path];
            if (install && install(workspace, installSelector, url,
                                   @{@"CFBundleIdentifier": bundleId})) {
                return YES;
            }
        }
    }

    NSString *detail = [lastLog stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (detail.length > 240) { detail = [detail substringToIndex:240]; }
    NSString *message = [NSString stringWithFormat:
        @"安装失败（MobileInstallation 返回 %d）。\n请确认已安装 AppSync Unified，且设备已越狱。%@\n\n"
         "安装包位置：\n%@",
        miResult,
        detail.length ? [@"\n" stringByAppendingString:detail] : @"",
        path];
    if (error) {
        *error = [NSError errorWithDomain:@"yuedu.update" code:20
            userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

+ (void)cleanupStalePackages {
    NSString *tmp = NSTemporaryDirectory();
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tmp error:NULL];
    for (NSString *name in items) {
        if ([name hasPrefix:@"yuedu-update"] && [name hasSuffix:@".ipa"]) {
            [[NSFileManager defaultManager] removeItemAtPath:
                [tmp stringByAppendingPathComponent:name] error:NULL];
        }
    }
}

+ (void)relaunchApplication {
    static BOOL scheduled = NO;
    if (scheduled) { return; }
    scheduled = YES;

    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"com.local.yuedulite";
    // 退出后由后台脚本拉起新版本；uiopen / open 来自常见越狱工具包。
    NSString *command = [NSString stringWithFormat:
        @"sleep 2; "
         "/usr/bin/uiopen yuedulite:// >/dev/null 2>&1 || "
         "/usr/bin/open %@ >/dev/null 2>&1 || "
         "/usr/local/bin/uiopen yuedulite:// >/dev/null 2>&1",
        bundleId];
    YLSpawnDetached(@"/bin/sh", @[@"-c", command]);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        exit(0);
    });
}

@end
