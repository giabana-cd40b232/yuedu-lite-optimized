#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, YLReaderTheme) {
    YLReaderThemeWhite = 0,
    YLReaderThemeSepia = 1,
    YLReaderThemeGreen = 2,
    YLReaderThemeNight = 3
};

extern NSString *const YLThemeDidChangeNotification;

/**
 * 全局主题 + 阅读排版设置。
 * 设置保存在 NSUserDefaults，阅读页和列表页共用一套配色。
 */
@interface YLTheme : NSObject

+ (instancetype)shared;

#pragma mark - 阅读排版

@property (nonatomic, assign) NSInteger fontSize;        // 13 - 30
@property (nonatomic, copy) NSString *fontFamily;        // system / song / hei / kai
@property (nonatomic, assign) CGFloat lineSpacing;       // 2 - 16
@property (nonatomic, assign) CGFloat paragraphSpacing;  // 0 - 24 段间距
@property (nonatomic, assign) CGFloat letterSpacing;     // 0 - 6  字间距
@property (nonatomic, assign) CGFloat insetLeft;         // 0 - 48
@property (nonatomic, assign) CGFloat insetRight;        // 0 - 48
@property (nonatomic, assign) CGFloat insetTop;          // 0 - 48
@property (nonatomic, assign) CGFloat insetBottom;       // 0 - 48
@property (nonatomic, assign) BOOL boldText;             // 正文加粗
@property (nonatomic, assign) BOOL italicText;           // 正文斜体
@property (nonatomic, assign) BOOL showChapterTitle;     // 正文顶部显示章节标题
@property (nonatomic, assign) BOOL showHeader;           // 页眉：书名 + 章节
@property (nonatomic, assign) BOOL showFooter;           // 页脚：页码
@property (nonatomic, assign) YLReaderTheme readerTheme;
@property (nonatomic, assign) BOOL pagedMode;            // YES 翻页，NO 滚动
@property (nonatomic, assign) BOOL pageCurl;             // YES 仿真，NO 平移
@property (nonatomic, assign) NSInteger readerOrientation; // 0 自动 1 竖屏锁定 2 横屏锁定

#pragma mark - 章节标题

@property (nonatomic, assign) CGFloat chapterTitleFontSize;   // 0 = 跟随正文自动
@property (nonatomic, copy) NSString *chapterTitleFontFamily; // 空 = 跟随正文字体
@property (nonatomic, assign) NSInteger chapterTitleWeight;   // 0 常规 1 中黑 2 加粗

- (UIFont *)chapterTitleFont;
- (NSString *)chapterTitleWeightName;

#pragma mark - 界面

@property (nonatomic, assign) BOOL nightMode;

- (void)save;

#pragma mark - 字体

- (NSArray *)familyKeys;
- (NSString *)displayNameForFamily:(NSString *)family;
- (UIFont *)fontOfSize:(CGFloat)size;
- (UIFont *)boldFontOfSize:(CGFloat)size;
/** 按当前字体生成粗体/斜体变体；自定义字体不支持时退回最接近的字体。 */
- (UIFont *)fontOfSize:(CGFloat)size bold:(BOOL)bold italic:(BOOL)italic;

#pragma mark - 阅读配色

- (UIColor *)readerBackground;
- (UIColor *)readerTextColor;
- (UIColor *)readerSecondaryColor;

#pragma mark - 界面配色

- (UIColor *)appBackground;
- (UIColor *)barBackground;
- (UIColor *)barTextColor;
- (UIColor *)secondaryTextColor;
- (UIColor *)tertiaryTextColor;
- (UIColor *)accentColor;
- (UIColor *)accentSoftColor;
- (UIColor *)cellBackground;
- (UIColor *)cardBackground;
- (UIColor *)cardBorderColor;
- (UIColor *)separatorColor;

#pragma mark - 现代界面 token

- (CGFloat)cardCornerRadius;   // 16
- (CGFloat)screenPadding;      // 16
- (CGFloat)hairlineHeight;     // 0.5

/** style: 0 蓝 1 琥珀 2 绿，用于统计磁贴等浅色底。 */
- (UIColor *)tintColorForStyle:(NSInteger)style;
- (UIColor *)tintForegroundForStyle:(NSInteger)style;

- (UIFont *)uiFontOfSize:(CGFloat)size weight:(UIFontWeight)weight;
- (UIFont *)titleFontOfSize:(CGFloat)size;

/** 统一卡片观感：圆角 + 背景 + 极细边框（不使用阴影，照顾 4S 性能）。 */
- (void)applyCardStyle:(UIView *)view;
- (void)applyCardStyle:(UIView *)view cornerRadius:(CGFloat)radius;

- (void)applyAppearance;
- (void)applyToViewController:(UIViewController *)controller;
- (void)styleCell:(UITableViewCell *)cell;

@end
