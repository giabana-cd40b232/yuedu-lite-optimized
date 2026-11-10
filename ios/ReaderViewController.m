#import "ReaderViewController.h"
#import "API.h"
#import "TocViewController.h"
#import "YLComponents.h"
#import "YLTheme.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>

#pragma mark - 单页显示

@interface YLPageViewController : UIViewController
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, assign) NSInteger pageNumber;
@property (nonatomic, copy) NSAttributedString *pageText;
@end

@implementation YLPageViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                     UIViewAutoresizingFlexibleHeight;
    self.textView.backgroundColor = [UIColor clearColor];
    self.textView.editable = NO;
    self.textView.selectable = NO;
    self.textView.scrollEnabled = NO;
    self.textView.userInteractionEnabled = NO;
    self.textView.textContainerInset = UIEdgeInsetsZero;
    self.textView.textContainer.lineFragmentPadding = 0;
    self.textView.contentInset = UIEdgeInsetsZero;
    if ([self.textView respondsToSelector:@selector(setLayoutMargins:)]) {
        self.textView.layoutMargins = UIEdgeInsetsZero;
    }
    self.textView.attributedText = self.pageText;
    [self.view addSubview:self.textView];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.textView.frame = self.view.bounds;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.textView.frame = self.view.bounds;
}

- (void)setPageText:(NSAttributedString *)pageText {
    _pageText = [pageText copy];
    if (self.isViewLoaded) {
        self.textView.attributedText = _pageText;
    }
}

@end

#pragma mark - 阅读器

@interface ReaderViewController () <
    UIPageViewControllerDelegate,
    UIPageViewControllerDataSource,
    UITextViewDelegate,
    UIGestureRecognizerDelegate,
    AVSpeechSynthesizerDelegate>

@property (nonatomic, strong) NSDictionary *book;
@property (nonatomic, strong) NSArray *chapters;
@property (nonatomic, assign) NSInteger chapterIndex;
@property (nonatomic, copy) NSString *chapterTitle;
@property (nonatomic, copy) NSString *chapterText;
@property (nonatomic, copy) NSString *rawChapterText;
@property (nonatomic, assign) NSInteger chapterHeaderLength;
@property (nonatomic, assign) NSInteger pendingPosition;
@property (nonatomic, assign) CGFloat pendingRatio;
@property (nonatomic, assign) NSInteger loadSequence;

@property (nonatomic, strong) UITextView *scrollTextView;
@property (nonatomic, strong) UIPageViewController *pagedController;
@property (nonatomic, strong) NSMutableArray *pageRanges;
@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, assign) CGRect textArea;
@property (nonatomic, assign) CGSize lastTextAreaSize;
@property (nonatomic, assign) BOOL rebuilding;

@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *pageLabel;
@property (nonatomic, strong) UILabel *headerLabel;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, strong) UIButton *ttsButton;
@property (nonatomic, strong) NSMutableArray *chromeButtons;
@property (nonatomic, assign) BOOL barsHidden;

@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIScrollView *panelScroll;
@property (nonatomic, strong) NSMutableArray *panelLabels;
@property (nonatomic, strong) NSMutableArray *panelButtons;
@property (nonatomic, strong) NSMutableArray *themeSwatches;
@property (nonatomic, strong) UILabel *fontSizeValueLabel;
@property (nonatomic, strong) UILabel *lineSpacingValueLabel;
@property (nonatomic, strong) UILabel *paragraphSpacingValueLabel;
@property (nonatomic, strong) UILabel *letterSpacingValueLabel;
@property (nonatomic, strong) UILabel *insetLeftValueLabel;
@property (nonatomic, strong) UILabel *insetRightValueLabel;
@property (nonatomic, strong) UILabel *insetTopValueLabel;
@property (nonatomic, strong) UILabel *insetBottomValueLabel;
@property (nonatomic, strong) UIButton *fontButton;
@property (nonatomic, strong) UILabel *chapterTitleSizeValueLabel;
@property (nonatomic, strong) UIButton *chapterTitleFontButton;
@property (nonatomic, strong) UIButton *chapterTitleWeightButton;
@property (nonatomic, strong) UISegmentedControl *modeSegment;
@property (nonatomic, strong) UISegmentedControl *animSegment;
@property (nonatomic, strong) UIButton *pageModeButton;
@property (nonatomic, strong) UIButton *pageAnimButton;
@property (nonatomic, strong) UISwitch *titleSwitch;
@property (nonatomic, strong) UISwitch *headerSwitch;
@property (nonatomic, strong) UISwitch *footerSwitch;
@property (nonatomic, strong) UISwitch *boldSwitch;
@property (nonatomic, strong) UISwitch *italicSwitch;

@property (nonatomic, strong) AVSpeechSynthesizer *synthesizer;
@property (nonatomic, assign) BOOL speechActive;
@property (nonatomic, assign) BOOL speechPaused;
@property (nonatomic, assign) NSInteger speechFinished;
@property (nonatomic, assign) NSInteger speechTotal;
@property (nonatomic, strong) NSDate *sessionStart;
@property (nonatomic, copy) NSArray *bookmarks;
@property (nonatomic, strong) UILabel *bookmarkMark;
@property (nonatomic, assign) BOOL chromeChangePending;

@end

@implementation ReaderViewController

#pragma mark - 生命周期

- (instancetype)initWithBook:(NSDictionary *)book {
    return [self initWithBook:book chapters:nil index:0];
}

- (instancetype)initWithBook:(NSDictionary *)book
                    chapters:(NSArray *)chapters
                       index:(NSInteger)index {
    self = [super init];
    if (self) {
        _book = [book isKindOfClass:[NSDictionary class]] ? book : @{};
        _chapters = [chapters isKindOfClass:[NSArray class]] ? chapters : nil;
        _chapterIndex = MAX(0, index);
        _pendingPosition = 0;
        _pendingRatio = 0;
        _pageRanges = [NSMutableArray array];
        _chromeButtons = [NSMutableArray array];
        _panelLabels = [NSMutableArray array];
        _panelButtons = [NSMutableArray array];
        _themeSwatches = [NSMutableArray array];
        _pageIndex = 0;
        _barsHidden = NO;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.automaticallyAdjustsScrollViewInsets = NO;
    self.title = self.book[@"name"] ?: @"阅读";

    [self buildScrollTextView];
    [self buildChrome];
    [self buildSpinner];
    [self buildPanel];
    [self updateLayoutMetrics];
    [self ensureContentMode];
    [self applyChromeTheme];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    tap.delegate = self;
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];

    self.synthesizer = [[AVSpeechSynthesizer alloc] init];
    self.synthesizer.delegate = self;

    if (self.chapters.count) {
        [self loadChapterAtIndex:self.chapterIndex position:0 direction:YES animated:NO];
    } else {
        [self loadChapters];
    }
    [self refreshBookmarks];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    self.navigationController.toolbarHidden = YES;
    [self applyChromeTheme];
    [self setNeedsStatusBarAppearanceUpdate];
    // 记录“当前正在阅读页”，App 被系统杀掉后下次启动可以直接回到阅读器。
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:@"yl.lastWasInReader"];
    NSString *key = self.book[@"key"];
    if ([key isKindOfClass:[NSString class]] && key.length) {
        [defaults setObject:key forKey:@"yl.lastReadingBookKey"];
    }
    // 只保存 plist 安全的基本字段，避免 NSNull 之类的 JSON 值写进 NSUserDefaults。
    NSMutableDictionary *lastBook = [NSMutableDictionary dictionary];
    NSArray *fields = @[@"key", @"name", @"author", @"sourceUrl",
                        @"bookUrl", @"coverPath", @"sourceName"];
    for (NSString *field in fields) {
        id value = self.book[field];
        if ([value isKindOfClass:[NSString class]] && [value length]) {
            lastBook[field] = value;
        }
    }
    if ([self.book[@"local"] respondsToSelector:@selector(boolValue)]) {
        lastBook[@"local"] = @([self.book[@"local"] boolValue]);
    }
    if (lastBook.count) {
        [defaults setObject:lastBook forKey:@"yl.lastReadingBook"];
    }
    [defaults synchronize];
    // 统计累计阅读时长
    self.sessionStart = [NSDate date];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // 只有被 pop（返回书架/主页）时才清除标记；打开目录等子页面时保持。
    if (self.isMovingFromParentViewController ||
        self.navigationController.isBeingDismissed) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:NO forKey:@"yl.lastWasInReader"];
        [defaults synchronize];
    }
    [self stopSpeech];
    [self saveProgress];
    // 统计累计阅读时长（超过 1 秒才算，避免误触进出累计一堆 0 秒）
    if (self.sessionStart) {
        NSTimeInterval seconds = [[NSDate date] timeIntervalSinceDate:self.sessionStart];
        if (seconds > 1) {
            [[API shared] post:@"/api/stats/add"
                          body:@{@"seconds": @((NSInteger)seconds)}
                    completion:nil];
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            double total = [defaults doubleForKey:@"yl.stats.readSeconds"] + seconds;
            [defaults setDouble:total forKey:@"yl.stats.readSeconds"];
        }
        self.sessionStart = nil;
    }
    // 退出阅读页立刻上传这本书的进度（跳过 30 秒节流），
    // 安卓端马上就能看到最新位置。
    NSString *key = self.book[@"key"];
    if ([key isKindOfClass:[NSString class]] && key.length) {
        [[API shared] post:@"/api/sync/pushBook" body:@{@"key": key}
                completion:nil];
    }
    [self.navigationController setNavigationBarHidden:NO animated:NO];
    self.navigationController.toolbarHidden = NO;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize oldSize = self.textArea.size;
    [self updateLayoutMetrics];
    self.pagedController.view.frame = self.textArea;
    self.scrollTextView.frame = self.textArea;
    self.spinner.center = CGPointMake(CGRectGetMidX(self.textArea),
                                      CGRectGetMidY(self.textArea));
    if (!self.panel.hidden) {
        [self layoutPanel];
    }

    BOOL sizeChanged = !CGSizeEqualToSize(oldSize, self.textArea.size);
    // 全屏切换会在 0.25 秒后统一重排，这里不再重复渲染，避免位置抖动
    if (sizeChanged && self.chapterText.length && !self.rebuilding &&
        !self.chromeChangePending) {
        NSInteger position = [self currentPosition];
        [self renderChapterAtPosition:position direction:YES animated:NO];
    }
    [self updateChrome];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return [YLTheme shared].readerTheme == YLReaderThemeNight
        ? UIStatusBarStyleLightContent : UIStatusBarStyleDefault;
}

#pragma mark - 搭建界面

- (void)buildScrollTextView {
    self.scrollTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.scrollTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                           UIViewAutoresizingFlexibleHeight;
    self.scrollTextView.backgroundColor = [UIColor clearColor];
    self.scrollTextView.editable = NO;
    self.scrollTextView.selectable = NO;
    self.scrollTextView.alwaysBounceVertical = YES;
    self.scrollTextView.showsVerticalScrollIndicator = NO;
    self.scrollTextView.textContainerInset = UIEdgeInsetsZero;
    self.scrollTextView.textContainer.lineFragmentPadding = 0;
    self.scrollTextView.delegate = self;
    self.scrollTextView.hidden = YES;
    [self.view insertSubview:self.scrollTextView atIndex:0];
}

// 顶部工具条改成图标按钮：返回 / 目录 / 同步 / 书签 / Aa
- (UIButton *)barButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [[YLTheme shared] uiFontOfSize:13 weight:UIFontWeightMedium];
    button.tintColor = [[YLTheme shared] accentColor];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.chromeButtons addObject:button];
    return button;
}

