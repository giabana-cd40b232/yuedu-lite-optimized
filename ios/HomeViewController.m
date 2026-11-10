#import "HomeViewController.h"
#import "API.h"
#import "BookshelfViewController.h"
#import "CloudViewController.h"
#import "ReaderViewController.h"
#import "SettingsViewController.h"
#import "YLComponents.h"
#import "YLTheme.h"
#import <math.h>

@interface HomeViewController ()
@property (nonatomic, strong) NSDictionary *currentBook;
@property (nonatomic, strong) NSDictionary *stats;
@property (nonatomic, assign) BOOL autoResumePending;

@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UILabel *greetingLabel;
@property (nonatomic, strong) UILabel *greetingSubLabel;

@property (nonatomic, strong) UIView *bookCard;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *bookNameLabel;
@property (nonatomic, strong) UILabel *bookMetaLabel;
@property (nonatomic, strong) UILabel *bookProgressText;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, strong) UIButton *continueButton;

@property (nonatomic, strong) UILabel *statsTitleLabel;
@property (nonatomic, strong) UIView *timeTile;
@property (nonatomic, strong) UILabel *timeValueLabel;
@property (nonatomic, strong) UIView *countTile;
@property (nonatomic, strong) UILabel *countValueLabel;
@property (nonatomic, strong) UILabel *actionsTitleLabel;

@property (nonatomic, strong) NSTimer *animTimer;
@property (nonatomic, assign) NSInteger animTimeTarget;
@property (nonatomic, assign) NSInteger animCountTarget;
@property (nonatomic, assign) NSInteger animTimeShown;
@property (nonatomic, assign) NSInteger animCountShown;
@end

static NSMutableDictionary *YLHomeCoverCache(void) {
    static NSMutableDictionary *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSMutableDictionary dictionary]; });
    return cache;
}

@implementation HomeViewController

- (void)dealloc {
    [self.animTimer invalidate];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // 大标题放在滚动区，导航栏只保留图标按钮，视觉上更接近现代 App。
    self.title = @"";
    self.autoResumePending = YES;
    self.navigationItem.backBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"返回"
                                         style:UIBarButtonItemStylePlain
                                        target:nil
                                        action:nil];
    UIImage *settingsIcon = [YLComponents iconNamed:@"settings" size:22
                                              color:[[YLTheme shared] accentColor]];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:settingsIcon
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(showSettings)];
    UIImage *shelfIcon = [YLComponents iconNamed:@"books" size:22
                                           color:[[YLTheme shared] accentColor]];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:shelfIcon
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(openShelf)];
    [self buildUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:NO];
    self.navigationController.toolbarHidden = YES;
    [[YLTheme shared] applyToViewController:self];
    [self applyTheme];
    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutUI];
}

#pragma mark - UI 构建

