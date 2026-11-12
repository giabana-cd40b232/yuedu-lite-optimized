#import "YLTheme.h"
#import "YLFontManager.h"

NSString *const YLThemeDidChangeNotification = @"YLThemeDidChangeNotification";

static NSString *const kYLFontSizeKey = @"yl.theme.fontSize";
static NSString *const kYLFontFamilyKey = @"yl.theme.fontFamily";
static NSString *const kYLLineSpacingKey = @"yl.theme.lineSpacing";
static NSString *const kYLParagraphSpacingKey = @"yl.theme.paragraphSpacing";
static NSString *const kYLLetterSpacingKey = @"yl.theme.letterSpacing";
static NSString *const kYLInsetLeftKey = @"yl.theme.insetLeft";
static NSString *const kYLInsetRightKey = @"yl.theme.insetRight";
static NSString *const kYLInsetTopKey = @"yl.theme.insetTop";
static NSString *const kYLInsetBottomKey = @"yl.theme.insetBottom";
static NSString *const kYLShowTitleKey = @"yl.theme.showChapterTitle";
static NSString *const kYLBoldTextKey = @"yl.theme.boldText";
static NSString *const kYLItalicTextKey = @"yl.theme.italicText";
static NSString *const kYLShowHeaderKey = @"yl.theme.showHeader";
static NSString *const kYLShowFooterKey = @"yl.theme.showFooter";
static NSString *const kYLReaderThemeKey = @"yl.theme.readerTheme";
static NSString *const kYLPagedModeKey = @"yl.theme.pagedMode";
static NSString *const kYLPageCurlKey = @"yl.theme.pageCurl";
static NSString *const kYLNightModeKey = @"yl.theme.nightMode";
static NSString *const kYLReaderOrientKey = @"yl.reader.orientation";
static NSString *const kYLChapterTitleSizeKey = @"yl.theme.chapterTitleSize";
static NSString *const kYLChapterTitleFamilyKey = @"yl.theme.chapterTitleFamily";
static NSString *const kYLChapterTitleWeightKey = @"yl.theme.chapterTitleWeight";

@implementation YLTheme

+ (instancetype)shared {
    static YLTheme *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[YLTheme alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _fontSize = [defaults objectForKey:kYLFontSizeKey]
            ? [defaults integerForKey:kYLFontSizeKey] : 18;
        _fontFamily = [defaults stringForKey:kYLFontFamilyKey] ?: @"system";
        _lineSpacing = [defaults objectForKey:kYLLineSpacingKey]
            ? [defaults doubleForKey:kYLLineSpacingKey] : 8.0;
        _paragraphSpacing = [defaults objectForKey:kYLParagraphSpacingKey]
            ? [defaults doubleForKey:kYLParagraphSpacingKey] : 6.0;
        _letterSpacing = [defaults objectForKey:kYLLetterSpacingKey]
            ? [defaults doubleForKey:kYLLetterSpacingKey] : 0.0;
        _insetLeft = [defaults objectForKey:kYLInsetLeftKey]
            ? [defaults doubleForKey:kYLInsetLeftKey] : 18.0;
        _insetRight = [defaults objectForKey:kYLInsetRightKey]
            ? [defaults doubleForKey:kYLInsetRightKey] : 18.0;
        _insetTop = [defaults objectForKey:kYLInsetTopKey]
            ? [defaults doubleForKey:kYLInsetTopKey] : 6.0;
        _insetBottom = [defaults objectForKey:kYLInsetBottomKey]
            ? [defaults doubleForKey:kYLInsetBottomKey] : 6.0;
        _showChapterTitle = [defaults objectForKey:kYLShowTitleKey]
            ? [defaults boolForKey:kYLShowTitleKey] : YES;
        _boldText = [defaults objectForKey:kYLBoldTextKey]
            ? [defaults boolForKey:kYLBoldTextKey] : NO;
        _italicText = [defaults objectForKey:kYLItalicTextKey]
            ? [defaults boolForKey:kYLItalicTextKey] : NO;
        _showHeader = [defaults objectForKey:kYLShowHeaderKey]
            ? [defaults boolForKey:kYLShowHeaderKey] : YES;
        _showFooter = [defaults objectForKey:kYLShowFooterKey]
            ? [defaults boolForKey:kYLShowFooterKey] : YES;
        _readerTheme = [defaults objectForKey:kYLReaderThemeKey]
            ? [defaults integerForKey:kYLReaderThemeKey] : YLReaderThemeWhite;
        _pagedMode = [defaults objectForKey:kYLPagedModeKey]
            ? [defaults boolForKey:kYLPagedModeKey] : YES;
        _pageCurl = [defaults objectForKey:kYLPageCurlKey]
            ? [defaults boolForKey:kYLPageCurlKey] : NO;
        _nightMode = [defaults objectForKey:kYLNightModeKey]
            ? [defaults boolForKey:kYLNightModeKey] : NO;
        _readerOrientation = [defaults objectForKey:kYLReaderOrientKey]
            ? [defaults integerForKey:kYLReaderOrientKey] : 0;
        _chapterTitleFontSize = [defaults objectForKey:kYLChapterTitleSizeKey]
            ? [defaults doubleForKey:kYLChapterTitleSizeKey] : 0;
        _chapterTitleFontFamily = [defaults stringForKey:kYLChapterTitleFamilyKey] ?: @"";
        _chapterTitleWeight = [defaults objectForKey:kYLChapterTitleWeightKey]
            ? [defaults integerForKey:kYLChapterTitleWeightKey] : 2;
        [self clampValues];
    }
    return self;
}