- (UIButton *)iconBarButton:(NSString *)icon action:(SEL)action {
    UIImage *image = [YLComponents iconNamed:icon size:21
                                       color:[[YLTheme shared] accentColor]];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:image forState:UIControlStateNormal];
    button.tintColor = [[YLTheme shared] accentColor];
    button.adjustsImageWhenHighlighted = NO;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.chromeButtons addObject:button];
    return button;
}

- (void)buildChrome {
    YLTheme *theme = [YLTheme shared];
    self.topBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.topBar.backgroundColor = [theme barBackground];
    [self.view addSubview:self.topBar];

    self.bottomBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.bottomBar.backgroundColor = [theme barBackground];
    [self.view addSubview:self.bottomBar];

    // 页眉 / 页脚：独立于上下工具条，工具条隐藏时也一直显示。
    self.headerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.headerLabel.font = [theme uiFontOfSize:11 weight:UIFontWeightRegular];
    self.headerLabel.textColor = [theme readerSecondaryColor];
    self.headerLabel.alpha = 0.72;
    self.headerLabel.textAlignment = NSTextAlignmentCenter;
    self.headerLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.view addSubview:self.headerLabel];

    self.footerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.footerLabel.font = [theme uiFontOfSize:11 weight:UIFontWeightRegular];
    self.footerLabel.textColor = [theme readerSecondaryColor];
    self.footerLabel.alpha = 0.72;
    self.footerLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.footerLabel];

    UIView *topLine = [[UIView alloc] initWithFrame:CGRectZero];
    topLine.tag = 1001;
    topLine.backgroundColor = [theme separatorColor];
    [self.topBar addSubview:topLine];

    UIView *bottomLine = [[UIView alloc] initWithFrame:CGRectZero];
    bottomLine.tag = 1002;
    bottomLine.backgroundColor = [theme separatorColor];
    [self.bottomBar addSubview:bottomLine];

    UIButton *back = [self iconBarButton:@"back" action:@selector(goBack)];
    [self.topBar addSubview:back];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.font = [theme uiFontOfSize:15 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [theme barTextColor];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.topBar addSubview:self.titleLabel];

    UIButton *toc = [self barButton:@"目录" action:@selector(openToc)];
    toc.titleLabel.font = [theme uiFontOfSize:12 weight:UIFontWeightMedium];
    [self.bottomBar addSubview:toc];

    UIButton *appearance = [self barButton:@"Aa" action:@selector(togglePanel)];
    appearance.titleLabel.font = [theme uiFontOfSize:15 weight:UIFontWeightBold];
    [self.topBar addSubview:appearance];

    UIButton *bookmark = [self iconBarButton:@"bookmark" action:@selector(bookmarkTapped)];
    [self.topBar addSubview:bookmark];

    UIButton *sync = [self iconBarButton:@"refresh" action:@selector(syncTapped)];
    [self.topBar addSubview:sync];

    // 书签标记：当前页有书签时显示在文字区右上角
    self.bookmarkMark = [[UILabel alloc] initWithFrame:CGRectZero];
    self.bookmarkMark.text = @"🔖";
    self.bookmarkMark.font = [UIFont systemFontOfSize:18];
    self.bookmarkMark.hidden = YES;
    [self.view addSubview:self.bookmarkMark];

    UIButton *previous = [self barButton:@"上一章" action:@selector(previousChapter)];
    previous.titleLabel.font = [theme uiFontOfSize:12 weight:UIFontWeightMedium];
    [self.bottomBar addSubview:previous];

    self.pageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.pageLabel.font = [theme uiFontOfSize:12 weight:UIFontWeightMedium];
    self.pageLabel.textColor = [theme readerSecondaryColor];
    self.pageLabel.textAlignment = NSTextAlignmentCenter;
    [self.bottomBar addSubview:self.pageLabel];

    self.ttsButton = [self barButton:@"朗读" action:@selector(ttsTapped)];
    self.ttsButton.titleLabel.font = [theme uiFontOfSize:12 weight:UIFontWeightMedium];
    [self.bottomBar addSubview:self.ttsButton];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(ttsLongPressed:)];
    [self.ttsButton addGestureRecognizer:longPress];

    UIButton *next = [self barButton:@"下一章" action:@selector(nextChapter)];
    next.titleLabel.font = [theme uiFontOfSize:12 weight:UIFontWeightMedium];
    [self.bottomBar addSubview:next];
}

- (void)buildSpinner {
    self.spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
}

- (CGFloat)panelControlWidth {
    return MAX(280, self.view.bounds.size.width - 16);
}

- (void)buildPanel {
    self.dimView = [[UIView alloc] initWithFrame:CGRectZero];
    self.dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    self.dimView.hidden = YES;
    [self.view addSubview:self.dimView];
    UITapGestureRecognizer *dimTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hidePanel)];
    [self.dimView addGestureRecognizer:dimTap];

    self.panel = [[UIView alloc] initWithFrame:CGRectZero];
    self.panel.hidden = YES;
    self.panel.layer.cornerRadius = 16;
    self.panel.layer.masksToBounds = YES;
    self.panel.layer.borderWidth = 0.5;
    self.panel.layer.borderColor = [[YLTheme shared] cardBorderColor].CGColor;
    [self.view addSubview:self.panel];

    self.panelScroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.panelScroll.alwaysBounceVertical = YES;
    self.panelScroll.clipsToBounds = YES;
    self.panelScroll.showsVerticalScrollIndicator = YES;
    self.panelScroll.backgroundColor = [UIColor clearColor];
    [self.panel addSubview:self.panelScroll];

    UILabel *heading = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, 160, 28)];
    heading.text = @"排版";
    heading.font = [[YLTheme shared] uiFontOfSize:16 weight:UIFontWeightSemibold];
    heading.textColor = [[YLTheme shared] barTextColor];
    heading.tag = 1003;
    [self.panel addSubview:heading];
    [self.panelLabels addObject:heading];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    done.frame = CGRectMake(240, 8, 50, 28);
    [done setTitle:@"完成" forState:UIControlStateNormal];
    done.titleLabel.font = [[YLTheme shared] uiFontOfSize:14 weight:UIFontWeightSemibold];
    done.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [done addTarget:self action:@selector(hidePanel)
   forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:done];
    [self.panelButtons addObject:done];

    CGFloat width = [self panelControlWidth];
    CGFloat y = 2;
    const CGFloat rowHeight = 32;

    // 翻页/动画/字体：小号紧凑按钮（4S 竖屏不拥挤）
    CGFloat optW = MIN(132.0f, MAX(96.0f, width - 120.0f));
    [self panelLabel:@"翻页" frame:CGRectMake(14, y, 84, 30)];
    self.pageModeButton = [self panelOptionButton:CGRectMake(90, y + 3, optW, 24)
                                           action:@selector(togglePageMode)];
    [self.panelScroll addSubview:self.pageModeButton];
    [self.panelButtons addObject:self.pageModeButton];
    y += 30;

    [self panelLabel:@"动画" frame:CGRectMake(14, y, 84, 30)];
    self.pageAnimButton = [self panelOptionButton:CGRectMake(90, y + 3, optW, 24)
                                           action:@selector(togglePageAnim)];
    [self.panelScroll addSubview:self.pageAnimButton];
    [self.panelButtons addObject:self.pageAnimButton];
    y += 30;

    // 4S 高度只有 480pt：步进器排成两列，全部 10 行一屏放下、无需滚动。
    self.fontSizeValueLabel = [self addMiniStepper:CGRectMake(10, y, (width - 24) / 2.0, rowHeight)
        title:@"字号" minus:@selector(decreaseFontSize) plus:@selector(increaseFontSize)];
    self.lineSpacingValueLabel = [self addMiniStepper:CGRectMake(16 + (width - 24) / 2.0, y, (width - 24) / 2.0, rowHeight)
        title:@"行距" minus:@selector(decreaseLineSpacing) plus:@selector(increaseLineSpacing)];
    y += rowHeight;

    self.paragraphSpacingValueLabel = [self addMiniStepper:CGRectMake(10, y, (width - 24) / 2.0, rowHeight)
        title:@"段距" minus:@selector(decreaseParagraphSpacing) plus:@selector(increaseParagraphSpacing)];
    self.letterSpacingValueLabel = [self addMiniStepper:CGRectMake(16 + (width - 24) / 2.0, y, (width - 24) / 2.0, rowHeight)
        title:@"字距" minus:@selector(decreaseLetterSpacing) plus:@selector(increaseLetterSpacing)];
    y += rowHeight;

    self.insetLeftValueLabel = [self addMiniStepper:CGRectMake(10, y, (width - 24) / 2.0, rowHeight)
        title:@"左边" minus:@selector(decreaseInsetLeft) plus:@selector(increaseInsetLeft)];
    self.insetRightValueLabel = [self addMiniStepper:CGRectMake(16 + (width - 24) / 2.0, y, (width - 24) / 2.0, rowHeight)
        title:@"右边" minus:@selector(decreaseInsetRight) plus:@selector(increaseInsetRight)];
    y += rowHeight;

    self.insetTopValueLabel = [self addMiniStepper:CGRectMake(10, y, (width - 24) / 2.0, rowHeight)
        title:@"上边" minus:@selector(decreaseInsetTop) plus:@selector(increaseInsetTop)];
    self.insetBottomValueLabel = [self addMiniStepper:CGRectMake(16 + (width - 24) / 2.0, y, (width - 24) / 2.0, rowHeight)
        title:@"下边" minus:@selector(decreaseInsetBottom) plus:@selector(increaseInsetBottom)];
    y += rowHeight;

    [self panelLabel:@"字体" frame:CGRectMake(14, y, 84, 30)];
    self.fontButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.fontButton.frame = CGRectMake(90, y + 3, MIN(132.0f, MAX(96.0f, width - 120.0f)), 24);
    self.fontButton.contentHorizontalAlignment =
        UIControlContentHorizontalAlignmentLeft;
    self.fontButton.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    self.fontButton.titleLabel.font = [UIFont systemFontOfSize:12];
    self.fontButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.fontButton.titleLabel.minimumScaleFactor = 0.75;
    self.fontButton.layer.cornerRadius = 5;
    self.fontButton.layer.borderWidth = 1;
    [self.fontButton addTarget:self action:@selector(chooseFont)
              forControlEvents:UIControlEventTouchUpInside];
    [self.panelScroll addSubview:self.fontButton];
    [self.panelButtons addObject:self.fontButton];
    y += 30;

    [self panelLabel:@"背景" frame:CGRectMake(14, y, 84, rowHeight)];
    NSArray *swatchColors = @[
        [UIColor colorWithRed:0.988 green:0.984 blue:0.965 alpha:1],
        [UIColor colorWithRed:0.957 green:0.914 blue:0.824 alpha:1],
        [UIColor colorWithRed:0.902 green:0.937 blue:0.875 alpha:1],
        [UIColor colorWithRed:0.086 green:0.094 blue:0.110 alpha:1]
    ];
    CGFloat sw = 34, sg = 6, sx = 90;
    for (NSInteger i = 0; i < 4; i += 1) {
        UIButton *swatch = [UIButton buttonWithType:UIButtonTypeCustom];
        swatch.frame = CGRectMake(sx + i * (sw + sg), y + 3, sw, 26);
        swatch.tag = i;
        swatch.backgroundColor = swatchColors[i];
        swatch.layer.cornerRadius = 8;
        swatch.layer.borderWidth = 1;
        swatch.layer.borderColor = [[YLTheme shared] separatorColor].CGColor;
        [swatch addTarget:self action:@selector(themeSwatchTapped:)
         forControlEvents:UIControlEventTouchUpInside];
        [self.panelScroll addSubview:swatch];
        [self.themeSwatches addObject:swatch];
    }
    y += rowHeight;

    self.titleSwitch = [self addSwitchRow:@"章节标题" y:y
                                   action:@selector(displaySwitchChanged:)];
    y += rowHeight;

    // 章节标题样式：字号（0=跟随正文）/ 字体 / 字重
    self.chapterTitleSizeValueLabel = [self addMiniStepper:CGRectMake(10, y, (width - 24) / 2.0, rowHeight)
        title:@"标题字号"
   labelWidth:48
        minus:@selector(decreaseChapterTitleSize)
         plus:@selector(increaseChapterTitleSize)];
    self.chapterTitleWeightButton = [self panelOptionButton:CGRectMake(16 + (width - 24) / 2.0, y + 3,
        (width - 24) / 2.0 - 4, 24)
        action:@selector(toggleChapterTitleWeight)];
    [self.panelScroll addSubview:self.chapterTitleWeightButton];
    [self.panelButtons addObject:self.chapterTitleWeightButton];
    y += rowHeight;

    [self panelLabel:@"标题字体" frame:CGRectMake(14, y, 84, 30)];
    self.chapterTitleFontButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.chapterTitleFontButton.frame = CGRectMake(90, y + 3,
        MIN(132.0f, MAX(96.0f, width - 120.0f)), 24);
    self.chapterTitleFontButton.contentHorizontalAlignment =
        UIControlContentHorizontalAlignmentLeft;
    self.chapterTitleFontButton.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    self.chapterTitleFontButton.titleLabel.font = [UIFont systemFontOfSize:12];
    self.chapterTitleFontButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.chapterTitleFontButton.titleLabel.minimumScaleFactor = 0.75;
    self.chapterTitleFontButton.layer.cornerRadius = 6;
    self.chapterTitleFontButton.layer.borderWidth = 1;
    [self.chapterTitleFontButton addTarget:self action:@selector(chooseChapterTitleFont)
                          forControlEvents:UIControlEventTouchUpInside];
    [self.panelScroll addSubview:self.chapterTitleFontButton];
    [self.panelButtons addObject:self.chapterTitleFontButton];
    y += 30;

    // 页眉 / 页脚 并排一行（用相对位置，避免窄屏溢出）
    CGFloat mid = width / 2.0;
    [self panelLabel:@"页眉" frame:CGRectMake(14, y, 36, rowHeight)];
    self.headerSwitch = [self addSwitchAt:CGRectMake(mid - 58, y + 1, 51, 28)
                                   action:@selector(displaySwitchChanged:)];
    [self panelLabel:@"页脚" frame:CGRectMake(mid + 2, y, 36, rowHeight)];
    self.footerSwitch = [self addSwitchAt:CGRectMake(width - 60, y + 1, 51, 28)
                                   action:@selector(displaySwitchChanged:)];
    y += rowHeight;

    // 粗体 / 斜体（开关状态保存到主题，立即重排）
    [self panelLabel:@"粗体" frame:CGRectMake(14, y, 36, rowHeight)];
    self.boldSwitch = [self addSwitchAt:CGRectMake(mid - 58, y + 1, 51, 28)
                                 action:@selector(textStyleChanged:)];
    [self panelLabel:@"斜体" frame:CGRectMake(mid + 2, y, 36, rowHeight)];
    self.italicSwitch = [self addSwitchAt:CGRectMake(width - 60, y + 1, 51, 28)
                                   action:@selector(textStyleChanged:)];
    y += rowHeight;

    self.panelScroll.contentSize = CGSizeMake(width, y + 4);
    self.panelScroll.contentInset = UIEdgeInsetsZero;
    [self refreshPanelValues];
}