- (void)buildUI {
    YLTheme *theme = [YLTheme shared];
    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scroll.alwaysBounceVertical = YES;
    self.scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scroll];

    self.greetingLabel = [YLComponents labelWithFont:[theme titleFontOfSize:26]
                                               color:theme.barTextColor];
    self.greetingLabel.text = @"阅读 Lite";
    [self.scroll addSubview:self.greetingLabel];

    self.greetingSubLabel = [YLComponents labelWithFont:[theme uiFontOfSize:13
                                                                    weight:UIFontWeightRegular]
                                                  color:theme.secondaryTextColor];
    self.greetingSubLabel.text = @"把碎片时间留给一本书";
    [self.scroll addSubview:self.greetingSubLabel];

    // 当前书籍卡片
    self.bookCard = [YLComponents cardView];
    [self.scroll addSubview:self.bookCard];

    self.coverView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView.clipsToBounds = YES;
    self.coverView.layer.cornerRadius = 8;
    self.coverView.backgroundColor = theme.accentSoftColor;
    [self.bookCard addSubview:self.coverView];

    self.bookNameLabel = [YLComponents labelWithFont:[theme uiFontOfSize:17
                                                                    weight:UIFontWeightSemibold]
                                               color:theme.barTextColor];
    self.bookNameLabel.numberOfLines = 2;
    [self.bookCard addSubview:self.bookNameLabel];

    self.bookMetaLabel = [YLComponents labelWithFont:[theme uiFontOfSize:12
                                                                   weight:UIFontWeightRegular]
                                               color:theme.tertiaryTextColor];
    self.bookMetaLabel.numberOfLines = 1;
    [self.bookCard addSubview:self.bookMetaLabel];

    self.bookProgressText = [YLComponents labelWithFont:[theme uiFontOfSize:12
                                                                     weight:UIFontWeightMedium]
                                                  color:theme.accentColor];
    self.bookProgressText.numberOfLines = 1;
    self.bookProgressText.adjustsFontSizeToFitWidth = YES;
    self.bookProgressText.minimumScaleFactor = 0.8;
    [self.bookCard addSubview:self.bookProgressText];

    self.progressTrack = [[UIView alloc] initWithFrame:CGRectZero];
    self.progressTrack.layer.cornerRadius = 3;
    self.progressTrack.clipsToBounds = YES;
    [self.bookCard addSubview:self.progressTrack];
    self.progressFill = [[UIView alloc] initWithFrame:CGRectZero];
    self.progressFill.layer.cornerRadius = 3;
    [self.progressTrack addSubview:self.progressFill];

    self.continueButton = [YLComponents filledButtonWithTitle:@"继续阅读"
                                                        target:self
                                                        action:@selector(continueReading)];
    [self.bookCard addSubview:self.continueButton];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(continueReading)];
    [self.bookCard addGestureRecognizer:tap];

    // 统计磁贴
    self.statsTitleLabel = [YLComponents labelWithFont:[theme uiFontOfSize:13
                                                                     weight:UIFontWeightSemibold]
                                                 color:theme.secondaryTextColor];
    self.statsTitleLabel.text = @"阅读统计";
    [self.scroll addSubview:self.statsTitleLabel];

    self.timeTile = [self statTileWithTitle:@"累计阅读" icon:@"clock" style:0];
    self.timeValueLabel = (UILabel *)[self.timeTile viewWithTag:101];
    [self.scroll addSubview:self.timeTile];

    self.countTile = [self statTileWithTitle:@"读过的书" icon:@"book" style:2];
    self.countValueLabel = (UILabel *)[self.countTile viewWithTag:101];
    [self.scroll addSubview:self.countTile];

    // 快捷入口
    self.actionsTitleLabel = [YLComponents labelWithFont:[theme uiFontOfSize:13
                                                                      weight:UIFontWeightSemibold]
                                                  color:theme.secondaryTextColor];
    self.actionsTitleLabel.text = @"快捷入口";
    [self.scroll addSubview:self.actionsTitleLabel];

    NSArray *items = @[
        @[@"cloud", @"云端书库"],
        @[@"books", @"我的书架"],
        @[@"refresh", @"同步进度"]
    ];
    for (NSInteger i = 0; i < (NSInteger)items.count; i += 1) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = 200 + i;
        [theme applyCardStyle:button];
        [button addTarget:self action:@selector(quickAction:)
         forControlEvents:UIControlEventTouchUpInside];

        UIView *iconBG = [[UIView alloc] initWithFrame:CGRectZero];
        iconBG.tag = 1;
        iconBG.userInteractionEnabled = NO;
        iconBG.layer.cornerRadius = 18;
        [button addSubview:iconBG];

        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        icon.tag = 3;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.image = [YLComponents iconNamed:items[i][0] size:18
                                       color:[theme tintForegroundForStyle:i]];
        icon.userInteractionEnabled = NO;
        [iconBG addSubview:icon];

        UILabel *label = [YLComponents labelWithFont:[theme uiFontOfSize:11.5
                                                                  weight:UIFontWeightMedium]
                                               color:theme.barTextColor];
        label.text = items[i][1];
        label.textAlignment = NSTextAlignmentCenter;
        label.tag = 2;
        label.userInteractionEnabled = NO;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.8;
        [button addSubview:label];
        [self.scroll addSubview:button];
    }
}

