#import <Foundation/Foundation.h>

/**
 * 自定义字体管理：扫描字体目录、用 CoreText 注册 TTF/OTF，
 * 并把 PostScript 名称暴露给阅读器（YLTheme 里用 "custom:<名称>" 表示）。
 */
@interface YLFontManager : NSObject

+ (instancetype)shared;

/** 重新扫描字体目录并注册，返回 [{name, display, file, family}]。 */
- (void)reload;
- (NSArray *)fonts;

- (NSString *)displayNameForFont:(NSString *)postScriptName;

/** 导入/替换一个字体文件（复制到字体目录）。 */
- (BOOL)importFontAtPath:(NSString *)path error:(NSString **)error;

/** 把收件箱里的 ttf/otf 全部导入，导入成功后删除源文件。 */
- (NSInteger)importFontsFromInbox:(NSArray **)imported errors:(NSArray **)errors;

@end