// 面板高度按内容精确计算；新增章节标题样式后 13 行，
// 4S（480pt 高）上允许轻微滚动，仍能完整操作。
- (CGFloat)panelContentHeight {
    return 13 * 32 + 6;
}

// 紧凑步进器：标签 + [-] 值 [+]，一列只占半个面板宽
- (UILabel *)addMiniStepper:(CGRect)frame
                      title:(NSString *)title
                      minus:(SEL)minusAction
                       plus:(SEL)plusAction {
    return [self addMiniStepper:frame title:title labelWidth:30
                          minus:minusAction plus:plusAction];
}

- (UILabel *)addMiniStepper:(CGRect)frame
                      title:(NSString *)title
                 labelWidth:(CGFloat)labelWidth
                      minus:(SEL)minusAction
                       plus:(SEL)plusAction {
    CGFloat x = frame.origin.x;
    CGFloat y = frame.origin.y;
    CGFloat w = frame.size.width;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(x, y, labelWidth, 30)];
    label.text = title;
    label.font = [UIFont systemFontOfSize:11];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.8;
    label.textColor = [[YLTheme shared] secondaryTextColor];
    [self.panelScroll addSubview:label];
    [self.panelLabels addObject:label];

    // 紧凑布局：按列宽自适应，防止 4S 上溢出
    CGFloat btn = 20, valW = 26;
    CGFloat right = x + w - 2;
    CGFloat plusX = right - btn;
    CGFloat valX = plusX - valW;
    CGFloat minusX = valX - btn;
    if (minusX < x + labelWidth + 2) {
        minusX = x + labelWidth + 2;
        valX = minusX + btn;
        plusX = valX + valW;
    }
    [self panelStepButton:@"-" action:minusAction
                    frame:CGRectMake(minusX, y + 5, btn, btn)];
    UILabel *value = [self panelValueLabel:CGRectMake(valX, y, valW, 30)];
    value.font = [UIFont systemFontOfSize:11];
    value.adjustsFontSizeToFitWidth = YES;
    value.minimumScaleFactor = 0.7;
    [self panelStepButton:@"+" action:plusAction
                    frame:CGRectMake(plusX, y + 5, btn, btn)];
    return value;
}

- (UISwitch *)addSwitchAt:(CGRect)frame action:(SEL)action {
    UISwitch *switcher = [[UISwitch alloc] initWithFrame:frame];
    switcher.onTintColor = [[YLTheme shared] accentColor];
    [switcher addTarget:self action:action
       forControlEvents:UIControlEventValueChanged];
    [self.panelScroll addSubview:switcher];
    return switcher;
}

- (UISwitch *)addSwitchRow:(NSString *)title y:(CGFloat)y action:(SEL)action {
    CGFloat width = [self panelControlWidth];
    [self panelLabel:title frame:CGRectMake(14, y, 84, 34)];
    UISwitch *switcher = [[UISwitch alloc]
        initWithFrame:CGRectMake(width - 66, y + 1, 51, 31)];
    switcher.onTintColor = [[YLTheme shared] accentColor];
    [switcher addTarget:self action:action
       forControlEvents:UIControlEventValueChanged];
    [self.panelScroll addSubview:switcher];
    return switcher;
}

- (UILabel *)panelLabel:(NSString *)text frame:(CGRect)frame {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.font = [UIFont systemFontOfSize:14];
    label.textColor = [[YLTheme shared] secondaryTextColor];
    [self.panelScroll addSubview:label];
    [self.panelLabels addObject:label];
    return label;
}

- (UILabel *)panelValueLabel:(CGRect)frame {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:16];
    label.textColor = [[YLTheme shared] barTextColor];
    [self.panelScroll addSubview:label];
    [self.panelLabels addObject:label];
    return label;
}

- (UIButton *)panelOptionButton:(CGRect)frame action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    button.titleLabel.font = [UIFont systemFontOfSize:12];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.75;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    button.layer.cornerRadius = 5;
    button.layer.borderWidth = 1;
    button.layer.borderColor = [[YLTheme shared] separatorColor].CGColor;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIButton *)panelStepButton:(NSString *)title action:(SEL)action frame:(CGRect)frame {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:20];
    button.tintColor = [[YLTheme shared] accentColor];
    button.backgroundColor = [[YLTheme shared] appBackground];
    button.layer.cornerRadius = 7;
    button.layer.borderWidth = 1;
    button.layer.borderColor = [[YLTheme shared] separatorColor].CGColor;
    button.tag = 2001;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.panelScroll addSubview:button];
    [self.panelButtons addObject:button];
    return button;
}

#pragma mark - 布局

- (void)updateLayoutMetrics {
    CGRect bounds = self.view.bounds;
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;
    // 工具条作为覆盖层淡入淡出，正文区域固定不变 → 全屏切换无重排、无卡顿
    YLTheme *theme = [YLTheme shared];
    CGFloat barTopH = 64, barBottomH = 46;
    BOOL showBars = !self.barsHidden;

    self.topBar.frame = CGRectMake(0, 0, width, barTopH);
    self.bottomBar.frame = CGRectMake(0, height - barBottomH, width, barBottomH);
    self.topBar.alpha = showBars ? 1 : 0;
    self.bottomBar.alpha = showBars ? 1 : 0;
    self.dimView.frame = bounds;

    UIView *topLine = [self.topBar viewWithTag:1001];
    topLine.frame = CGRectMake(0, barTopH - 0.5, width, 0.5);
    UIView *bottomLine = [self.bottomBar viewWithTag:1002];
    bottomLine.frame = CGRectMake(0, 0, width, 0.5);

    UIButton *back = self.chromeButtons[0];
    back.frame = CGRectMake(2, 20, 40, 44);

    CGFloat right = width - 4;
    UIButton *appearance = self.chromeButtons[2];
    appearance.frame = CGRectMake(right - 32, 26, 32, 32);
    right -= 36;
    UIButton *sync = self.chromeButtons[4];
    sync.frame = CGRectMake(right - 36, 20, 36, 44);
    right -= 36;
    UIButton *bookmark = self.chromeButtons[3];
    bookmark.frame = CGRectMake(right - 36, 20, 36, 44);
    right -= 36;
    self.titleLabel.frame = CGRectMake(46, 20, MAX(40, right - 4 - 46), 44);

    UIButton *toc = self.chromeButtons[1];
    UIButton *previous = self.chromeButtons[5];
    UIButton *next = self.chromeButtons[7];
    toc.frame = CGRectMake(2, 8, 46, 30);
    previous.frame = CGRectMake(48, 8, 50, 30);
    next.frame = CGRectMake(width - 52, 8, 50, 30);
    self.ttsButton.frame = CGRectMake(width - 98, 8, 46, 30);
    self.pageLabel.frame = CGRectMake(98, 8,
        MAX(30, width - 98 - 98), 30);

    CGFloat headerHeight = theme.showHeader ? 20 : 0;
    CGFloat footerHeight = theme.showFooter ? 20 : 0;
    // 正文区域固定（不随工具条显隐变化），全屏切换只淡入淡出覆盖层，无重排卡顿
    CGFloat areaTop = headerHeight + theme.insetTop + 4;
    CGFloat areaBottom = footerHeight + theme.insetBottom + 4;
    CGFloat areaWidth = MAX(40, width - theme.insetLeft - theme.insetRight);
    CGFloat areaHeight = MAX(40, height - areaTop - areaBottom);

    self.textArea = CGRectMake(theme.insetLeft, areaTop, areaWidth, areaHeight);
    self.lastTextAreaSize = self.textArea.size;

    self.headerLabel.hidden = !theme.showHeader;
    self.headerLabel.frame = CGRectMake(theme.insetLeft, areaTop - headerHeight - 1,
                                        areaWidth, 16);
    self.footerLabel.hidden = !theme.showFooter;
    self.footerLabel.frame = CGRectMake(theme.insetLeft,
                                        height - areaBottom + 2,
                                        areaWidth, 16);
    self.bookmarkMark.frame = CGRectMake(width - 34,
                                         areaTop - headerHeight + 2,
                                         28, 28);

    self.spinner.center = CGPointMake(CGRectGetMidX(self.textArea),
                                      CGRectGetMidY(self.textArea));
}

