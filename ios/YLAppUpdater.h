#import <Foundation/Foundation.h>

extern NSString *const YLAutoCheckUpdateKey;

/**
 * 应用内更新：
 * 1. 从 Gitee / GitHub Release 查询最新版本；
 * 2. 下载 IPA 到应用临时目录；
 * 3. 直接在本机安装（优先调用 ipainstaller，失败时退回
 *    MobileInstallation 私有接口，依赖 AppSync Unified 允许未签名覆盖）；
 * 4. 安装成功后删除安装包，由调用方重启应用。
 *    不再依赖 itms-services 和用户 WebDAV，避免 manifest 404。
 */
@interface YLAppUpdater : NSObject

/** 查询最新 release，返回 {tag, version, build, fullVersion, ipaUrl, host}，失败返回 error。 */
+ (void)checkForUpdateWithCompletion:(void (^)(NSDictionary *releaseInfo,
                                               NSError *error))completion;

/** 云端 release 是否比当前安装的版本新（优先比较 build 号）。 */
+ (BOOL)isReleaseNewer:(NSDictionary *)releaseInfo;

/**
 * 下载并直接安装。
 * progress 用于显示阶段状态，downloadProgress 为 0.0 ~ 1.0。
 */
+ (void)installRelease:(NSDictionary *)releaseInfo
              progress:(void (^)(NSString *status))progress
      downloadProgress:(void (^)(double fraction))downloadProgress
            completion:(void (^)(NSError *error))completion;

/** 删除临时目录里上次残留的更新包。 */
+ (void)cleanupStalePackages;

/** 退出应用并尝试自动重新打开（失败时用户手动点桌面图标）。 */
+ (void)relaunchApplication;

@end