- (UIView *)statTileWithTitle:(NSString *)title icon:(NSString *)iconName style:(NSInteger)style {
    YLTheme *theme = [YLTheme shared];
    UIView *tile = [[UIView alloc] initWithFrame:CGRectZero];
    tile.layer.cornerRadius = 16;
    tile.layer.masksToBounds = YES;
    tile.tag = 300 + style;

    UIView *iconBG = [[UIView alloc] initWithFrame:CGRectZero];
    iconBG.backgroundColor = [[theme tintForegroundForStyle:style] colorWithAlphaComponent:0.14];
    iconBG.layer.cornerRadius = 8;
    iconBG.tag = 103;
    [tile addSubview:iconBG];

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
    icon.image = [YLComponents iconNamed:iconName size:12
                                   color:[theme tintForegroundForStyle:style]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tag = 104;
    [tile addSubview:icon];

    UILabel *name = [YLComponents labelWithFont:[theme uiFontOfSize:11.5
                                                               weight:UIFontWeightMedium]
                                          color:[theme tintForegroundForStyle:style]];
    name.text = title;
    name.tag = 102;
    name.alpha = 0.9;
    [tile addSubview:name];

    UILabel *value = [YLComponents labelWithFont:[theme uiFontOfSize:22
                                                                 weight:UIFontWeightBold]
                                           color:[theme tintForegroundForStyle:style]];
    value.text = @"--";
    value.tag = 101;
    value.adjustsFontSizeToFitWidth = YES;
    value.minimumScaleFactor = 0.6;
    [tile addSubview:value];
    return tile;
}

- (void)applyTheme {
    YLTheme *theme = [YLTheme shared];
    self.view.backgroundColor = theme.appBackground;
    self.scroll.backgroundColor = theme.appBackground;
    self.greetingLabel.textColor = theme.barTextColor;
    self.greetingSubLabel.textColor = theme.secondaryTextColor;
    [theme applyCardStyle:self.bookCard];
    self.bookNameLabel.textColor = theme.barTextColor;
    self.bookMetaLabel.textColor = theme.tertiaryTextColor;
    self.bookProgressText.textColor = theme.accentColor;
    self.progressTrack.backgroundColor = [theme.separatorColor colorWithAlphaComponent:0.55];
    self.progressFill.backgroundColor = theme.accentColor;
    self.statsTitleLabel.textColor = theme.secondaryTextColor;
    self.actionsTitleLabel.textColor = theme.secondaryTextColor;

    // 方向刷新后按钮背景/文字需要在浅色与夜间之间切换
    [self.continueButton setTitleColor:(theme.nightMode
        ? [UIColor colorWithRed:0.055 green:0.075 blue:0.125 alpha:1]
        : [UIColor whiteColor]) forState:UIControlStateNormal];
    self.continueButton.backgroundColor = theme.accentColor;

    NSArray *tiles = @[self.timeTile, self.countTile];
    NSArray *styles = @[@0, @2];
    for (NSInteger i = 0; i < (NSInteger)tiles.count; i += 1) {
        UIView *tile = tiles[i];
        NSInteger style = [styles[i] integerValue];
        tile.backgroundColor = [theme tintColorForStyle:style];
        ((UILabel *)[tile viewWithTag:101]).textColor = [theme tintForegroundForStyle:style];
        ((UILabel *)[tile viewWithTag:102]).textColor = [theme tintForegroundForStyle:style];
        ((UIView *)[tile viewWithTag:103]).backgroundColor =
            [[theme tintForegroundForStyle:style] colorWithAlphaComponent:0.14];
        ((UIImageView *)[tile viewWithTag:104]).image =
            [YLComponents iconNamed:(style == 0 ? @"clock" : @"book") size:12
                               color:[theme tintForegroundForStyle:style]];
    }

    for (NSInteger i = 0; i < 3; i += 1) {
        UIButton *button = (UIButton *)[self.scroll viewWithTag:200 + i];
        [theme applyCardStyle:button];
        UIView *iconBG = [button viewWithTag:1];
        iconBG.backgroundColor = [theme tintColorForStyle:i];
        UIImageView *icon = (UIImageView *)[iconBG viewWithTag:3];
        icon.image = [YLComponents iconNamed:(i == 0 ? @"cloud" : (i == 1 ? @"books" : @"refresh"))
                                        size:18
                                       color:[theme tintForegroundForStyle:i]];
        ((UILabel *)[button viewWithTag:2]).textColor = theme.barTextColor;
    }
}

- (void)layoutUI {
    CGFloat w = self.view.bounds.size.width;
    self.scroll.frame = self.view.bounds;

    CGFloat pad = [[YLTheme shared] screenPadding];
    CGFloat y = 8;

    self.greetingLabel.frame = CGRectMake(pad, y, w - pad * 2, 34);
    y += 36;
    self.greetingSubLabel.frame = CGRectMake(pad, y, w - pad * 2, 18);
    y += 26;

    // 当前书籍卡片：左封面 + 右信息
    CGFloat cardW = w - pad * 2;
    CGFloat cardH = 150;
    self.bookCard.frame = CGRectMake(pad, y, cardW, cardH);
    CGFloat inner = 14;
    CGFloat coverW = 76, coverH = 106;
    self.coverView.frame = CGRectMake(inner, inner, coverW, coverH);

    CGFloat textX = inner + coverW + 14;
    CGFloat textW = cardW - textX - inner;
    self.bookNameLabel.frame = CGRectMake(textX, inner, textW, 42);
    self.bookMetaLabel.frame = CGRectMake(textX, inner + 44, textW, 16);
    self.bookProgressText.frame = CGRectMake(textX, inner + 64, textW, 16);
    self.progressTrack.frame = CGRectMake(textX, inner + 86, textW, 6);
    [self layoutProgressFill];
    self.continueButton.frame = CGRectMake(textX, inner + 100, 96, 32);
    y += cardH + 18;

    self.statsTitleLabel.frame = CGRectMake(pad, y, 120, 18);
    y += 26;

    CGFloat tileW = (cardW - 12) / 2.0;
    self.timeTile.frame = CGRectMake(pad, y, tileW, 86);
    self.countTile.frame = CGRectMake(pad + tileW + 12, y, tileW, 86);
    [self layoutTile:self.timeTile];
    [self layoutTile:self.countTile];
    y += 86 + 18;

    self.actionsTitleLabel.frame = CGRectMake(pad, y, 120, 18);
    y += 26;

    CGFloat iconW = (cardW - 24) / 3.0;
    for (NSInteger i = 0; i < 3; i += 1) {
        UIButton *button = (UIButton *)[self.scroll viewWithTag:200 + i];
        button.frame = CGRectMake(pad + i * (iconW + 12), y, iconW, 84);
        UIView *iconBG = [button viewWithTag:1];
        iconBG.frame = CGRectMake((iconW - 36) / 2.0, 14, 36, 36);
        ((UIImageView *)[iconBG viewWithTag:3]).frame = CGRectMake(9, 9, 18, 18);
        ((UILabel *)[button viewWithTag:2]).frame = CGRectMake(6, 56, iconW - 12, 18);
    }
    y += 84 + 24;

    self.scroll.contentSize = CGSizeMake(w, y);
}

- (void)layoutTile:(UIView *)tile {
    CGFloat w = tile.bounds.size.width;
    ((UIView *)[tile viewWithTag:103]).frame = CGRectMake(12, 12, 20, 20);
    ((UIImageView *)[tile viewWithTag:104]).frame = CGRectMake(12 + 4, 12 + 4, 12, 12);
    ((UILabel *)[tile viewWithTag:102]).frame = CGRectMake(38, 12, w - 50, 20);
    ((UILabel *)[tile viewWithTag:101]).frame = CGRectMake(12, 38, w - 24, 34);
}

- (void)layoutProgressFill {
    CGFloat ratio = [self overallRatioForBook:self.currentBook];
    CGFloat tw = self.progressTrack.bounds.size.width;
    self.progressFill.frame = CGRectMake(0, 0, tw * ratio, 6);
}

#pragma mark - 进度计算（全书）

- (CGFloat)ratioFromProgress:(NSDictionary *)progress {
    if (![progress isKindOfClass:[NSDictionary class]]) { return 0; }
    id value = progress[@"ratio"] ?: progress[@"percent"] ?: progress[@"progress"];
    CGFloat ratio = 0;
    if ([value respondsToSelector:@selector(doubleValue)]) {
        ratio = [value doubleValue];
        if (ratio > 1) { ratio = ratio / 100.0; }
    }
    return MIN(1.0, MAX(0.0, ratio));
}

- (NSInteger)chapterCountForBook:(NSDictionary *)book progress:(NSDictionary *)progress {
    NSInteger count = [book[@"chapterCount"] integerValue];
    if (count <= 0) { count = [progress[@"chapterCount"] integerValue]; }
    return MAX(0, count);
}

- (CGFloat)overallRatioForBook:(NSDictionary *)book {
    if (![book isKindOfClass:[NSDictionary class]]) { return 0; }
    NSDictionary *progress = book[@"progress"];
    if (![progress isKindOfClass:[NSDictionary class]]) { return 0; }
    CGFloat ratio = [self ratioFromProgress:progress];
    NSInteger count = [self chapterCountForBook:book progress:progress];
    NSInteger index = [progress[@"chapterIndex"] integerValue];
    if (count > 0 && index >= 0 && index < count) {
        CGFloat overall = ((CGFloat)index + ratio) / (CGFloat)count;
        return MIN(1.0, MAX(0.0, overall));
    }
    return ratio;
}

#pragma mark - 数据

- (void)reload {
    __weak HomeViewController *weakSelf = self;
    [[API shared] get:@"/api/shelf" query:nil completion:^(id result, NSError *error) {
        HomeViewController *s = weakSelf; if (!s || error) { return; }
        NSDictionary *payload = [result isKindOfClass:[NSDictionary class]] ? result : nil;
        NSArray *books = [payload[@"books"] isKindOfClass:[NSArray class]] ? payload[@"books"] : @[];
        [s pickCurrentBookFrom:books];
        [s updateBookCard];
        [s autoResumeIfNeeded];
    }];
    [[API shared] post:@"/api/stats" body:@{} completion:^(id result, NSError *error) {
        HomeViewController *s = weakSelf; if (!s) { return; }
        s.stats = (!error && [result isKindOfClass:[NSDictionary class]]) ? result : @{};
        [s updateStatsAnimated];
    }];
}

- (void)pickCurrentBookFrom:(NSArray *)books {
    NSDictionary *best = nil;
    long long bestTime = 0;
    for (NSDictionary *book in books) {
        NSDictionary *progress = book[@"progress"];
        if (![progress isKindOfClass:[NSDictionary class]]) { continue; }
        id timeValue = progress[@"updatedAt"];
        long long time = [timeValue respondsToSelector:@selector(longLongValue)]
            ? [timeValue longLongValue] : 0;
        if (time > bestTime) { bestTime = time; best = book; }
    }
    self.currentBook = best;
}

- (void)updateBookCard {
    YLTheme *theme = [YLTheme shared];
    NSDictionary *book = self.currentBook;
    if (book) {
        self.bookNameLabel.text = book[@"name"] ?: @"未命名";
        NSString *author = book[@"author"];
        if (![author isKindOfClass:[NSString class]] || !author.length) { author = @"未知作者"; }
        NSString *source = book[@"sourceName"];
        if (![source isKindOfClass:[NSString class]] || !source.length) {
            source = [book[@"local"] boolValue] ? @"本地" : @"在线";
        }
        self.bookMetaLabel.text = [NSString stringWithFormat:@"%@ · %@", author, source];

        NSDictionary *progress = [book[@"progress"] isKindOfClass:[NSDictionary class]]
            ? book[@"progress"] : nil;
        CGFloat overall = [self overallRatioForBook:book];
        NSInteger percent = (NSInteger)lround(overall * 100.0);
        NSInteger count = [self chapterCountForBook:book progress:progress];
        NSInteger index = [progress[@"chapterIndex"] integerValue];
        if (count > 0) {
            self.bookProgressText.text = [NSString stringWithFormat:@"全书 %ld%% · 第 %ld/%ld 章",
                (long)percent, (long)MIN(count, MAX(1, index + 1)), (long)count];
        } else if (progress) {
            // 目录还没缓存到本机时拿不到总章数，此时只显示章节内进度，
            // 不要把它误标成“全书进度”。
            self.bookProgressText.text = [NSString stringWithFormat:@"第 %ld 章 · 本章 %ld%%",
                (long)MAX(1, index + 1), (long)percent];
        } else {
            self.bookProgressText.text = @"尚未开始阅读";
        }
        self.greetingSubLabel.text = [NSString stringWithFormat:@"继续《%@》", book[@"name"] ?: @"这本书"];
        self.continueButton.hidden = NO;
        self.continueButton.userInteractionEnabled = YES;
        [self loadCoverForBook:book];
        self.bookCard.alpha = 1;
    } else {
        self.bookNameLabel.text = @"还没有阅读记录";
        self.bookMetaLabel.text = @"从书架或云端添加一本";
        self.bookProgressText.text = @"开始阅读后，这里会显示全书进度";
        self.greetingSubLabel.text = @"把碎片时间留给一本书";
        self.continueButton.hidden = YES;
        self.continueButton.userInteractionEnabled = NO;
        self.coverView.image = [self placeholderCoverFor:@"书" theme:theme];
    }
    [self layoutProgressFill];
}

- (void)updateStatsAnimated {
    // 使用云端同步后的总时长（本机+其他设备），回退到本机 NSUserDefaults
    NSInteger totalSeconds = [self.stats[@"totalSeconds"] integerValue];
    if (totalSeconds <= 0) {
        totalSeconds = (NSInteger)[[NSUserDefaults standardUserDefaults]
            doubleForKey:@"yl.stats.readSeconds"];
    }
    NSInteger minutes = totalSeconds / 60;
    NSInteger booksRead = [self.stats[@"booksRead"] integerValue];

    self.animTimeTarget = minutes;
    self.animCountTarget = booksRead;
    self.animTimeShown = 0;
    self.animCountShown = 0;
    [self.animTimer invalidate];
    // 数字递增动画，约 0.6 秒内完成
    self.animTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0
                                                       target:self
                                                     selector:@selector(tickAnim)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)tickAnim {
    BOOL done = YES;
    if (self.animTimeShown < self.animTimeTarget) {
        NSInteger step = MAX(1, (self.animTimeTarget - self.animTimeShown) / 6);
        self.animTimeShown = MIN(self.animTimeTarget, self.animTimeShown + step);
        done = NO;
    }
    if (self.animCountShown < self.animCountTarget) {
        NSInteger step = MAX(1, (self.animCountTarget - self.animCountShown) / 6);
        self.animCountShown = MIN(self.animCountTarget, self.animCountShown + step);
        done = NO;
    }
    [self renderStatLabels];
    if (done) { [self.animTimer invalidate]; self.animTimer = nil; }
}

- (void)renderStatLabels {
    // 时长：分钟 -> “X分钟 / X小时 / X小时Y分”
    NSInteger m = self.animTimeShown;
    if (m < 1) {
        self.timeValueLabel.text = @"<1分";
    } else if (m < 60) {
        self.timeValueLabel.text = [NSString stringWithFormat:@"%ld分", (long)m];
    } else {
        NSInteger h = m / 60, mm = m % 60;
        self.timeValueLabel.text = mm ? [NSString stringWithFormat:@"%ld时%ld分", (long)h, (long)mm]
                                      : [NSString stringWithFormat:@"%ld小时", (long)h];
    }
    self.countValueLabel.text = [NSString stringWithFormat:@"%ld本", (long)self.animCountShown];
}

#pragma mark - 封面

- (void)loadCoverForBook:(NSDictionary *)book {
    YLTheme *theme = [YLTheme shared];
    NSString *path = book[@"coverPath"];
    if ([path isKindOfClass:[NSString class]] && path.length) {
        UIImage *cached = YLHomeCoverCache()[path];
        if (cached) { self.coverView.image = cached; return; }
        UIImage *img = [UIImage imageWithContentsOfFile:path];
        if (img) { YLHomeCoverCache()[path] = img; self.coverView.image = img; return; }
    }
    NSString *name = book[@"name"] ?: @"书";
    self.coverView.image = [self placeholderCoverFor:name theme:theme];
}

- (UIImage *)placeholderCoverFor:(NSString *)name theme:(YLTheme *)theme {
    NSString *title = name.length ? name : @"未命名";
    NSString *key = [@"ph|" stringByAppendingString:title];
    UIImage *cached = YLHomeCoverCache()[key];
    if (cached) { return cached; }
    CGSize sz = CGSizeMake(76, 106);
    UIGraphicsBeginImageContextWithOptions(sz, YES, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[] = {0.204,0.435,0.925,1.0, 0.365,0.545,0.980,1.0};
    CGGradientRef grad = CGGradientCreateWithColorComponents(space, comps, (CGFloat[]){0,1}, 2);
    CGContextDrawLinearGradient(ctx, grad, CGPointZero, CGPointMake(0, sz.height), 0);
    CGGradientRelease(grad); CGColorSpaceRelease(space);

    // 右下角留一层淡淡的浅色弧，避免纯色封面显得单调
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.08].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(sz.width * 0.35, sz.height * 0.62,
                                               sz.width, sz.width));

    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    ps.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *attrs = @{NSFontAttributeName:[UIFont boldSystemFontOfSize:12],
                            NSForegroundColorAttributeName:[UIColor whiteColor],
                            NSParagraphStyleAttributeName:ps};
    CGRect tr = CGRectInset(CGRectMake(0, 0, sz.width, sz.height), 6, 8);
    CGSize ts = [title boundingRectWithSize:tr.size
                                    options:NSStringDrawingUsesLineFragmentOrigin
                                 attributes:attrs context:nil].size;
    tr.size.height = MIN(ts.height, tr.size.height);
    tr.origin.y = (sz.height - tr.size.height) / 2.0;
    [title drawWithRect:tr options:NSStringDrawingUsesLineFragmentOrigin
             attributes:attrs context:nil];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (img) { YLHomeCoverCache()[key] = img; }
    return img;
}