- (void)layoutPanel {
    CGFloat width = self.view.bounds.size.width;
    CGFloat viewHeight = self.view.bounds.size.height;
    CGFloat panelWidth = MAX(280, width - 16);
    CGFloat contentHeight = [self panelContentHeight];
    CGFloat panelHeight = MIN(viewHeight - 20, contentHeight + 52);
    panelHeight = MAX(280, panelHeight);
    self.panel.frame = CGRectMake((width - panelWidth) / 2,
                                  viewHeight - panelHeight - 8,
                                  panelWidth, panelHeight);
    UIView *done = self.panelButtons.firstObject;
    done.frame = CGRectMake(panelWidth - 60, 8, 50, 28);
    self.panelScroll.frame = CGRectMake(0, 42, panelWidth, panelHeight - 42);
    self.panelScroll.contentSize = CGSizeMake(panelWidth,
        MAX(contentHeight, panelHeight - 42));
}

#pragma mark - 主题

- (void)applyChromeTheme {
    YLTheme *theme = [YLTheme shared];
    self.view.backgroundColor = [theme readerBackground];
    self.topBar.backgroundColor = [theme barBackground];
    self.bottomBar.backgroundColor = [theme barBackground];
    [self.topBar viewWithTag:1001].backgroundColor = [theme separatorColor];
    [self.bottomBar viewWithTag:1002].backgroundColor = [theme separatorColor];
    self.titleLabel.textColor = [theme barTextColor];
    self.pageLabel.textColor = [theme readerSecondaryColor];
    self.headerLabel.textColor = [theme readerSecondaryColor];
    self.footerLabel.textColor = [theme readerSecondaryColor];
    for (UIButton *button in self.chromeButtons) {
        button.tintColor = [theme accentColor];
    }
    self.spinner.activityIndicatorViewStyle =
        theme.readerTheme == YLReaderThemeNight
            ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray;

    self.panel.backgroundColor = [theme barBackground];
    self.panel.layer.borderColor = [theme cardBorderColor].CGColor;
    for (UILabel *label in self.panelLabels) {
        if (label.tag == 1003) { continue; }
        label.textColor = [theme secondaryTextColor];
    }
    ((UILabel *)[self.panel viewWithTag:1003]).textColor = [theme barTextColor];
    self.fontSizeValueLabel.textColor = [theme barTextColor];
    self.lineSpacingValueLabel.textColor = [theme barTextColor];
    self.paragraphSpacingValueLabel.textColor = [theme barTextColor];
    self.letterSpacingValueLabel.textColor = [theme barTextColor];
    self.insetLeftValueLabel.textColor = [theme barTextColor];
    self.insetRightValueLabel.textColor = [theme barTextColor];
    self.insetTopValueLabel.textColor = [theme barTextColor];
    self.insetBottomValueLabel.textColor = [theme barTextColor];
    self.chapterTitleSizeValueLabel.textColor = [theme barTextColor];
    [self.fontButton setTitleColor:[theme barTextColor]
                          forState:UIControlStateNormal];
    [self.chapterTitleFontButton setTitleColor:[theme barTextColor]
                                      forState:UIControlStateNormal];
    self.pageModeButton.tintColor = [theme accentColor];
    self.pageAnimButton.tintColor = [theme accentColor];
    [self.pageModeButton setTitleColor:[theme barTextColor] forState:UIControlStateNormal];
    [self.pageAnimButton setTitleColor:[theme barTextColor] forState:UIControlStateNormal];
    self.pageModeButton.backgroundColor = [[theme appBackground] colorWithAlphaComponent:0.6f];
    self.pageAnimButton.backgroundColor = [[theme appBackground] colorWithAlphaComponent:0.6f];
    self.titleSwitch.onTintColor = [theme accentColor];
    self.headerSwitch.onTintColor = [theme accentColor];
    self.footerSwitch.onTintColor = [theme accentColor];
    self.boldSwitch.onTintColor = [theme accentColor];
    self.italicSwitch.onTintColor = [theme accentColor];
    for (UIButton *button in self.panelButtons) {
        button.tintColor = [theme accentColor];
        if (button.tag == 2001) {
            button.backgroundColor = [theme appBackground];
        }
        button.layer.borderColor = [theme separatorColor].CGColor;
    }

    // 顶部图标按当前配色重绘，夜间模式切换后不会残留旧颜色。
    if (self.chromeButtons.count >= 5) {
        [self.chromeButtons[0] setImage:[YLComponents iconNamed:@"back" size:21
                                                          color:theme.accentColor]
                               forState:UIControlStateNormal];
        [self.chromeButtons[3] setImage:[YLComponents iconNamed:@"bookmark" size:21
                                                          color:theme.accentColor]
                               forState:UIControlStateNormal];
        [self.chromeButtons[4] setImage:[YLComponents iconNamed:@"refresh" size:21
                                                          color:theme.accentColor]
                               forState:UIControlStateNormal];
        UIButton *appearanceButton = self.chromeButtons[2];
        appearanceButton.backgroundColor = theme.accentSoftColor;
        appearanceButton.layer.cornerRadius = 10;
        [appearanceButton setTitleColor:theme.accentColor forState:UIControlStateNormal];
    }
    [self refreshPanelValues];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (NSDictionary *)textAttributes {
    YLTheme *theme = [YLTheme shared];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineSpacing = theme.lineSpacing;
    // 段距按较小比例应用，避免中文按行分段时间距过大
    style.paragraphSpacing = MAX(0, theme.paragraphSpacing * 0.5);
    style.paragraphSpacingBefore = 0;
    style.lineBreakMode = NSLineBreakByWordWrapping;
    style.headIndent = 0;
    style.firstLineHeadIndent = 0;
    style.alignment = NSTextAlignmentNatural;
    NSMutableDictionary *attributes = [@{
        NSFontAttributeName: [theme fontOfSize:theme.fontSize
                                         bold:theme.boldText
                                       italic:theme.italicText],
        NSParagraphStyleAttributeName: style,
        NSForegroundColorAttributeName: [theme readerTextColor]
    } mutableCopy];
    if (theme.letterSpacing > 0.01) {
        attributes[NSKernAttributeName] = @(theme.letterSpacing);
    }
    return attributes;
}

// 章节正文在引擎里已经按安卓版“阅读”的规则拆好：不包含标题，
// 开头的空白被替换成两个全角空格。这样 pos 才能和安卓对上。
// 显示时才在正文前拼上章节标题（可关闭），并记住标题占了多长，
// 用于“显示位置 ↔ 同步位置”的换算。
- (void)rebuildChapterText {
    NSString *raw = self.rawChapterText ?: @"";
    YLTheme *theme = [YLTheme shared];
    if (theme.showChapterTitle && self.chapterTitle.length &&
        ![raw hasPrefix:self.chapterTitle]) {
        NSString *header = [NSString stringWithFormat:@"%@\n\n", self.chapterTitle];
        self.chapterHeaderLength = (NSInteger)header.length;
        self.chapterText = [header stringByAppendingString:raw];
    } else {
        self.chapterHeaderLength = 0;
        self.chapterText = raw;
    }
}

- (NSInteger)decoratedPositionForRaw:(NSInteger)raw {
    if (raw <= 0) { return 0; }
    NSInteger rawLength = (NSInteger)self.rawChapterText.length;
    if (rawLength <= 0) { return 0; }
    if (raw >= rawLength) { raw = rawLength - 1; }
    NSInteger decorated = raw + self.chapterHeaderLength;
    NSInteger length = (NSInteger)self.chapterText.length;
    return MIN(decorated, MAX(0, length - 1));
}

- (NSInteger)rawPositionForDecorated:(NSInteger)decorated {
    return MAX(0, decorated - self.chapterHeaderLength);
}

- (NSAttributedString *)attributedChapterText {
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc]
        initWithString:self.chapterText ?: @""
            attributes:[self textAttributes]];
    if (self.chapterHeaderLength > 0 &&
        self.chapterHeaderLength <= (NSInteger)attributed.length) {
        YLTheme *theme = [YLTheme shared];
        [attributed addAttributes:@{
            NSFontAttributeName: [theme chapterTitleFont],
            NSForegroundColorAttributeName: [theme readerTextColor]
        } range:NSMakeRange(0, self.chapterHeaderLength)];
    }
    return attributed;
}

#pragma mark - 内容模式

- (void)ensureContentMode {
    YLTheme *theme = [YLTheme shared];
    if (theme.pagedMode) {
        self.scrollTextView.hidden = YES;
        UIPageViewControllerTransitionStyle style = theme.pageCurl
            ? UIPageViewControllerTransitionStylePageCurl
            : UIPageViewControllerTransitionStyleScroll;
        if (!self.pagedController || self.pagedController.transitionStyle != style) {
            [self buildPagedControllerWithStyle:style];
        }
        self.pagedController.view.hidden = NO;
        self.pagedController.view.frame = self.textArea;
    } else {
        self.pagedController.view.hidden = YES;
        self.scrollTextView.hidden = NO;
        self.scrollTextView.frame = self.textArea;
    }
}

- (void)buildPagedControllerWithStyle:(UIPageViewControllerTransitionStyle)style {
    if (self.pagedController) {
        [self.pagedController willMoveToParentViewController:nil];
        [self.pagedController.view removeFromSuperview];
        [self.pagedController removeFromParentViewController];
        self.pagedController = nil;
    }

    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    // 卷页样式才允许传书脊位置，滚动样式传了会直接抛异常。
    if (style == UIPageViewControllerTransitionStylePageCurl) {
        options[UIPageViewControllerOptionSpineLocationKey] =
            @(UIPageViewControllerSpineLocationMin);
    } else {
        options[UIPageViewControllerOptionInterPageSpacingKey] = @(8);
    }
    self.pagedController = [[UIPageViewController alloc]
        initWithTransitionStyle:style
          navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
                        options:options];
    self.pagedController.dataSource = self;
    self.pagedController.delegate = self;
    self.pagedController.view.backgroundColor = [UIColor clearColor];

    [self addChildViewController:self.pagedController];
    self.pagedController.view.frame = self.textArea;
    [self.view insertSubview:self.pagedController.view atIndex:0];
    [self.pagedController didMoveToParentViewController:self];
}

#pragma mark - 目录与章节

// 打开书先从云端拉一次进度（带签名缓存，通常只有一次 PROPFIND），
// 拉到更新的进度后再取目录，保证打开位置是两边最新的。
- (void)loadChapters {
    __weak ReaderViewController *weakSelf = self;
    [[API shared] post:@"/api/sync/pullBook" body:@{}
            completion:^(id result, NSError *error) {
        ReaderViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        [strongSelf loadChaptersAfterSync];
    }];
}

