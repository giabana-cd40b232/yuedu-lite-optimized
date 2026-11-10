#import <UIKit/UIKit.h>

/** “设置 - 自动检查更新”开关的 NSUserDefaults key（默认开启）。 */
extern NSString *const YLAutoCheckUpdateKey;

/**
 * 更新提示 / 下载进度 / 安装结果的共用界面。
 * 设置页手动检查和启动时自动检查都走这里，保证行为一致。
 */
@interface YLUpdateUI : NSObject

+ (BOOL)autoCheckEnabled;
+ (void)setAutoCheckEnabled:(BOOL)enabled;

/**
 * 查询最新版本。
 * silent = YES 时不显示“正在检查 / 已是最新”，只有发现新版本才弹窗。
 */
+ (void)checkForUpdatesFrom:(UIViewController *)host silent:(BOOL)silent;

@end