- (void)clampValues {
    if (_fontSize < 13) { _fontSize = 13; }
    if (_fontSize > 30) { _fontSize = 30; }
    if (_lineSpacing < 2) { _lineSpacing = 2; }
    if (_lineSpacing > 16) { _lineSpacing = 16; }
    if (_paragraphSpacing < 0) { _paragraphSpacing = 0; }
    if (_paragraphSpacing > 24) { _paragraphSpacing = 24; }
    if (_letterSpacing < 0) { _letterSpacing = 0; }
    if (_letterSpacing > 6) { _letterSpacing = 6; }
    if (_insetLeft < 0) { _insetLeft = 0; }
    if (_insetLeft > 48) { _insetLeft = 48; }
    if (_insetRight < 0) { _insetRight = 0; }
    if (_insetRight > 48) { _insetRight = 48; }
    if (_insetTop < 0) { _insetTop = 0; }
    if (_insetTop > 48) { _insetTop = 48; }
    if (_insetBottom < 0) { _insetBottom = 0; }
    if (_insetBottom > 48) { _insetBottom = 48; }
    if (_chapterTitleFontSize > 0) {
        if (_chapterTitleFontSize < 12) { _chapterTitleFontSize = 12; }
        if (_chapterTitleFontSize > 34) { _chapterTitleFontSize = 34; }
    }
    if (_chapterTitleWeight < 0) { _chapterTitleWeight = 0; }
    if (_chapterTitleWeight > 2) { _chapterTitleWeight = 2; }
    if (_readerTheme < YLReaderThemeWhite || _readerTheme > YLReaderThemeNight) {
        _readerTheme = YLReaderThemeWhite;
    }
    if (_readerOrientation < 0 || _readerOrientation > 2) { _readerOrientation = 0; }
    if (!_fontFamily.length) { _fontFamily = @"system"; }
    NSArray *builtin = @[@"system", @"song", @"hei", @"kai"];
    BOOL custom = [_fontFamily hasPrefix:@"custom:"] &&
        _fontFamily.length > 7;
    if (!custom && ![builtin containsObject:_fontFamily]) {
        _fontFamily = @"system";
    }
    if (_chapterTitleFontFamily.length) {
        BOOL titleCustom = [_chapterTitleFontFamily hasPrefix:@"custom:"] &&
            _chapterTitleFontFamily.length > 7;
        if (!titleCustom && ![builtin containsObject:_chapterTitleFontFamily]) {
            _chapterTitleFontFamily = @"";
        }
    }
}