- (void)loadChaptersAfterSync {
    NSString *source = self.book[@"sourceUrl"] ?: @"";
    NSString *url = self.book[@"bookUrl"] ?: self.book[@"key"] ?: @"";
    __weak ReaderViewController *weakSelf = self;
    [[API shared] get:@"/api/toc" query:@{@"source": source, @"url": url}
           completion:^(id result, NSError *error) {
        ReaderViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        if (error) {
            [strongSelf showMessage:error.localizedDescription];
            return;
        }
        NSDictionary *payload = [result isKindOfClass:[NSDictionary class]] ? result : nil;
        NSDictionary *book = payload[@"book"];
        if ([book isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *merged = [strongSelf.book mutableCopy];
            [merged addEntriesFromDictionary:book];
            strongSelf.book = merged;
        }
        strongSelf.chapters = [payload[@"chapters"] isKindOfClass:[NSArray class]]
            ? payload[@"chapters"] : @[];

        NSDictionary *progress = strongSelf.book[@"progress"];
        if (![progress isKindOfClass:[NSDictionary class]]) { progress = nil; }
        id indexValue = progress[@"chapterIndex"];
        id posValue = progress[@"pos"];
        id ratioValue = progress[@"ratio"];
        NSInteger index = [indexValue respondsToSelector:@selector(integerValue)]
            ? [indexValue integerValue] : 0;
        if (index < 0 || index >= (NSInteger)strongSelf.chapters.count) { index = 0; }
        NSInteger position = [posValue respondsToSelector:@selector(integerValue)]
            ? [posValue integerValue] : 0;
        strongSelf.pendingRatio = [ratioValue respondsToSelector:@selector(doubleValue)]
            ? [ratioValue doubleValue] : 0;
        // 老版本只存了比例：先标记为 -1，等正文长度确定后再换算成字符位置
        if (position <= 0 && strongSelf.pendingRatio > 0) { position = -1; }
        [strongSelf loadChapterAtIndex:index position:position direction:YES animated:NO];
    }];
}

- (void)loadChapterAtIndex:(NSInteger)index
                  position:(NSInteger)position
                 direction:(BOOL)forward
                  animated:(BOOL)animated {
    if (index < 0 || index >= (NSInteger)self.chapters.count) {
        [self showMessage:index < 0 ? @"已经是第一章" : @"已经是最后一章"];
        return;
    }
    [self saveProgress];
    [self stopSpeech];

    self.chapterIndex = index;
    self.pendingPosition = position;
    if (position >= 0) { self.pendingRatio = 0; }
    NSDictionary *chapter = self.chapters[index];
    self.chapterTitle = [chapter[@"title"] isKindOfClass:[NSString class]]
        ? chapter[@"title"] : @"";
    [self updateChrome];
    [self.spinner startAnimating];

    self.loadSequence += 1;
    NSInteger token = self.loadSequence;

    NSString *source = self.book[@"sourceUrl"] ?: @"";
    NSString *url = chapter[@"url"] ?: self.book[@"bookUrl"] ?: @"";
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[@"source"] = source;
    query[@"url"] = url;
    if ([source isEqualToString:@"local"]) {
        query[@"key"] = self.book[@"bookUrl"] ?: url;
        query[@"index"] = [NSString stringWithFormat:@"%ld", (long)index];
    }

    __weak ReaderViewController *weakSelf = self;
    [[API shared] get:@"/api/content" query:query completion:^(id result, NSError *error) {
        ReaderViewController *strongSelf = weakSelf;
        if (!strongSelf || token != strongSelf.loadSequence) { return; }
        [strongSelf.spinner stopAnimating];
        if (error) {
            [strongSelf showMessage:error.localizedDescription];
            return;
        }
        NSDictionary *payload = [result isKindOfClass:[NSDictionary class]] ? result : nil;
        NSString *text = [payload[@"text"] isKindOfClass:[NSString class]] ? payload[@"text"] : @"";
        NSString *title = [payload[@"title"] isKindOfClass:[NSString class]]
            ? payload[@"title"] : strongSelf.chapterTitle;
        if (title.length) { strongSelf.chapterTitle = title; }
        if (!text.length) { text = @"（本章暂无内容）"; }
        // 原样保存正文，不再插入缩进/标题，保证 pos 和安卓一致。
        strongSelf.rawChapterText = text;
        [strongSelf rebuildChapterText];
        NSInteger target = strongSelf.pendingPosition;
        if (target < 0) {
            target = (NSInteger)(strongSelf.pendingRatio * (double)text.length);
            strongSelf.pendingRatio = 0;
        }
        [strongSelf renderChapterAtPosition:[strongSelf decoratedPositionForRaw:target]
                                  direction:forward
                                   animated:animated];
        [strongSelf updateChrome];
        [strongSelf scheduleSave];
    }];
}

- (void)renderChapterAtPosition:(NSInteger)position
                      direction:(BOOL)forward
                       animated:(BOOL)animated {
    NSInteger length = self.chapterText.length;
    if (length <= 0) {
        [self updateChrome];
        return;
    }
    NSInteger target = position;
    if (target < 0) { target = 0; }
    if (target >= length) { target = MAX(0, length - 1); }

    [self ensureContentMode];
    if ([YLTheme shared].pagedMode) {
        [self repaginate];
        UIPageViewControllerNavigationDirection direction = forward
            ? UIPageViewControllerNavigationDirectionForward
            : UIPageViewControllerNavigationDirectionReverse;
        [self showPage:[self pageForPosition:target]
             direction:direction
              animated:animated];
    } else {
        [self applyScrollTextWithPosition:target];
    }
    [self updateChrome];
}

- (void)previousChapter {
    NSInteger index = self.chapterIndex - 1;
    if (index < 0) {
        [self showMessage:@"已经是第一章"];
        return;
    }
    [self loadChapterAtIndex:index position:NSIntegerMax direction:NO animated:YES];
}

- (void)nextChapter {
    NSInteger index = self.chapterIndex + 1;
    if (index >= (NSInteger)self.chapters.count) {
        [self showMessage:@"已经是最后一章"];
        return;
    }
    [self loadChapterAtIndex:index position:0 direction:YES animated:YES];
}

#pragma mark - 分页

- (void)repaginate {
    [self.pageRanges removeAllObjects];
    self.rebuilding = YES;

    CGSize size = self.textArea.size;
    NSString *text = self.chapterText ?: @"";
    if (size.width < 40 || size.height < 40 || text.length == 0) {
        [self.pageRanges addObject:[NSValue valueWithRange:NSMakeRange(0, text.length)]];
        self.rebuilding = NO;
        return;
    }

    // 必须用和实际渲染完全一致的富文本（含章节标题的加粗大字号）分页，
    // 否则标题占位不同，翻页末尾会少一行/丢字。
    NSTextStorage *storage = [[NSTextStorage alloc]
        initWithAttributedString:[self attributedChapterText]];
    NSLayoutManager *layout = [[NSLayoutManager alloc] init];
    [storage addLayoutManager:layout];

    // iOS 9 的 UITextView 在 UIPageViewController 里渲染时，末尾约两行会被裁掉。
    // 分页时主动预留两行高度，保证整页内容都能完整显示（不再丢字）。
    YLTheme *pagingTheme = [YLTheme shared];
    UIFont *pagingFont = [pagingTheme fontOfSize:pagingTheme.fontSize
                                            bold:pagingTheme.boldText
                                          italic:pagingTheme.italicText];
    CGFloat twoLines = (pagingFont.lineHeight + pagingTheme.lineSpacing) * 2.0 + 6.0;
    CGFloat pageHeight = MAX(20.0, size.height - twoLines);

    while (YES) {
        NSTextContainer *container = [[NSTextContainer alloc]
            initWithSize:CGSizeMake(size.width, pageHeight)];
        container.lineFragmentPadding = 0;
        [layout addTextContainer:container];
        NSRange glyphRange = [layout glyphRangeForTextContainer:container];
        if (glyphRange.length == 0) { break; }
        NSRange charRange = [layout characterRangeForGlyphRange:glyphRange
                                               actualGlyphRange:NULL];
        if (charRange.length == 0) { break; }
        [self.pageRanges addObject:[NSValue valueWithRange:charRange]];
        if (NSMaxRange(glyphRange) >= layout.numberOfGlyphs) { break; }
    }

    // 兜底：确保未因排版异常丢失尾部文字
    if (self.pageRanges.count) {
        NSRange last = [[self.pageRanges lastObject] rangeValue];
        NSUInteger end = NSMaxRange(last);
        if (end < text.length) {
            [self.pageRanges addObject:[NSValue valueWithRange:NSMakeRange(end, text.length - end)]];
        }
    }
    if (!self.pageRanges.count) {
        [self.pageRanges addObject:[NSValue valueWithRange:NSMakeRange(0, text.length)]];
    }
    if (self.pageIndex >= (NSInteger)self.pageRanges.count) {
        self.pageIndex = (NSInteger)self.pageRanges.count - 1;
    }
    if (self.pageIndex < 0) { self.pageIndex = 0; }
    self.rebuilding = NO;
}

- (NSInteger)pageForPosition:(NSInteger)position {
    if (!self.pageRanges.count) { return 0; }
    if (position <= 0) { return 0; }
    for (NSInteger i = 0; i < (NSInteger)self.pageRanges.count; i += 1) {
        NSRange range = [self.pageRanges[i] rangeValue];
        if (position < (NSInteger)NSMaxRange(range)) { return i; }
    }
    return (NSInteger)self.pageRanges.count - 1;
}

- (YLPageViewController *)pageControllerForPage:(NSInteger)page {
    if (page < 0 || page >= (NSInteger)self.pageRanges.count) { return nil; }
    NSRange range = [self.pageRanges[page] rangeValue];
    NSString *text = self.chapterText ?: @"";
    if (NSMaxRange(range) > text.length) { return nil; }

    NSString *pageString = [text substringWithRange:range];
    NSUInteger trimmed = 0;
    while (trimmed < pageString.length &&
           ([pageString characterAtIndex:trimmed] == '\n' ||
            [pageString characterAtIndex:trimmed] == '\r')) {
        trimmed += 1;
    }
    NSInteger pageStart = (NSInteger)range.location + (NSInteger)trimmed;
    if (trimmed) {
        pageString = [pageString substringFromIndex:trimmed];
    }

    YLPageViewController *controller = [[YLPageViewController alloc] init];
    controller.pageNumber = page;

    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc]
        initWithString:pageString attributes:[self textAttributes]];
    if (self.chapterHeaderLength > 0 && pageStart < self.chapterHeaderLength) {
        NSRange overlap = NSIntersectionRange(
            NSMakeRange(0, self.chapterHeaderLength),
            NSMakeRange(pageStart, pageString.length));
        if (overlap.length > 0) {
            YLTheme *theme = [YLTheme shared];
            [attributed addAttributes:@{
                NSFontAttributeName: [theme fontOfSize:theme.fontSize + 2
                                                 bold:YES
                                               italic:theme.italicText]
            } range:NSMakeRange(overlap.location - pageStart, overlap.length)];
        }
    }
    controller.pageText = attributed;
    return controller;
}

- (void)showPage:(NSInteger)page
       direction:(UIPageViewControllerNavigationDirection)direction
        animated:(BOOL)animated {
    if (!self.pagedController || !self.pageRanges.count) { return; }
    if (page < 0) { page = 0; }
    if (page >= (NSInteger)self.pageRanges.count) {
        page = (NSInteger)self.pageRanges.count - 1;
    }
    YLPageViewController *controller = [self pageControllerForPage:page];
    if (!controller) { return; }
    self.pageIndex = page;
    __weak ReaderViewController *weakSelf = self;
    [self.pagedController setViewControllers:@[controller]
                                   direction:direction
                                    animated:animated
                                  completion:^(BOOL finished) {
        [weakSelf updateChrome];
    }];
    [self updateChrome];
}

- (void)showPage:(NSInteger)page animated:(BOOL)animated {
    UIPageViewControllerNavigationDirection direction =
        page >= self.pageIndex ? UIPageViewControllerNavigationDirectionForward
                               : UIPageViewControllerNavigationDirectionReverse;
    [self showPage:page direction:direction animated:animated];
}

#pragma mark - 滚动模式

