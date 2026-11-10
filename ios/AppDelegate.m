#import "AppDelegate.h"
#import "API.h"
#import "HomeViewController.h"
#import "ReaderViewController.h"
#import "YLAppUpdater.h"
#import "YLFontManager.h"
#import "YLNavigationController.h"
#import "YLStore.h"
#import "YLTheme.h"
#import "YLUpdateUI.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 先把书籍/字体目录准备好，再加载主题（自定义字体依赖字体注册）
    [[YLStore shared] prepare];
    [[YLFontManager shared] reload];
    [[YLTheme shared] applyAppearance];
    // 清理上次更新残留的安装包（安装过程中进程被系统结束时会留下）
    [YLAppUpdater cleanupStalePackages];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [[YLTheme shared] appBackground];
    self.window.tintColor = [[YLTheme shared] accentColor];

    HomeViewController *home = [[HomeViewController alloc] init];
    YLNavigationController *navigation =
        [[YLNavigationController alloc] initWithRootViewController:home];
    navigation.toolbarHidden = NO;
    self.window.rootViewController = navigation;

    // 上次是从阅读界面退出（包括被系统杀掉）时，直接恢复阅读器，
    // 不再先显示主页再跳转，避免启动时闪一下。
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *lastBook = [defaults dictionaryForKey:@"yl.lastReadingBook"];
    NSString *lastKey = lastBook[@"key"];
    if ([defaults boolForKey:@"yl.lastWasInReader"] &&
        [lastKey isKindOfClass:[NSString class]] && lastKey.length) {
        [defaults setBool:NO forKey:@"yl.lastWasInReader"];
        [defaults synchronize];
        ReaderViewController *reader =
            [[ReaderViewController alloc] initWithBook:lastBook];
        [navigation pushViewController:reader animated:NO];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeChanged)
                                                 name:YLThemeDidChangeNotification
                                               object:nil];

    [self.window makeKeyAndVisible];

    // 启动自动检查更新（可在“设置 - 应用”里关闭）
    if ([YLUpdateUI autoCheckEnabled]) {
        __weak AppDelegate *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            AppDelegate *strongSelf = weakSelf;
            if (!strongSelf) { return; }
            [YLUpdateUI checkForUpdatesFrom:strongSelf.window.rootViewController
                                     silent:YES];
        });
    }
    return YES;
}

- (void)themeChanged {
    [[YLTheme shared] applyAppearance];
    self.window.backgroundColor = [[YLTheme shared] appBackground];
    self.window.tintColor = [[YLTheme shared] accentColor];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [[NSUserDefaults standardUserDefaults] synchronize];
    // 退到后台时补一次上传，避免自动上传被节流而漏掉最后一章
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    task = [application beginBackgroundTaskWithExpirationHandler:^{
        if (task != UIBackgroundTaskInvalid) {
            [application endBackgroundTask:task];
            task = UIBackgroundTaskInvalid;
        }
    }];
    [[API shared] post:@"/api/sync/push" body:@{} completion:^(id result, NSError *error) {
        if (task != UIBackgroundTaskInvalid) {
            [application endBackgroundTask:task];
            task = UIBackgroundTaskInvalid;
        }
    }];
}

@end