#pragma mark - 操作

- (void)autoResumeIfNeeded {
    if (!self.autoResumePending) { return; }
    self.autoResumePending = NO;

    // 启动时 AppDelegate 可能已经直接把阅读器压栈，避免再推一次。
    if ([self.navigationController.topViewController isKindOfClass:[ReaderViewController class]]) {
        return;
    }

    // 只有“上次从阅读页退出”才自动续读；否则停留在主页。
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (![ud boolForKey:@"yl.lastWasInReader"]) { return; }

    NSString *lastKey = [ud stringForKey:@"yl.lastReadingBookKey"];
    if (!lastKey.length) { [ud setBool:NO forKey:@"yl.lastWasInReader"]; return; }

    if (self.currentBook && [self.currentBook[@"key"] isEqualToString:lastKey]) {
        [ud setBool:NO forKey:@"yl.lastWasInReader"];
        [self continueReading];
        return;
    }
    // 当前书不对（或还没加载到）时，从书架里精确查找
    __weak HomeViewController *weakSelf = self;
    [[API shared] get:@"/api/shelf" query:nil completion:^(id result, NSError *error) {
        HomeViewController *s = weakSelf;
        if (!s) { return; }
        NSDictionary *payload = [result isKindOfClass:[NSDictionary class]] ? result : nil;
        NSArray *books = [payload[@"books"] isKindOfClass:[NSArray class]] ? payload[@"books"] : @[];
        for (NSDictionary *book in books) {
            if ([book[@"key"] isEqualToString:lastKey]) {
                [ud setBool:NO forKey:@"yl.lastWasInReader"];
                [s openBook:book];
                return;
            }
        }
    }];
}