- (void)applyScrollTextWithPosition:(NSInteger)position {
    NSAttributedString *attributed = [self attributedChapterText];
    self.scrollTextView.attributedText = attributed;
    [self.scrollTextView setContentOffset:CGPointZero animated:NO];
    [self.scrollTextView layoutIfNeeded];

    NSInteger length = self.chapterText.length;
    if (position <= 0 || length == 0) { return; }
    if (position >= length) {
        CGFloat maxOffset = MAX(0, self.scrollTextView.contentSize.height -
                                   self.scrollTextView.bounds.size.height);
        [self.scrollTextView setContentOffset:CGPointMake(0, maxOffset) animated:NO];
        return;
    }
    UITextPosition *textPosition = [self.scrollTextView
        positionFromPosition:self.scrollTextView.beginningOfDocument offset:position];
    if (!textPosition) { return; }
    CGRect caret = [self.scrollTextView caretRectForPosition:textPosition];
    if (CGRectIsNull(caret) || CGRectIsInfinite(caret)) { return; }
    CGFloat offset = MAX(0, caret.origin.y - 4);
    [self.scrollTextView setContentOffset:CGPointMake(0, offset) animated:NO];
}

- (NSInteger)currentPosition {
    if ([YLTheme shared].pagedMode && self.pageRanges.count) {
        NSInteger page = MIN(MAX(0, self.pageIndex), (NSInteger)self.pageRanges.count - 1);
        NSRange range = [self.pageRanges[page] rangeValue];
        return (NSInteger)range.location;
    }
    if (self.scrollTextView && self.chapterText.length) {
        CGPoint point = CGPointMake(2, self.scrollTextView.contentOffset.y + 2);
        UITextPosition *position = [self.scrollTextView closestPositionToPoint:point];
        if (position) {
            NSInteger offset = [self.scrollTextView
                offsetFromPosition:self.scrollTextView.beginningOfDocument
                        toPosition:position];
            if (offset >= 0 && offset <= (NSInteger)self.chapterText.length) {
                return offset;
            }
        }
        CGFloat maxOffset = MAX(1, self.scrollTextView.contentSize.height -
                                   self.scrollTextView.bounds.size.height);
        CGFloat ratio = MIN(1.0, MAX(0.0, self.scrollTextView.contentOffset.y / maxOffset));
        return (NSInteger)(ratio * self.chapterText.length);
    }
    return self.pendingPosition;
}

#pragma mark - 翻页 / 点击

- (void)turnNext {
    if (self.chapterText.length == 0) { return; }
    if ([YLTheme shared].pagedMode) {
        if (self.pageIndex + 1 < (NSInteger)self.pageRanges.count) {
            [self showPage:self.pageIndex + 1 animated:YES];
            [self scheduleSave];
        } else {
            [self nextChapter];
        }
        return;
    }
    CGFloat maxOffset = MAX(0, self.scrollTextView.contentSize.height -
                               self.scrollTextView.bounds.size.height);
    if (self.scrollTextView.contentOffset.y < maxOffset - 2) {
        CGFloat target = MIN(maxOffset, self.scrollTextView.contentOffset.y +
            self.scrollTextView.bounds.size.height * 0.92);
        [self.scrollTextView setContentOffset:CGPointMake(0, target) animated:YES];
    } else {
        [self nextChapter];
    }
}

- (void)turnPrevious {
    if (self.chapterText.length == 0) { return; }
    if ([YLTheme shared].pagedMode) {
        if (self.pageIndex > 0) {
            [self showPage:self.pageIndex - 1 animated:YES];
            [self scheduleSave];
        } else {
            [self previousChapter];
        }
        return;
    }
    if (self.scrollTextView.contentOffset.y > 2) {
        CGFloat target = MAX(0, self.scrollTextView.contentOffset.y -
            self.scrollTextView.bounds.size.height * 0.92);
        [self.scrollTextView setContentOffset:CGPointMake(0, target) animated:YES];
    } else {
        [self previousChapter];
    }
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if (!self.panel.hidden) { return; }
    if (self.barsHidden) {
        [self setBarsHidden:NO];
        return;
    }
    CGPoint point = [gesture locationInView:self.view];
    CGFloat width = self.view.bounds.size.width;
    if (point.x < width * 0.28) {
        [self turnPrevious];
    } else if (point.x > width * 0.72) {
        [self turnNext];
    } else {
        [self setBarsHidden:YES];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    UIView *view = touch.view;
    if (view && ([view isDescendantOfView:self.topBar] ||
                 [view isDescendantOfView:self.bottomBar] ||
                 [view isDescendantOfView:self.panel] ||
                 view == self.dimView)) {
        return NO;
    }
    return YES;
}

- (void)setBarsHidden:(BOOL)hidden {
    if (_barsHidden == hidden) { return; }
    _barsHidden = hidden;
    // 工具条为覆盖层，正文区域固定：仅淡入淡出，无重排/重分页，4S 不卡顿
    [UIView animateWithDuration:0.2
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.topBar.alpha = hidden ? 0 : 1;
        self.bottomBar.alpha = hidden ? 0 : 1;
    } completion:nil];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)relayoutForChromeChangeWithRaw:(NSNumber *)rawValue {
    self.chromeChangePending = NO;
    NSInteger raw = [rawValue longLongValue];
    [self updateLayoutMetrics];
    [UIView performWithoutAnimation:^{
        self.pagedController.view.frame = self.textArea;
        self.scrollTextView.frame = self.textArea;
    }];
    if (!self.rawChapterText.length || self.rebuilding) {
        [self updateChrome];
        return;
    }
    NSInteger decorated = [self decoratedPositionForRaw:raw];
    __weak ReaderViewController *weakSelf = self;
    void (^apply)(void) = ^{
        ReaderViewController *s = weakSelf; if (!s) { return; }
        if ([YLTheme shared].pagedMode) {
            [s repaginate];
            [s showPage:[s pageForPosition:decorated]
                 direction:UIPageViewControllerNavigationDirectionForward
                  animated:NO];
        } else {
            [s applyScrollTextWithPosition:decorated];
        }
        [s updateChrome];
    };
    // 让出一帧，减少退出全屏时工具条弹出+重排叠加造成的卡顿
    dispatch_async(dispatch_get_main_queue(), apply);
}

- (BOOL)prefersStatusBarHidden {
    return self.barsHidden;
}

- (BOOL)shouldAutorotate {
    return [YLTheme shared].readerOrientation == 0;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    switch ([YLTheme shared].readerOrientation) {
        case 1: return UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
        case 2: return UIInterfaceOrientationMaskLandscape;
        default: return UIInterfaceOrientationMaskAllButUpsideDown;
    }
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if ([YLTheme shared].readerOrientation == 2) {
        return UIInterfaceOrientationLandscapeRight;
    }
    return UIInterfaceOrientationPortrait;
}

#pragma mark - 顶部按钮