- (void)save {
    [self clampValues];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.fontSize forKey:kYLFontSizeKey];
    [defaults setObject:self.fontFamily ?: @"system" forKey:kYLFontFamilyKey];
    [defaults setDouble:self.lineSpacing forKey:kYLLineSpacingKey];
    [defaults setDouble:self.paragraphSpacing forKey:kYLParagraphSpacingKey];
    [defaults setDouble:self.letterSpacing forKey:kYLLetterSpacingKey];
    [defaults setDouble:self.insetLeft forKey:kYLInsetLeftKey];
    [defaults setDouble:self.insetRight forKey:kYLInsetRightKey];
    [defaults setDouble:self.insetTop forKey:kYLInsetTopKey];
    [defaults setDouble:self.insetBottom forKey:kYLInsetBottomKey];
    [defaults setBool:self.showChapterTitle forKey:kYLShowTitleKey];
    [defaults setBool:self.boldText forKey:kYLBoldTextKey];
    [defaults setBool:self.italicText forKey:kYLItalicTextKey];
    [defaults setBool:self.showHeader forKey:kYLShowHeaderKey];
    [defaults setBool:self.showFooter forKey:kYLShowFooterKey];
    [defaults setInteger:self.readerTheme forKey:kYLReaderThemeKey];
    [defaults setBool:self.pagedMode forKey:kYLPagedModeKey];
    [defaults setBool:self.pageCurl forKey:kYLPageCurlKey];
    [defaults setBool:self.nightMode forKey:kYLNightModeKey];
    [defaults setInteger:self.readerOrientation forKey:kYLReaderOrientKey];
    [defaults setDouble:self.chapterTitleFontSize forKey:kYLChapterTitleSizeKey];
    [defaults setObject:self.chapterTitleFontFamily ?: @"" forKey:kYLChapterTitleFamilyKey];
    [defaults setInteger:self.chapterTitleWeight forKey:kYLChapterTitleWeightKey];
    [defaults synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:YLThemeDidChangeNotification
                                                        object:self];
}

#pragma mark - 字体

- (NSArray *)familyKeys {
    NSMutableArray *keys = [NSMutableArray arrayWithObjects:
        @"system", @"song", @"hei", @"kai", nil];
    NSArray *fonts = [[YLFontManager shared] fonts];
    for (NSDictionary *info in fonts) {
        NSString *name = info[@"name"];
        if (!name.length) { continue; }
        NSString *key = [@"custom:" stringByAppendingString:name];
        if (![keys containsObject:key]) { [keys addObject:key]; }
    }
    return keys;
}

- (NSString *)displayNameForFamily:(NSString *)family {
    if ([family hasPrefix:@"custom:"]) {
        NSString *name = [family substringFromIndex:7];
        NSString *display = [[YLFontManager shared] displayNameForFont:name];
        return display.length ? display : name;
    }
    if ([family isEqualToString:@"song"]) { return @"宋体"; }
    if ([family isEqualToString:@"hei"]) { return @"黑体"; }
    if ([family isEqualToString:@"kai"]) { return @"楷体"; }
    return @"系统";
}

- (UIFont *)fontForFamily:(NSString *)family size:(CGFloat)size {
    if (!family.length) { family = @"system"; }
    if ([family hasPrefix:@"custom:"]) {
        NSString *name = [family substringFromIndex:7];
        UIFont *font = [UIFont fontWithName:name size:size];
        if (font) { return font; }
        return [UIFont systemFontOfSize:size];
    }
    NSArray *candidates = nil;
    if ([family isEqualToString:@"song"]) {
        candidates = @[@"STSongti-SC-Regular", @"Songti SC", @"STSong", @"SimSun"];
    } else if ([family isEqualToString:@"hei"]) {
        candidates = @[@"PingFangSC-Regular", @"PingFang SC", @"STHeitiSC-Light", @"Heiti SC"];
    } else if ([family isEqualToString:@"kai"]) {
        candidates = @[@"STKaiti", @"Kaiti SC", @"STKaitiSC-Regular", @"KaiTi"];
    }
    for (NSString *name in candidates) {
        UIFont *font = [UIFont fontWithName:name size:size];
        if (font) { return font; }
    }
    return [UIFont systemFontOfSize:size];
}

- (UIFont *)fontOfSize:(CGFloat)size {
    return [self fontForFamily:self.fontFamily size:size];
}

- (UIFont *)boldFontOfSize:(CGFloat)size {
    UIFont *font = [self fontOfSize:size];
    UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorWithSymbolicTraits:
        UIFontDescriptorTraitBold];
    UIFont *bold = descriptor ? [UIFont fontWithDescriptor:descriptor size:size] : nil;
    return bold ?: [UIFont boldSystemFontOfSize:size];
}