- (void)continueReading {
    if (!self.currentBook) {
        [self openShelf];
        return;
    }
    [self openBook:self.currentBook];
}

- (void)openBook:(NSDictionary *)book {
    if (![book isKindOfClass:[NSDictionary class]]) { return; }
    NSString *key = book[@"key"];
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    if ([key isKindOfClass:[NSString class]] && key.length) { body[@"key"] = key; }
    __weak HomeViewController *weakSelf = self;
    [[API shared] post:@"/api/sync/pullBook" body:body
            completion:^(id result, NSError *error) {
        HomeViewController *s = weakSelf; if (!s) { return; }
        [s pushReaderForBookWithKey:key fallback:book];
    }];
}

- (void)pushReaderForBookWithKey:(NSString *)key fallback:(NSDictionary *)fallback {
    // 防止连续点击同一本书打开多个阅读窗口
    static NSString *lastReadingKey = nil;
    static NSTimeInterval lastReadingTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if ([key isKindOfClass:[NSString class]] && key.length &&
        [lastReadingKey isEqualToString:key] &&
        (now - lastReadingTime) < 2.0) {
        return;
    }
    lastReadingKey = key;
    lastReadingTime = now;

    __weak HomeViewController *weakSelf = self;
    [[API shared] get:@"/api/shelf" query:nil completion:^(id result, NSError *error) {
        HomeViewController *s = weakSelf; if (!s) { return; }
        NSDictionary *book = fallback;
        if (!error) {
            NSDictionary *payload = [result isKindOfClass:[NSDictionary class]] ? result : nil;
            NSArray *books = [payload[@"books"] isKindOfClass:[NSArray class]] ? payload[@"books"] : @[];
            if ([key isKindOfClass:[NSString class]] && key.length) {
                for (NSDictionary *c in books) {
                    if ([c[@"key"] isEqualToString:key]) { book = c; break; }
                }
            }
        }
        // 检查当前导航栈中是否已存在该书的阅读器
        UIViewController *topVC = s.navigationController.topViewController;
        if ([topVC isKindOfClass:[ReaderViewController class]]) {
            NSDictionary *currentBook = [(ReaderViewController *)topVC valueForKey:@"book"] ?: @{};
            if ([currentBook[@"key"] isEqualToString:key]) {
                return;
            }
        }
        ReaderViewController *reader = [[ReaderViewController alloc] initWithBook:book];
        [s.navigationController pushViewController:reader animated:YES];
    }];
}

- (void)quickAction:(UIButton *)btn {
    NSInteger idx = btn.tag - 200;
    if (idx == 0) {
        CloudViewController *c = [[CloudViewController alloc] init];
        [self.navigationController pushViewController:c animated:YES];
    } else if (idx == 1) {
        [self openShelf];
    } else {
        [self syncNow];
    }
}

- (void)syncNow {
    __weak HomeViewController *weakSelf = self;
    [[API shared] post:@"/api/sync/pull" body:@{} completion:^(id r, NSError *e) {
        [[API shared] post:@"/api/sync/push" body:@{} completion:^(id r2, NSError *e2) {
            HomeViewController *s = weakSelf; if (!s) { return; }
            [s showMessage:e2 ? e2.localizedDescription : @"同步完成"];
            [s reload];
        }];
    }];
}

- (void)openShelf {
    BookshelfViewController *c = [[BookshelfViewController alloc] init];
    [self.navigationController pushViewController:c animated:YES];
}

- (void)showSettings {
    SettingsViewController *c = [[SettingsViewController alloc] initWithStyle:UITableViewStyleGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:c];
    [[YLTheme shared] applyAppearance];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)showMessage:(NSString *)text {
    if (!text.length) { return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:text
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