- (void)goBack {
    [self stopSpeech];
    [self saveProgress];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)openToc {
    [self saveProgress];
    TocViewController *toc = [[TocViewController alloc] initWithBook:self.book
                                                            chapters:self.chapters];
    toc.selectedIndex = self.chapterIndex;
    __weak ReaderViewController *weakSelf = self;
    toc.selectBlock = ^(NSInteger index, NSArray *chapters, NSDictionary *book) {
        ReaderViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        if ([chapters isKindOfClass:[NSArray class]] && chapters.count) {
            strongSelf.chapters = chapters;
        }
        if ([book isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *merged = [strongSelf.book mutableCopy];
            [merged addEntriesFromDictionary:book];
            strongSelf.book = merged;
        }
        [strongSelf.navigationController popToViewController:strongSelf animated:YES];
        [strongSelf loadChapterAtIndex:index position:0 direction:YES animated:NO];
    };
    [self.navigationController pushViewController:toc animated:YES];
}

#pragma mark - 书签

- (NSString *)bookKey {
    NSString *key = self.book[@"key"];
    return [key isKindOfClass:[NSString class]] ? key : @"";
}

- (void)bookmarkTapped {
    NSString *key = [self bookKey];
    if (!key.length) { return; }
    __weak ReaderViewController *weakSelf = self;
    [[API shared] post:@"/api/bookmark/list" body:@{@"key": key}
            completion:^(id result, NSError *error) {
        ReaderViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        NSDictionary *payload = [result isKindOfClass:[NSDictionary class]] ? result : @{};
        NSArray *bookmarks = [payload[@"bookmarks"] isKindOfClass:[NSArray class]]
            ? payload[@"bookmarks"] : @[];
        [strongSelf showBookmarkSheet:bookmarks];
    }];
}

- (void)showBookmarkSheet:(NSArray *)bookmarks {
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"书签（%lu）",
            (unsigned long)bookmarks.count]
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    __weak ReaderViewController *weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"添加书签"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        ReaderViewController *strongSelf = weakSelf;
        if (strongSelf) { [strongSelf addBookmark]; }
    }]];

    // 最新的书签排在最上面，最多列 8 条
    NSInteger count = (NSInteger)bookmarks.count;
    NSInteger shown = MIN(count, 8);
    for (NSInteger i = 0; i < shown; i += 1) {
        NSDictionary *bookmark = bookmarks[count - 1 - i];
        NSString *title = [bookmark[@"title"] isKindOfClass:[NSString class]]
            ? bookmark[@"title"] : @"";
        if (!title.length) { title = @"书签"; }
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:
            [bookmark[@"time"] doubleValue] / 1000.0];
        NSString *timeText = [NSDateFormatter
            localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle
                                 timeStyle:NSDateFormatterShortStyle];
        [sheet addAction:[UIAlertAction
            actionWithTitle:[NSString stringWithFormat:@"%@  ·  %@",
                title, timeText]
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
            ReaderViewController *strongSelf = weakSelf;
            if (!strongSelf) { return; }
            NSInteger index = [bookmark[@"index"] integerValue];
            NSInteger rawPos = [bookmark[@"pos"] integerValue];
            // 取消全屏切换的延迟重排，避免它用跳转前位置覆盖书签跳转
            [NSObject cancelPreviousPerformRequestsWithTarget:strongSelf
                selector:@selector(relayoutForChromeChangeWithRaw:) object:nil];
            strongSelf.chromeChangePending = NO;
            [strongSelf setBarsHidden:YES];
            [strongSelf loadChapterAtIndex:index
                                  position:rawPos
                                 direction:YES
                                  animated:NO];
        }]];
    }

    if (bookmarks.count) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"清空本书书签"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            ReaderViewController *strongSelf = weakSelf;
            if (!strongSelf) { return; }
            [[API shared] post:@"/api/bookmark/clear"
                          body:@{@"key": [strongSelf bookKey]}
                    completion:nil];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)addBookmark {
    NSString *key = [self bookKey];
    if (!key.length || !self.chapters.count) { return; }
    NSInteger rawPos = [self rawPositionForDecorated:[self currentPosition]];
    NSString *snippet = @"";
    NSString *raw = self.rawChapterText ?: @"";
    if (raw.length) {
        NSInteger start = MAX(0, MIN(rawPos, (NSInteger)raw.length - 1));
        NSInteger end = MIN((NSInteger)raw.length, start + 24);
        if (end > start) {
            snippet = [[raw substringWithRange:NSMakeRange(start, end - start)]
                stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
    NSDictionary *body = @{
        @"key": key,
        @"index": @(self.chapterIndex),
        @"pos": @(MAX(0, rawPos)),
        @"title": self.chapterTitle ?: @"",
        @"snippet": snippet,
        @"time": @((long long)([[NSDate date] timeIntervalSince1970] * 1000))
    };
    __weak ReaderViewController *weakSelf = self;
    [[API shared] post:@"/api/bookmark/add" body:body
            completion:^(id result, NSError *error) {
        ReaderViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        [strongSelf showMessage:error ? error.localizedDescription : @"已添加书签"];
        [strongSelf refreshBookmarks];
    }];
}

// 当前页（±30 字）有书签时，在文字区右上角显示书签图标
- (void)refreshBookmarks {
    NSString *key = [self bookKey];
    if (!key.length) { return; }
    __weak ReaderViewController *weakSelf = self;
    [[API shared] post:@"/api/bookmark/list" body:@{@"key": key}
            completion:^(id result, NSError *error) {
        ReaderViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        NSDictionary *payload = [result isKindOfClass:[NSDictionary class]] ? result : @{};
        NSArray *list = [payload[@"bookmarks"] isKindOfClass:[NSArray class]]
            ? payload[@"bookmarks"] : @[];
        strongSelf.bookmarks = list;
        [strongSelf updateBookmarkMark];
    }];
}

- (void)updateBookmarkMark {
    BOOL marked = NO;
    if (self.bookmarks.count && self.chapters.count) {
        NSInteger raw = [self rawPositionForDecorated:[self currentPosition]];
        for (NSDictionary *bookmark in self.bookmarks) {
            if ([bookmark[@"index"] integerValue] != self.chapterIndex) { continue; }
            if (labs((long)[bookmark[@"pos"] integerValue] - (long)raw) < 30) {
                marked = YES;
                break;
            }
        }
    }
    self.bookmarkMark.hidden = !marked;
}

#pragma mark - 手动同步

- (void)syncTapped {
    [self saveProgress];
    NSString *key = [self bookKey];
    __weak ReaderViewController *weakSelf = self;
    // 先拉（云端更靠前就采纳），再立刻把当前书推上去
    [[API shared] post:@"/api/sync/pullBook" body:@{}
            completion:^(id result, NSError *error) {
        [[API shared] post:@"/api/sync/pushBook"
                      body:key.length ? @{@"key": key} : @{}
                completion:^(id result2, NSError *error2) {
            ReaderViewController *strongSelf = weakSelf;
            if (!strongSelf) { return; }
            if (error2) {
                [strongSelf showMessage:error2.localizedDescription];
            } else {
                [strongSelf showMessage:@"同步完成"];
            }
        }];
    }];
}

#pragma mark - 排版面板

- (void)togglePanel {
    if (self.panel.hidden) {
        [self showPanel];
    } else {
        [self hidePanel];
    }
}

- (void)showPanel {
    [self refreshPanelValues];
    [self layoutPanel];
    self.panel.hidden = NO;
    self.dimView.hidden = NO;
    self.dimView.alpha = 0;
    [self.view bringSubviewToFront:self.dimView];
    [self.view bringSubviewToFront:self.panel];

    CGFloat height = self.panel.bounds.size.height;
    CGRect target = self.panel.frame;
    self.panel.frame = CGRectMake(target.origin.x,
                                  self.view.bounds.size.height,
                                  target.size.width, height);
    [UIView animateWithDuration:0.22 animations:^{
        self.panel.frame = target;
        self.dimView.alpha = 1;
    }];
}

- (void)hidePanel {
    if (self.panel.hidden) { return; }
    CGRect target = self.panel.frame;
    CGFloat height = target.size.height;
    [UIView animateWithDuration:0.2 animations:^{
        self.panel.frame = CGRectMake(target.origin.x,
                                      self.view.bounds.size.height,
                                      target.size.width, height);
        self.dimView.alpha = 0;
    } completion:^(BOOL finished) {
        self.panel.hidden = YES;
        self.dimView.hidden = YES;
    }];
}

- (void)refreshPanelValues {
    YLTheme *theme = [YLTheme shared];
    self.fontSizeValueLabel.text = [NSString stringWithFormat:@"%ld", (long)theme.fontSize];
    self.lineSpacingValueLabel.text = [NSString stringWithFormat:@"%ld",
        (long)lround(theme.lineSpacing)];
    self.paragraphSpacingValueLabel.text = [NSString stringWithFormat:@"%ld",
        (long)lround(theme.paragraphSpacing)];
    self.letterSpacingValueLabel.text = [NSString stringWithFormat:@"%.1f",
        theme.letterSpacing];
    self.insetLeftValueLabel.text = [NSString stringWithFormat:@"%ld",
        (long)lround(theme.insetLeft)];
    self.insetRightValueLabel.text = [NSString stringWithFormat:@"%ld",
        (long)lround(theme.insetRight)];
    self.insetTopValueLabel.text = [NSString stringWithFormat:@"%ld",
        (long)lround(theme.insetTop)];
    self.insetBottomValueLabel.text = [NSString stringWithFormat:@"%ld",
        (long)lround(theme.insetBottom)];
    [self.fontButton setTitle:[NSString stringWithFormat:@"%@  ▾",
        [theme displayNameForFamily:theme.fontFamily]]
                     forState:UIControlStateNormal];
    [self.pageModeButton setTitle:theme.pagedMode ? @"左右翻页  ▸" : @"上下滚动  ▸"
                          forState:UIControlStateNormal];
    [self.pageAnimButton setTitle:(theme.pageCurl ? @"仿真翻页  ▸" : @"平移动画  ▸")
                          forState:UIControlStateNormal];
    self.pageAnimButton.enabled = theme.pagedMode;
    self.pageAnimButton.alpha = theme.pagedMode ? 1.0 : 0.45;
    self.titleSwitch.on = theme.showChapterTitle;
    self.headerSwitch.on = theme.showHeader;
    self.footerSwitch.on = theme.showFooter;
    self.boldSwitch.on = theme.boldText;
    self.italicSwitch.on = theme.italicText;
    self.chapterTitleSizeValueLabel.text = theme.chapterTitleFontSize > 0
        ? [NSString stringWithFormat:@"%ld", (long)lround(theme.chapterTitleFontSize)]
        : @"跟随";
    NSString *titleFamily = theme.chapterTitleFontFamily.length
        ? [theme displayNameForFamily:theme.chapterTitleFontFamily] : @"跟随正文";
    [self.chapterTitleFontButton setTitle:[NSString stringWithFormat:@"%@  ▾", titleFamily]
                                 forState:UIControlStateNormal];
    [self.chapterTitleWeightButton setTitle:[NSString stringWithFormat:@"字重 %@  ▸",
        [theme chapterTitleWeightName]]
                                   forState:UIControlStateNormal];
    for (UIButton *swatch in self.themeSwatches) {
        BOOL selected = (swatch.tag == theme.readerTheme);
        swatch.layer.borderWidth = selected ? 2.5 : 1;
        swatch.layer.borderColor = selected
            ? [theme accentColor].CGColor : [theme separatorColor].CGColor;
    }
}

- (void)decreaseFontSize {
    YLTheme *theme = [YLTheme shared];
    theme.fontSize = MAX(13, theme.fontSize - 1);
    [self applySettingsChange];
}

- (void)increaseFontSize {
    YLTheme *theme = [YLTheme shared];
    theme.fontSize = MIN(30, theme.fontSize + 1);
    [self applySettingsChange];
}

- (void)decreaseLineSpacing {
    YLTheme *theme = [YLTheme shared];
    theme.lineSpacing = MAX(2, theme.lineSpacing - 1);
    [self applySettingsChange];
}

- (void)increaseLineSpacing {
    YLTheme *theme = [YLTheme shared];
    theme.lineSpacing = MIN(16, theme.lineSpacing + 1);
    [self applySettingsChange];
}

- (void)decreaseParagraphSpacing {
    YLTheme *theme = [YLTheme shared];
    theme.paragraphSpacing = MAX(0, theme.paragraphSpacing - 1);
    [self applySettingsChange];
}

- (void)increaseParagraphSpacing {
    YLTheme *theme = [YLTheme shared];
    theme.paragraphSpacing = MIN(20, theme.paragraphSpacing + 1);
    [self applySettingsChange];
}

- (void)decreaseLetterSpacing {
    YLTheme *theme = [YLTheme shared];
    theme.letterSpacing = MAX(0, theme.letterSpacing - 0.5);
    [self applySettingsChange];
}

- (void)increaseLetterSpacing {
    YLTheme *theme = [YLTheme shared];
    theme.letterSpacing = MIN(6, theme.letterSpacing + 0.5);
    [self applySettingsChange];
}

- (void)decreaseInsetLeft {
    [YLTheme shared].insetLeft = MAX(0, [YLTheme shared].insetLeft - 4);
    [self applySettingsChange];
}

- (void)increaseInsetLeft {
    [YLTheme shared].insetLeft = MIN(48, [YLTheme shared].insetLeft + 4);
    [self applySettingsChange];
}

- (void)decreaseInsetRight {
    [YLTheme shared].insetRight = MAX(0, [YLTheme shared].insetRight - 4);
    [self applySettingsChange];
}

- (void)increaseInsetRight {
    [YLTheme shared].insetRight = MIN(48, [YLTheme shared].insetRight + 4);
    [self applySettingsChange];
}

- (void)decreaseInsetTop {
    [YLTheme shared].insetTop = MAX(0, [YLTheme shared].insetTop - 4);
    [self applySettingsChange];
}

- (void)increaseInsetTop {
    [YLTheme shared].insetTop = MIN(48, [YLTheme shared].insetTop + 4);
    [self applySettingsChange];
}

- (void)decreaseInsetBottom {
    [YLTheme shared].insetBottom = MAX(0, [YLTheme shared].insetBottom - 4);
    [self applySettingsChange];
}

- (void)increaseInsetBottom {
    [YLTheme shared].insetBottom = MIN(48, [YLTheme shared].insetBottom + 4);
    [self applySettingsChange];
}

#pragma mark - 章节标题样式

- (void)decreaseChapterTitleSize {
    YLTheme *theme = [YLTheme shared];
    CGFloat size = theme.chapterTitleFontSize;
    if (size <= 0) { return; } // 已经是“跟随正文”
    theme.chapterTitleFontSize = (size <= 12.5) ? 0 : MAX(12, size - 1);
    [self applySettingsChange];
}

- (void)increaseChapterTitleSize {
    YLTheme *theme = [YLTheme shared];
    CGFloat size = theme.chapterTitleFontSize;
    if (size <= 0) {
        theme.chapterTitleFontSize = MIN(34, (CGFloat)theme.fontSize + 2);
    } else {
        theme.chapterTitleFontSize = MIN(34, size + 1);
    }
    [self applySettingsChange];
}

- (void)toggleChapterTitleWeight {
    YLTheme *theme = [YLTheme shared];
    theme.chapterTitleWeight = (theme.chapterTitleWeight + 1) % 3;
    [self applySettingsChange];
}

- (void)chooseChapterTitleFont {
    YLTheme *theme = [YLTheme shared];
    NSArray *keys = [theme familyKeys];
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:@"章节标题字体"
                         message:@"“跟随正文”会使用正文字体"
                  preferredStyle:UIAlertControllerStyleActionSheet];
    NSMutableArray *titles = [NSMutableArray arrayWithObject:@"跟随正文"];
    for (NSString *key in keys) {
        [titles addObject:[theme displayNameForFamily:key]];
    }
    __weak ReaderViewController *weakSelf = self;
    // 第 0 项是跟随正文，之后与 keys 一一对应
    for (NSInteger i = 0; i < (NSInteger)titles.count; i += 1) {
        NSString *family = (i == 0) ? @"" : keys[i - 1];
        NSString *title = titles[i];
        if ([family isEqualToString:theme.chapterTitleFontFamily ?: @""]) {
            title = [title stringByAppendingString:@"  ✓"];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            ReaderViewController *strongSelf = weakSelf;
            if (!strongSelf) { return; }
            [YLTheme shared].chapterTitleFontFamily = family;
            [strongSelf applySettingsChange];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.chapterTitleFontButton;
        sheet.popoverPresentationController.sourceRect = self.chapterTitleFontButton.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)displaySwitchChanged:(UISwitch *)sender {
    YLTheme *theme = [YLTheme shared];
    if (sender == self.titleSwitch) {
        theme.showChapterTitle = sender.isOn;
    } else if (sender == self.headerSwitch) {
        theme.showHeader = sender.isOn;
    } else if (sender == self.footerSwitch) {
        theme.showFooter = sender.isOn;
    }
    [self applySettingsChange];
}

- (void)textStyleChanged:(UISwitch *)sender {
    YLTheme *theme = [YLTheme shared];
    theme.boldText = self.boldSwitch.isOn;
    theme.italicText = self.italicSwitch.isOn;
    [self applySettingsChange];
}

- (void)themeSwatchTapped:(UIButton *)button {
    [YLTheme shared].readerTheme = (YLReaderTheme)button.tag;
    [self applySettingsChange];
}

- (void)segmentChanged:(UISegmentedControl *)segment {
    YLTheme *theme = [YLTheme shared];
    if (segment == self.modeSegment) {
        theme.pagedMode = segment.selectedSegmentIndex == 1;
    } else if (segment == self.animSegment) {
        theme.pageCurl = segment.selectedSegmentIndex == 1;
    }
    [self applySettingsChange];
}

- (void)togglePageMode {
    YLTheme *theme = [YLTheme shared];
    theme.pagedMode = !theme.pagedMode;
    [self applySettingsChange];
}

- (void)togglePageAnim {
    YLTheme *theme = [YLTheme shared];
    if (!theme.pagedMode) { return; }
    theme.pageCurl = !theme.pageCurl;
    [self applySettingsChange];
}

- (void)chooseFont {
    YLTheme *theme = [YLTheme shared];
    NSArray *keys = [theme familyKeys];
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:@"选择字体"
                         message:@"自定义字体请到“设置 - 字体与存储”导入 TTF/OTF"
                  preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *key in keys) {
        NSString *title = [theme displayNameForFamily:key];
        if ([key isEqualToString:theme.fontFamily]) {
            title = [title stringByAppendingString:@"  ✓"];
        }
        __weak ReaderViewController *weakSelf = self;
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            ReaderViewController *strongSelf = weakSelf;
            if (!strongSelf) { return; }
            [YLTheme shared].fontFamily = key;
            [strongSelf applySettingsChange];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.fontButton;
        sheet.popoverPresentationController.sourceRect = self.fontButton.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)applySettingsChange {
    NSInteger raw = [self rawPositionForDecorated:[self currentPosition]];
    YLTheme *theme = [YLTheme shared];
    [theme save];
    [self applyChromeTheme];
    [self updateLayoutMetrics];
    [self ensureContentMode];
    if (self.rawChapterText.length) {
        [self rebuildChapterText];
        self.pendingPosition = raw;
        [self renderChapterAtPosition:[self decoratedPositionForRaw:raw]
                            direction:YES
                             animated:NO];
    }
    [self refreshPanelValues];
}

#pragma mark - 朗读

- (void)ttsTapped {
    if (self.speechPaused) {
        [self.synthesizer continueSpeaking];
        self.speechPaused = NO;
        [self updateChrome];
        return;
    }
    if (self.speechActive) {
        [self.synthesizer pauseSpeakingAtBoundary:AVSpeechBoundaryWord];
        self.speechPaused = YES;
        [self updateChrome];
        return;
    }
    [self startSpeech];
}

- (void)ttsLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self stopSpeech];
    }
}

- (void)startSpeech {
    NSString *raw = self.rawChapterText ?: @"";
    if (!raw.length) { return; }
    [self stopSpeech];

    NSInteger start = [self rawPositionForDecorated:[self currentPosition]];
    if (start < 0 || start >= (NSInteger)raw.length) { start = 0; }
    if ([YLTheme shared].pagedMode && self.pageRanges.count) {
        NSRange range = [self.pageRanges[self.pageIndex] rangeValue];
        start = [self rawPositionForDecorated:(NSInteger)range.location];
    }
    NSString *rest = [raw substringFromIndex:start];
    NSArray *chunks = [self speechChunks:rest];
    if (!chunks.count) { return; }

    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [session setActive:YES error:NULL];

    self.speechActive = YES;
    self.speechPaused = NO;
    self.speechFinished = 0;
    self.speechTotal = (NSInteger)chunks.count;

    for (NSString *chunk in chunks) {
        AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:chunk];
        AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"];
        if (voice) { utterance.voice = voice; }
        utterance.rate = 0.47;
        utterance.pitchMultiplier = 1.0;
        utterance.preUtteranceDelay = 0.02;
        utterance.postUtteranceDelay = 0.05;
        [self.synthesizer speakUtterance:utterance];
    }
    [self updateChrome];
}