- (UIFont *)fontOfSize:(CGFloat)size bold:(BOOL)bold italic:(BOOL)italic {
    UIFont *base = [self fontOfSize:size];
    if (!bold && !italic) { return base; }
    UIFontDescriptor *descriptor = base.fontDescriptor;
    UIFontDescriptorSymbolicTraits traits = descriptor.symbolicTraits;
    if (bold) {
        traits |= UIFontDescriptorTraitBold;
    } else {
        traits &= ~UIFontDescriptorTraitBold;
    }
    if (italic) {
        traits |= UIFontDescriptorTraitItalic;
    } else {
        traits &= ~UIFontDescriptorTraitItalic;
    }
    UIFontDescriptor *styled = [descriptor fontDescriptorWithSymbolicTraits:traits];
    UIFont *font = styled ? [UIFont fontWithDescriptor:styled size:size] : nil;
    if (font) { return font; }
    // 部分中文字体没有斜体变体：先拿到粗体，再给斜体加倾斜矩阵。
    UIFont *fallback = bold ? [self boldFontOfSize:size] : base;
    if (italic) {
        UIFontDescriptor *fd = fallback.fontDescriptor;
        CGAffineTransform matrix = CGAffineTransformMake(1, 0, 0.22, 1, 0, 0);
        fd = [fd fontDescriptorWithMatrix:matrix];
        UIFont *italicFont = fd ? [UIFont fontWithDescriptor:fd size:size] : nil;
        if (italicFont) { return italicFont; }
    }
    return fallback;
}

#pragma mark - 章节标题

- (UIFont *)chapterTitleFont {
    CGFloat size = self.chapterTitleFontSize > 0
        ? self.chapterTitleFontSize : (CGFloat)(self.fontSize + 2);
    NSString *family = self.chapterTitleFontFamily.length
        ? self.chapterTitleFontFamily : self.fontFamily;
    UIFont *base = [self fontForFamily:family size:size];
    if (self.chapterTitleWeight <= 0) { return base; }

    UIFontDescriptor *descriptor = base.fontDescriptor;
    if (self.chapterTitleWeight >= 2) {
        descriptor = [descriptor fontDescriptorWithSymbolicTraits:
            descriptor.symbolicTraits | UIFontDescriptorTraitBold];
    } else {
        // 中黑：用字重 trait，系统字体能精确呈现，中文字体自动回退最接近的权重。
        NSDictionary *traits = @{UIFontWeightTrait: @(0.23)};
        descriptor = [descriptor fontDescriptorByAddingAttributes:
            @{UIFontDescriptorTraitsAttribute: traits}];
    }
    UIFont *font = descriptor ? [UIFont fontWithDescriptor:descriptor size:size] : nil;
    if (font) { return font; }
    return self.chapterTitleWeight >= 2 ? [self boldFontOfSize:size] : base;
}

- (NSString *)chapterTitleWeightName {
    if (self.chapterTitleWeight >= 2) { return @"加粗"; }
    if (self.chapterTitleWeight == 1) { return @"中黑"; }
    return @"常规";
}

#pragma mark - 阅读配色

- (UIColor *)readerBackground {
    switch (self.readerTheme) {
        case YLReaderThemeSepia:
            return [UIColor colorWithRed:0.961 green:0.925 blue:0.851 alpha:1.0];
        case YLReaderThemeGreen:
            return [UIColor colorWithRed:0.902 green:0.937 blue:0.886 alpha:1.0];
        case YLReaderThemeNight:
            return [UIColor colorWithRed:0.067 green:0.075 blue:0.090 alpha:1.0];
        case YLReaderThemeWhite:
        default:
            return [UIColor colorWithRed:0.984 green:0.980 blue:0.969 alpha:1.0];
    }
}

- (UIColor *)readerTextColor {
    switch (self.readerTheme) {
        case YLReaderThemeSepia:
            return [UIColor colorWithRed:0.239 green:0.196 blue:0.145 alpha:1.0];
        case YLReaderThemeGreen:
            return [UIColor colorWithRed:0.129 green:0.180 blue:0.149 alpha:1.0];
        case YLReaderThemeNight:
            return [UIColor colorWithRed:0.729 green:0.757 blue:0.792 alpha:1.0];
        case YLReaderThemeWhite:
        default:
            return [UIColor colorWithRed:0.118 green:0.133 blue:0.157 alpha:1.0];
    }
}

- (UIColor *)readerSecondaryColor {
    return [[self readerTextColor] colorWithAlphaComponent:0.52];
}

#pragma mark - 界面配色