- (void)stopSpeech {
    BOOL wasActive = self.speechActive;
    self.speechActive = NO;
    self.speechPaused = NO;
    self.speechFinished = 0;
    self.speechTotal = 0;
    if (wasActive || self.synthesizer.isSpeaking || self.synthesizer.isPaused) {
        [self.synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
    [[AVAudioSession sharedInstance] setActive:NO
        withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
             error:NULL];
    [self updateChrome];
}

- (NSArray *)speechChunks:(NSString *)text {
    NSMutableArray *chunks = [NSMutableArray array];
    NSMutableString *buffer = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length; i += 1) {
        unichar character = [text characterAtIndex:i];
        [buffer appendFormat:@"%C", character];
        BOOL boundary = (character == 0x3002 || character == 0xFF01 ||
                         character == 0xFF1F || character == 0xFF1B ||
                         character == 0x2026 || character == '\n' ||
                         character == '!' || character == '?' || character == ';');
        if (boundary && buffer.length >= 2) {
            NSString *chunk = [buffer stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (chunk.length) { [chunks addObject:chunk]; }
            buffer = [NSMutableString string];
        } else if (buffer.length >= 220) {
            NSString *chunk = [buffer stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (chunk.length) { [chunks addObject:chunk]; }
            buffer = [NSMutableString string];
        }
    }
    NSString *rest = [buffer stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (rest.length) { [chunks addObject:rest]; }
    return chunks;
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer
    didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (!self.speechActive) { return; }
    self.speechFinished += 1;
    if (self.speechFinished >= self.speechTotal) {
        self.speechActive = NO;
        self.speechPaused = NO;
        [[AVAudioSession sharedInstance] setActive:NO
            withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                 error:NULL];
        [self updateChrome];
    }
}

#pragma mark - 章节标签 / 进度

- (void)updateChrome {
    YLTheme *theme = [YLTheme shared];
    NSString *name = self.chapterTitle.length ? self.chapterTitle : (self.book[@"name"] ?: @"阅读");
    self.titleLabel.text = name;

    if (theme.pagedMode) {
        if (self.pageRanges.count) {
            self.pageLabel.text = [NSString stringWithFormat:@"%ld/%lu",
                (long)(self.pageIndex + 1), (unsigned long)self.pageRanges.count];
        } else {
            self.pageLabel.text = @"—";
        }
    } else {
        CGFloat maxOffset = MAX(1, self.scrollTextView.contentSize.height -
                                   self.scrollTextView.bounds.size.height);
        CGFloat ratio = MIN(1.0, MAX(0.0,
            self.scrollTextView.contentOffset.y / maxOffset));
        NSInteger percent = (NSInteger)(ratio * 100);
        self.pageLabel.text = [NSString stringWithFormat:@"%ld%%", (long)percent];
    }

    NSString *bookName = self.book[@"name"] ?: @"";
    self.headerLabel.hidden = !theme.showHeader;
    self.footerLabel.hidden = !theme.showFooter;
    if (name.length && bookName.length && ![bookName isEqualToString:name]) {
        self.headerLabel.text = [NSString stringWithFormat:@"%@  ·  %@",
                                 bookName, name];
    } else {
        self.headerLabel.text = name;
    }
    self.footerLabel.text = self.pageLabel.text ?: @"";
    [self updateBookmarkMark];

    if (self.speechActive && self.speechPaused) {
        [self.ttsButton setTitle:@"继续" forState:UIControlStateNormal];
    } else if (self.speechActive) {
        [self.ttsButton setTitle:@"暂停" forState:UIControlStateNormal];
    } else {
        [self.ttsButton setTitle:@"朗读" forState:UIControlStateNormal];
    }
}

- (void)scheduleSave {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveProgress) object:nil];
    [self performSelector:@selector(saveProgress) withObject:nil afterDelay:1.5];
}

- (void)saveProgress {
    if (!self.chapters.count) { return; }
    if (self.chapterIndex < 0 || self.chapterIndex >= (NSInteger)self.chapters.count) { return; }
    if (!self.chapterText.length) { return; }

    // 界面位置包含章节标题（可能还有分页留白），同步给安卓的必须是
    // 去掉标题后的正文字符位置，否则误差会越来越大。
    NSInteger position = [self rawPositionForDecorated:[self currentPosition]];
    NSInteger length = MAX(1, (NSInteger)self.rawChapterText.length);
    if (position > length) { position = length; }
    CGFloat ratio = MIN(1.0, MAX(0.0, (double)position / (double)length));
    NSDictionary *chapter = self.chapters[self.chapterIndex];

    NSDictionary *body = @{
        @"key": self.book[@"key"] ?: @"",
        @"name": self.book[@"name"] ?: @"",
        @"author": self.book[@"author"] ?: @"",
        @"sourceUrl": self.book[@"sourceUrl"] ?: @"",
        @"bookUrl": self.book[@"bookUrl"] ?: @"",
        @"chapterIndex": @(self.chapterIndex),
        @"chapterTitle": chapter[@"title"] ?: self.chapterTitle ?: @"",
        @"chapterUrl": chapter[@"url"] ?: @"",
        @"chapterCount": @(self.chapters.count),
        @"pos": @(MAX(0, position)),
        @"ratio": @(ratio),
        @"updatedAt": @((long long)([[NSDate date] timeIntervalSince1970] * 1000))
    };
    [[API shared] post:@"/api/progress" body:body completion:nil];
}

#pragma mark - UIPageViewController

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController
      viewControllerBeforeViewController:(UIViewController *)viewController {
    if (![viewController isKindOfClass:[YLPageViewController class]]) { return nil; }
    NSInteger page = ((YLPageViewController *)viewController).pageNumber;
    if (page <= 0) { return nil; }
    return [self pageControllerForPage:page - 1];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController
       viewControllerAfterViewController:(UIViewController *)viewController {
    if (![viewController isKindOfClass:[YLPageViewController class]]) { return nil; }
    NSInteger page = ((YLPageViewController *)viewController).pageNumber;
    if (page + 1 >= (NSInteger)self.pageRanges.count) { return nil; }
    return [self pageControllerForPage:page + 1];
}

- (void)pageViewController:(UIPageViewController *)pageViewController
        didFinishAnimating:(BOOL)finished
   previousViewControllers:(NSArray *)previousViewControllers
       transitionCompleted:(BOOL)completed {
    if (!completed) { return; }
    YLPageViewController *controller = pageViewController.viewControllers.firstObject;
    if (![controller isKindOfClass:[YLPageViewController class]]) { return; }
    self.pageIndex = controller.pageNumber;
    [self updateChrome];
    [self scheduleSave];
}

#pragma mark - UIScrollView

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if ([YLTheme shared].pagedMode) { return; }
    [self updateChrome];
    [self scheduleSave];
}

#pragma mark - 提示

- (void)showMessage:(NSString *)text {
    if (!text.length) { return; }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:nil message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