- (UIColor *)appBackground {
    return self.nightMode
        ? [UIColor colorWithRed:0.043 green:0.055 blue:0.075 alpha:1.0]
        : [UIColor colorWithRed:0.949 green:0.957 blue:0.973 alpha:1.0];
}

- (UIColor *)barBackground {
    return self.nightMode
        ? [UIColor colorWithRed:0.071 green:0.086 blue:0.114 alpha:1.0]
        : [UIColor whiteColor];
}

- (UIColor *)barTextColor {
    return self.nightMode
        ? [UIColor colorWithRed:0.925 green:0.937 blue:0.953 alpha:1.0]
        : [UIColor colorWithRed:0.063 green:0.094 blue:0.157 alpha:1.0];
}

- (UIColor *)secondaryTextColor {
    return self.nightMode
        ? [UIColor colorWithRed:0.596 green:0.635 blue:0.702 alpha:1.0]
        : [UIColor colorWithRed:0.373 green:0.420 blue:0.502 alpha:1.0];
}

- (UIColor *)tertiaryTextColor {
    return self.nightMode
        ? [UIColor colorWithRed:0.400 green:0.439 blue:0.522 alpha:1.0]
        : [UIColor colorWithRed:0.596 green:0.635 blue:0.702 alpha:1.0];
}

- (UIColor *)accentColor {
    return self.nightMode
        ? [UIColor colorWithRed:0.478 green:0.608 blue:1.000 alpha:1.0]
        : [UIColor colorWithRed:0.204 green:0.435 blue:0.925 alpha:1.0];
}

- (UIColor *)accentSoftColor {
    return self.nightMode
        ? [UIColor colorWithRed:0.110 green:0.153 blue:0.278 alpha:1.0]
        : [UIColor colorWithRed:0.910 green:0.937 blue:1.000 alpha:1.0];
}

- (UIColor *)cellBackground {
    return self.nightMode
        ? [UIColor colorWithRed:0.082 green:0.098 blue:0.129 alpha:1.0]
        : [UIColor whiteColor];
}

- (UIColor *)cardBackground {
    return [self cellBackground];
}

- (UIColor *)cardBorderColor {
    return self.nightMode
        ? [UIColor colorWithRed:0.137 green:0.161 blue:0.212 alpha:1.0]
        : [UIColor colorWithRed:0.902 green:0.914 blue:0.937 alpha:1.0];
}

- (UIColor *)separatorColor {
    return self.nightMode
        ? [UIColor colorWithRed:0.145 green:0.169 blue:0.220 alpha:1.0]
        : [UIColor colorWithRed:0.898 green:0.910 blue:0.933 alpha:1.0];
}

#pragma mark - 现代界面 token

- (CGFloat)cardCornerRadius {
    return 16.0;
}

- (CGFloat)screenPadding {
    return 16.0;
}

- (CGFloat)hairlineHeight {
    return 0.5;
}

- (UIColor *)tintColorForStyle:(NSInteger)style {
    if (self.nightMode) {
        if (style == 1) { return [UIColor colorWithRed:0.157 green:0.125 blue:0.078 alpha:1.0]; }
        if (style == 2) { return [UIColor colorWithRed:0.075 green:0.157 blue:0.118 alpha:1.0]; }
        return [UIColor colorWithRed:0.094 green:0.125 blue:0.216 alpha:1.0];
    }
    if (style == 1) { return [UIColor colorWithRed:1.000 green:0.957 green:0.898 alpha:1.0]; }
    if (style == 2) { return [UIColor colorWithRed:0.914 green:0.976 green:0.941 alpha:1.0]; }
    return [UIColor colorWithRed:0.929 green:0.945 green:1.000 alpha:1.0];
}

- (UIColor *)tintForegroundForStyle:(NSInteger)style {
    if (self.nightMode) {
        if (style == 1) { return [UIColor colorWithRed:0.961 green:0.718 blue:0.357 alpha:1.0]; }
        if (style == 2) { return [UIColor colorWithRed:0.373 green:0.827 blue:0.627 alpha:1.0]; }
        return [UIColor colorWithRed:0.561 green:0.655 blue:1.000 alpha:1.0];
    }
    if (style == 1) { return [UIColor colorWithRed:0.698 green:0.416 blue:0.000 alpha:1.0]; }
    if (style == 2) { return [UIColor colorWithRed:0.071 green:0.502 blue:0.361 alpha:1.0]; }
    return [self accentColor];
}

- (UIFont *)uiFontOfSize:(CGFloat)size weight:(CGFloat)weight {
    if ([UIFont respondsToSelector:@selector(systemFontOfSize:weight:)]) {
        return [UIFont systemFontOfSize:size weight:weight];
    }
    return weight >= UIFontWeightSemibold
        ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
}

- (UIFont *)titleFontOfSize:(CGFloat)size {
    return [self uiFontOfSize:size weight:UIFontWeightBold];
}

- (void)applyCardStyle:(UIView *)view {
    [self applyCardStyle:view cornerRadius:[self cardCornerRadius]];
}

- (void)applyCardStyle:(UIView *)view cornerRadius:(CGFloat)radius {
    if (!view) { return; }
    view.backgroundColor = [self cardBackground];
    view.layer.cornerRadius = radius;
    view.layer.masksToBounds = YES;
    view.layer.borderWidth = 0.5;
    view.layer.borderColor = [self cardBorderColor].CGColor;
}

#pragma mark - 应用

- (void)applyAppearance {
    UINavigationBar *navigationBar = [UINavigationBar appearance];
    navigationBar.barTintColor = [self barBackground];
    navigationBar.backgroundColor = [self barBackground];
    navigationBar.tintColor = [self accentColor];
    navigationBar.translucent = NO;
    navigationBar.titleTextAttributes = @{
        NSForegroundColorAttributeName: [self barTextColor],
        NSFontAttributeName: [self uiFontOfSize:17 weight:UIFontWeightSemibold]
    };
    // 去掉 iOS 9 默认的立体渐变和高光，得到纯色现代导航栏。
    [navigationBar setBackgroundImage:[[UIImage alloc] init]
                        forBarMetrics:UIBarMetricsDefault];
    [navigationBar setShadowImage:[[UIImage alloc] init]];

    UIToolbar *toolbar = [UIToolbar appearance];
    toolbar.barTintColor = [self barBackground];
    toolbar.tintColor = [self accentColor];
    toolbar.translucent = NO;
    [toolbar setBackgroundImage:[[UIImage alloc] init]
             forToolbarPosition:UIBarPositionAny
                     barMetrics:UIBarMetricsDefault];
    [toolbar setShadowImage:[[UIImage alloc] init]
         forToolbarPosition:UIBarPositionAny];

    [[UISegmentedControl appearance] setTintColor:[self accentColor]];
    [[UISwitch appearance] setOnTintColor:[self accentColor]];
}

- (void)applyToViewController:(UIViewController *)controller {
    if (!controller) { return; }
    controller.view.backgroundColor = [self appBackground];
    if ([controller isKindOfClass:[UITableViewController class]]) {
        UITableView *tableView = ((UITableViewController *)controller).tableView;
        tableView.backgroundColor = [self appBackground];
        tableView.separatorColor = [self separatorColor];
        tableView.indicatorStyle = self.nightMode
            ? UIScrollViewIndicatorStyleWhite : UIScrollViewIndicatorStyleDefault;
        [tableView reloadData];
    }
    UINavigationController *navigation = controller.navigationController;
    if (navigation) {
        navigation.navigationBar.barTintColor = [self barBackground];
        navigation.navigationBar.tintColor = [self accentColor];
        navigation.navigationBar.translucent = NO;
        navigation.navigationBar.titleTextAttributes = @{
            NSForegroundColorAttributeName: [self barTextColor],
            NSFontAttributeName: [self uiFontOfSize:17 weight:UIFontWeightSemibold]
        };
        navigation.toolbar.barTintColor = [self barBackground];
        navigation.toolbar.tintColor = [self accentColor];
        navigation.toolbar.translucent = NO;
    }
}

- (void)styleCell:(UITableViewCell *)cell {
    if (!cell) { return; }
    cell.backgroundColor = [self cellBackground];
    cell.contentView.backgroundColor = [self cellBackground];
    cell.textLabel.textColor = [self barTextColor];
    cell.detailTextLabel.textColor = [self secondaryTextColor];
    UIView *selected = [[UIView alloc] init];
    UIColor *highlight = self.nightMode
        ? [UIColor colorWithRed:0.110 green:0.133 blue:0.176 alpha:1.0]
        : [UIColor colorWithRed:0.937 green:0.949 blue:0.969 alpha:1.0];
    selected.backgroundColor = highlight;
    cell.selectedBackgroundView = selected;
}

@end
