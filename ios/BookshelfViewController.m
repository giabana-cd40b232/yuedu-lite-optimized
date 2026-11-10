#import "BookshelfViewController.h"
#import "API.h"
#import "BookDetailViewController.h"
#import "CloudViewController.h"
#import "ReaderViewController.h"
#import "SettingsViewController.h"
#import "YLComponents.h"
#import "YLTheme.h"
#import <math.h>

static NSString *const kYLBookShelfModeKey = @"yl.bookshelf.mode";
static NSString *const kYLBookShelfFilterKey = @"yl.bookshelf.filter";

#pragma mark - 列表卡片 cell

@interface YLBookListCell : UITableViewCell
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, strong) UIImageView *chevronView;
- (void)applyTheme;
- (void)setProgressRatio:(CGFloat)ratio;
@end

@implementation YLBookListCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
             reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault
                  reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        self.card = [[UIView alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:self.card];

        self.coverView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.coverView.contentMode = UIViewContentModeScaleAspectFill;
        self.coverView.clipsToBounds = YES;
        self.coverView.layer.cornerRadius = 6;
        [self.card addSubview:self.coverView];

        self.nameLabel = [YLComponents labelWithFont:[UIFont systemFontOfSize:16]
                                               color:[UIColor blackColor]];
        self.nameLabel.numberOfLines = 2;
        [self.card addSubview:self.nameLabel];

        self.metaLabel = [YLComponents labelWithFont:[UIFont systemFontOfSize:12]
                                               color:[UIColor grayColor]];
        self.metaLabel.numberOfLines = 1;
        [self.card addSubview:self.metaLabel];

        self.progressLabel = [YLComponents labelWithFont:[UIFont systemFontOfSize:11]
                                                   color:[UIColor blueColor]];
        self.progressLabel.numberOfLines = 1;
        self.progressLabel.adjustsFontSizeToFitWidth = YES;
        self.progressLabel.minimumScaleFactor = 0.8;
        [self.card addSubview:self.progressLabel];

        self.progressTrack = [[UIView alloc] initWithFrame:CGRectZero];
        self.progressTrack.layer.cornerRadius = 1.5;
        self.progressTrack.clipsToBounds = YES;
        [self.card addSubview:self.progressTrack];
        self.progressFill = [[UIView alloc] initWithFrame:CGRectZero];
        self.progressFill.layer.cornerRadius = 1.5;
        [self.progressTrack addSubview:self.progressFill];

        self.chevronView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.chevronView.contentMode = UIViewContentModeScaleAspectFit;
        [self.card addSubview:self.chevronView];

        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    YLTheme *theme = [YLTheme shared];
    [theme applyCardStyle:self.card cornerRadius:14];
    self.nameLabel.font = [theme uiFontOfSize:16 weight:UIFontWeightSemibold];
    self.nameLabel.textColor = theme.barTextColor;
    self.metaLabel.textColor = theme.tertiaryTextColor;
    self.progressLabel.textColor = theme.accentColor;
    self.progressTrack.backgroundColor = [theme.separatorColor colorWithAlphaComponent:0.6];
    self.progressFill.backgroundColor = theme.accentColor;
    self.chevronView.image = [YLComponents iconNamed:@"chevron" size:13
                                               color:theme.tertiaryTextColor];
    self.coverView.backgroundColor = theme.accentSoftColor;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    YLTheme *theme = [YLTheme shared];
    self.card.backgroundColor = highlighted
        ? [theme.separatorColor colorWithAlphaComponent:0.55]
        : theme.cardBackground;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    self.card.frame = CGRectMake(16, 4, w - 32, h - 8);

    CGFloat cardW = self.card.bounds.size.width;
    self.coverView.frame = CGRectMake(12, 10, 44, 60);

    CGFloat textX = 12 + 44 + 12;
    CGFloat textW = cardW - textX - 30;
    self.nameLabel.frame = CGRectMake(textX, 10, textW, 22);
    self.metaLabel.frame = CGRectMake(textX, 34, textW, 16);
    self.progressLabel.frame = CGRectMake(textX, 52, textW, 14);
    self.progressTrack.frame = CGRectMake(textX, 70, textW, 3);
    [self setProgressRatio:self.progressFill.tag / 1000.0];
    self.chevronView.frame = CGRectMake(cardW - 24, (self.card.bounds.size.height - 13) / 2.0, 13, 13);
}

- (void)setProgressRatio:(CGFloat)ratio {
    CGFloat clamped = MIN(1.0, MAX(0.0, ratio));
    self.progressFill.tag = (NSInteger)lround(clamped * 1000.0);
    CGFloat width = self.progressTrack.bounds.size.width * clamped;
    self.progressFill.frame = CGRectMake(0, 0, width, 3);
}

@end

#pragma mark - 大图标网格 cell

@interface YLBookGridCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *percentLabel;
- (void)applyTheme;
@end

@implementation YLBookGridCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.coverView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.coverView.contentMode = UIViewContentModeScaleAspectFill;
        self.coverView.clipsToBounds = YES;
        self.coverView.layer.cornerRadius = 8;
        [self.contentView addSubview:self.coverView];

        self.nameLabel = [YLComponents labelWithFont:[UIFont systemFontOfSize:12]
                                               color:[UIColor blackColor]];
        self.nameLabel.textAlignment = NSTextAlignmentCenter;
        self.nameLabel.numberOfLines = 2;
        [self.contentView addSubview:self.nameLabel];

        self.percentLabel = [YLComponents labelWithFont:[UIFont systemFontOfSize:10]
                                                  color:[UIColor grayColor]];
        self.percentLabel.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:self.percentLabel];
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    YLTheme *theme = [YLTheme shared];
    self.nameLabel.font = [theme uiFontOfSize:12 weight:UIFontWeightMedium];
    self.nameLabel.textColor = theme.barTextColor;
    self.percentLabel.textColor = theme.tertiaryTextColor;
    self.coverView.backgroundColor = theme.accentSoftColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat coverHeight = floor(width * 1.38);
    self.coverView.frame = CGRectMake(0, 0, width, coverHeight);
    self.nameLabel.frame = CGRectMake(0, coverHeight + 6, width, 30);
    self.percentLabel.frame = CGRectMake(0, coverHeight + 34, width, 12);
}

@end

#pragma mark - 书架

@interface BookshelfViewController ()
<UITableViewDataSource, UITableViewDelegate,
 UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) NSArray *books;
@property (nonatomic, strong) NSMutableArray *filteredBooks;
@property (nonatomic, assign) NSInteger mode;    // 0 列表 1 大图标
@property (nonatomic, assign) NSInteger filter;  // 0 全部 1 本地

@property (nonatomic, strong) UITableView *listView;
@property (nonatomic, strong) UICollectionView *gridView;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

static NSMutableDictionary *YLCoverCache(void) {
    static NSMutableDictionary *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    return cache;
}

@implementation BookshelfViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"书架";
    self.filteredBooks = [NSMutableArray array];
    self.mode = [[NSUserDefaults standardUserDefaults]
        integerForKey:kYLBookShelfModeKey];
    // 立体书架已移除：旧版本保存的 mode=2 归位到大图标
    if (self.mode < 0 || self.mode > 1) {
        self.mode = 1;
        [[NSUserDefaults standardUserDefaults] setInteger:self.mode
                                                   forKey:kYLBookShelfModeKey];
    }
    self.filter = [[NSUserDefaults standardUserDefaults]
        integerForKey:kYLBookShelfFilterKey];

    [self buildFilter];
    [self buildModeButton];
    [self buildToolbar];
    [self buildListView];
    [self buildGridView];
    [self buildEmptyView];
    [self applyMode];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:NO];
    self.navigationController.toolbarHidden = NO;
    [[YLTheme shared] applyToViewController:self];
    [self applyTheme];
    // 风格在“设置 - 书架风格”里改，每次进入书架时重新读取
    NSInteger savedMode = [[NSUserDefaults standardUserDefaults]
        integerForKey:kYLBookShelfModeKey];
    if (savedMode < 0 || savedMode > 1) { savedMode = 1; }
    if (savedMode != self.mode) {
        self.mode = savedMode;
        [self applyMode];
    }
    [self reload];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect bounds = self.view.bounds;
    self.listView.frame = bounds;
    self.gridView.frame = bounds;
    self.emptyView.frame = bounds;
}

#pragma mark - 布局切换

- (void)buildFilter {
    UISegmentedControl *filter = [[UISegmentedControl alloc]
        initWithItems:@[@"全部", @"本地"]];
    filter.frame = CGRectMake(0, 0, 132, 28);
    filter.selectedSegmentIndex = self.filter;
    filter.tintColor = [[YLTheme shared] accentColor];
    [filter addTarget:self action:@selector(filterChanged:)
     forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = filter;
}

- (void)buildModeButton {
    UIImage *icon = [YLComponents iconNamed:(self.mode == 0 ? @"grid" : @"list")
                                       size:20
                                      color:[[YLTheme shared] accentColor]];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:icon
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(toggleMode)];
}

- (void)buildToolbar {
    CGFloat iconSize = 20;
    UIColor *accent = [[YLTheme shared] accentColor];
    UIBarButtonItem *cloud =
        [[UIBarButtonItem alloc] initWithImage:[YLComponents iconNamed:@"cloud"
                                                                 size:iconSize
                                                                color:accent]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(openCloud)];
    UIBarButtonItem *pull =
        [[UIBarButtonItem alloc] initWithImage:[YLComponents iconNamed:@"download"
                                                                 size:iconSize
                                                                color:accent]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(pullProgress)];
    UIBarButtonItem *push =
        [[UIBarButtonItem alloc] initWithImage:[YLComponents iconNamed:@"upload"
                                                                 size:iconSize
                                                                color:accent]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(pushProgress)];
    UIBarButtonItem *flex =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                       target:nil
                                                       action:nil];
    self.toolbarItems = @[cloud, flex, pull, push];
}

- (void)buildListView {
    self.listView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                 style:UITableViewStylePlain];
    self.listView.rowHeight = 92;
    self.listView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.listView.backgroundColor = [[YLTheme shared] appBackground];
    self.listView.tableFooterView = [[UIView alloc] init];
    self.listView.dataSource = self;
    self.listView.delegate = self;
    self.listView.contentInset = UIEdgeInsetsMake(8, 0, 12, 0);
    [self.view addSubview:self.listView];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(longPressed:)];
    [self.listView addGestureRecognizer:press];
}

- (void)buildGridView {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 12;
    layout.minimumLineSpacing = 18;
    layout.sectionInset = UIEdgeInsetsMake(16, 16, 24, 16);
    self.gridView = [[UICollectionView alloc] initWithFrame:self.view.bounds
                                       collectionViewLayout:layout];
    self.gridView.backgroundColor = [[YLTheme shared] appBackground];
    self.gridView.dataSource = self;
    self.gridView.delegate = self;
    [self.gridView registerClass:[YLBookGridCell class]
      forCellWithReuseIdentifier:@"GridCell"];
    [self.view addSubview:self.gridView];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(longPressed:)];
    [self.gridView addGestureRecognizer:press];
}

- (void)buildEmptyView {
    YLTheme *theme = [YLTheme shared];
    self.emptyView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.emptyView.backgroundColor = theme.appBackground;
    self.emptyView.hidden = YES;

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
    icon.image = [YLComponents iconNamed:@"books" size:44 color:theme.tertiaryTextColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tag = 1;
    [self.emptyView addSubview:icon];

    UILabel *label = [YLComponents labelWithFont:[theme uiFontOfSize:15 weight:UIFontWeightMedium]
                                           color:theme.secondaryTextColor];
    label.text = @"书架还是空的";
    label.textAlignment = NSTextAlignmentCenter;
    label.tag = 2;
    [self.emptyView addSubview:label];

    UILabel *hint = [YLComponents labelWithFont:[theme uiFontOfSize:12 weight:UIFontWeightRegular]
                                          color:theme.tertiaryTextColor];
    hint.text = @"去云端书库挑一本，或导入本地文件";
    hint.textAlignment = NSTextAlignmentCenter;
    hint.tag = 3;
    [self.emptyView addSubview:hint];

    UIButton *button = [YLComponents filledButtonWithTitle:@"打开云端书库"
                                                    target:self
                                                    action:@selector(openCloud)];
    button.tag = 4;
    [self.emptyView addSubview:button];
    [self.view addSubview:self.emptyView];
}

- (void)applyTheme {
    YLTheme *theme = [YLTheme shared];
    self.view.backgroundColor = theme.appBackground;
    self.listView.backgroundColor = theme.appBackground;
    self.gridView.backgroundColor = theme.appBackground;
    self.emptyView.backgroundColor = theme.appBackground;
    ((UIImageView *)[self.emptyView viewWithTag:1]).image =
        [YLComponents iconNamed:@"books" size:44 color:theme.tertiaryTextColor];
    ((UILabel *)[self.emptyView viewWithTag:2]).textColor = theme.secondaryTextColor;
    ((UILabel *)[self.emptyView viewWithTag:3]).textColor = theme.tertiaryTextColor;
    UIButton *emptyButton = (UIButton *)[self.emptyView viewWithTag:4];
    emptyButton.backgroundColor = theme.accentColor;
    [emptyButton setTitleColor:(theme.nightMode
        ? [UIColor colorWithRed:0.055 green:0.075 blue:0.125 alpha:1]
        : [UIColor whiteColor]) forState:UIControlStateNormal];
    [self buildModeButton];
    [self buildToolbar];
    [self.listView reloadData];
    [self.gridView reloadData];
}

- (void)applyMode {
    // 0 列表，1 大图标（立体书架已移除）
    self.listView.hidden = self.mode != 0;
    self.gridView.hidden = self.mode != 1;
    self.emptyView.hidden = self.filteredBooks.count > 0;
    [self buildModeButton];
}

- (void)toggleMode {
    self.mode = self.mode == 0 ? 1 : 0;
    [[NSUserDefaults standardUserDefaults] setInteger:self.mode
                                               forKey:kYLBookShelfModeKey];
    [self applyMode];
    [self refreshViews];
}

- (void)modeChanged:(UISegmentedControl *)segment {
    self.mode = segment.selectedSegmentIndex;
    [[NSUserDefaults standardUserDefaults] setInteger:self.mode
                                               forKey:kYLBookShelfModeKey];
    [self applyMode];
    [self refreshViews];
}

- (void)filterChanged:(UISegmentedControl *)segment {
    self.filter = segment.selectedSegmentIndex;
    [[NSUserDefaults standardUserDefaults] setInteger:self.filter
                                               forKey:kYLBookShelfFilterKey];
    [self applyFilter];
}

#pragma mark - 数据

- (void)reload {
    __weak BookshelfViewController *weakSelf = self;
    [[API shared] get:@"/api/shelf" query:nil completion:^(id result, NSError *error) {
        BookshelfViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        if (error) {
            [strongSelf showMessage:error.localizedDescription];
            return;
        }
        NSDictionary *payload = [result isKindOfClass:[NSDictionary class]] ? result : nil;
        strongSelf.books = [payload[@"books"] isKindOfClass:[NSArray class]]
            ? payload[@"books"] : @[];
        [strongSelf applyFilter];
    }];
}

- (void)applyFilter {
    [self.filteredBooks removeAllObjects];
    for (NSDictionary *book in self.books) {
        if (self.filter == 1 && ![book[@"local"] boolValue]) { continue; }
        [self.filteredBooks addObject:book];
    }
    [self refreshViews];
}

- (void)refreshViews {
    [self.listView reloadData];
    [self.gridView reloadData];
    self.emptyView.hidden = self.filteredBooks.count > 0;
}

#pragma mark - 进度

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

- (CGFloat)overallRatioForBook:(NSDictionary *)book {
    NSDictionary *progress = book[@"progress"];
    if (![progress isKindOfClass:[NSDictionary class]]) { return 0; }
    CGFloat ratio = [self ratioFromProgress:progress];
    NSInteger count = [book[@"chapterCount"] integerValue];
    if (count <= 0) { count = [progress[@"chapterCount"] integerValue]; }
    NSInteger index = [progress[@"chapterIndex"] integerValue];
    if (count > 0 && index >= 0 && index < count) {
        return MIN(1.0, MAX(0.0, ((CGFloat)index + ratio) / (CGFloat)count));
    }
    return ratio;
}

#pragma mark - 列表

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredBooks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"BookCell";
    YLBookListCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[YLBookListCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];
    }
    [cell applyTheme];

    NSDictionary *book = self.filteredBooks[indexPath.row];
    NSDictionary *progress = [book[@"progress"] isKindOfClass:[NSDictionary class]]
        ? book[@"progress"] : nil;

    cell.nameLabel.text = book[@"name"] ?: @"未命名";
    cell.coverView.image = [self coverImageForBook:book size:CGSizeMake(44, 60)];

    NSString *author = book[@"author"];
    if (![author isKindOfClass:[NSString class]] || !author.length) { author = @"未知作者"; }
    NSString *source = book[@"sourceName"];
    if (![source isKindOfClass:[NSString class]] || !source.length) {
        source = [book[@"local"] boolValue] ? @"本地" : @"在线";
    }
    cell.metaLabel.text = [NSString stringWithFormat:@"%@ · %@", author, source];

    CGFloat overall = [self overallRatioForBook:book];
    NSInteger percent = (NSInteger)lround(overall * 100.0);
    NSInteger count = [book[@"chapterCount"] integerValue];
    if (count <= 0 && progress) { count = [progress[@"chapterCount"] integerValue]; }
    if (count > 0) {
        NSInteger index = [progress[@"chapterIndex"] integerValue] + 1;
        cell.progressLabel.text = [NSString stringWithFormat:@"全书 %ld%% · 第 %ld/%ld 章",
            (long)percent, (long)MIN(count, MAX(1, index)), (long)count];
    } else if (progress) {
        NSInteger index = [progress[@"chapterIndex"] integerValue] + 1;
        cell.progressLabel.text = [NSString stringWithFormat:@"第 %ld 章 · 本章 %ld%%",
            (long)MAX(1, index), (long)percent];
    } else {
        cell.progressLabel.text = @"尚未开始阅读";
    }
    [cell setProgressRatio:overall];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self openBook:self.filteredBooks[indexPath.row]];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) { return; }
    NSDictionary *book = self.filteredBooks[indexPath.row];
    NSString *key = book[@"key"];
    if (![key isKindOfClass:[NSString class]] || !key.length) { return; }
    __weak BookshelfViewController *weakSelf = self;
    [[API shared] post:@"/api/shelf/remove" body:@{@"key": key}
           completion:^(id result, NSError *error) {
        BookshelfViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        if (error) {
            [strongSelf showMessage:error.localizedDescription];
            return;
        }
        [strongSelf reload];
    }];
}

#pragma mark - 大图标网格

- (NSInteger)collectionView:(UICollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return self.filteredBooks.count;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)layout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = floor((self.view.bounds.size.width - 32 - 24) / 3.0);
    return CGSizeMake(width, floor(width * 1.38) + 52);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    YLBookGridCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"GridCell"
                                                                     forIndexPath:indexPath];
    [cell applyTheme];
    NSDictionary *book = self.filteredBooks[indexPath.row];
    CGFloat width = floor((self.view.bounds.size.width - 32 - 24) / 3.0);
    cell.coverView.image = [self coverImageForBook:book
                                             size:CGSizeMake(width, floor(width * 1.38))];
    cell.nameLabel.text = book[@"name"] ?: @"未命名";
    CGFloat overall = [self overallRatioForBook:book];
    cell.percentLabel.text = overall > 0
        ? [NSString stringWithFormat:@"%ld%%", (long)lround(overall * 100.0)]
        : @"未读";
    cell.contentView.backgroundColor = [UIColor clearColor];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView
    didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [self openBook:self.filteredBooks[indexPath.row]];
}

#pragma mark - 长按查看详情

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) { return; }
    CGPoint point = [gesture locationInView:gesture.view];
    NSInteger index = -1;
    if (gesture.view == self.listView) {
        NSIndexPath *path = [self.listView indexPathForRowAtPoint:point];
        if (path) { index = path.row; }
    } else if (gesture.view == self.gridView) {
        NSIndexPath *path = [self.gridView indexPathForItemAtPoint:point];
        if (path) { index = path.item; }
    }
    if (index < 0 || index >= (NSInteger)self.filteredBooks.count) { return; }
    [self showBookDetail:self.filteredBooks[index]];
}

- (void)showBookDetail:(NSDictionary *)book {
    BookDetailViewController *detail = [[BookDetailViewController alloc] initWithBook:book];
    __weak BookshelfViewController *weakSelf = self;
    detail.readBlock = ^(NSDictionary *targetBook, NSArray *chapters, NSInteger index) {
        BookshelfViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        [strongSelf openBookAtChapter:targetBook chapters:chapters index:index];
    };
    [self.navigationController pushViewController:detail animated:YES];
}

#pragma mark - 打开书籍

- (void)openBook:(NSDictionary *)book {
    [self openBookAtChapter:book chapters:nil index:0];
}

// 打开书之前先拉一次云端进度，再用最新的书架数据进阅读页
- (void)openBookAtChapter:(NSDictionary *)book chapters:(NSArray *)chapters index:(NSInteger)index {
    if (![book isKindOfClass:[NSDictionary class]]) { return; }
    NSString *key = book[@"key"];
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

    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    if ([key isKindOfClass:[NSString class]] && key.length) { body[@"key"] = key; }
    __weak BookshelfViewController *weakSelf = self;
    [[API shared] post:@"/api/sync/pullBook" body:body
            completion:^(id result, NSError *error) {
        BookshelfViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        [strongSelf pushReaderForBookWithKey:key
                                    fallback:book
                                    chapters:chapters
                                       index:index];
    }];
}

- (void)pushReaderForBookWithKey:(NSString *)key
                        fallback:(NSDictionary *)fallback
                        chapters:(NSArray *)chapters
                           index:(NSInteger)index {
    __weak BookshelfViewController *weakSelf = self;
    [[API shared] get:@"/api/shelf" query:nil completion:^(id result, NSError *error) {
        BookshelfViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        NSDictionary *book = fallback;
        if (!error) {
            NSDictionary *payload = [result isKindOfClass:[NSDictionary class]] ? result : nil;
            NSArray *books = [payload[@"books"] isKindOfClass:[NSArray class]]
                ? payload[@"books"] : @[];
            if ([key isKindOfClass:[NSString class]] && key.length) {
                for (NSDictionary *candidate in books) {
                    if ([candidate[@"key"] isEqualToString:key]) { book = candidate; break; }
                }
            }
        }
        // 检查当前导航栈中是否已存在该书的阅读器
        UIViewController *topVC = strongSelf.navigationController.topViewController;
        if ([topVC isKindOfClass:[ReaderViewController class]]) {
            NSDictionary *currentBook = [(ReaderViewController *)topVC valueForKey:@"book"] ?: @{};
            if ([currentBook[@"key"] isEqualToString:key]) {
                return;
            }
        }
        ReaderViewController *reader = nil;
        if ([chapters isKindOfClass:[NSArray class]] && chapters.count) {
            reader = [[ReaderViewController alloc] initWithBook:book
                                                       chapters:chapters
                                                          index:index];
        } else {
            reader = [[ReaderViewController alloc] initWithBook:book];
        }
        [strongSelf.navigationController pushViewController:reader animated:YES];
    }];
}

#pragma mark - 封面

- (UIImage *)coverImageForBook:(NSDictionary *)book size:(CGSize)size {
    NSString *path = book[@"coverPath"];
    if ([path isKindOfClass:[NSString class]] && path.length) {
        UIImage *image = [self coverImageAtPath:path size:size];
        if (image) { return image; }
    }
    return [self coverImageForTitle:book[@"name"] ?: @"" size:size];
}

- (UIImage *)coverImageAtPath:(NSString *)path size:(CGSize)size {
    NSString *cacheKey = [NSString stringWithFormat:@"%.0fx%.0f|%@",
                          size.width, size.height, path];
    NSMutableDictionary *cache = YLCoverCache();
    UIImage *cached = cache[cacheKey];
    if (cached) { return cached; }
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (!image) { return nil; }
    UIImage *thumbnail = [self thumbnailForImage:image size:size];
    if (thumbnail) {
        if (cache.count > 60) { [cache removeAllObjects]; }
        cache[cacheKey] = thumbnail;
    }
    return thumbnail ?: image;
}

- (UIImage *)thumbnailForImage:(UIImage *)image size:(CGSize)size {
    if (!image || size.width <= 0 || size.height <= 0) { return nil; }
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:
        CGRectMake(0, 0, size.width, size.height) cornerRadius:6];
    [path addClip];
    CGFloat scale = MAX(size.width / MAX(1, image.size.width),
                        size.height / MAX(1, image.size.height));
    CGFloat drawWidth = image.size.width * scale;
    CGFloat drawHeight = image.size.height * scale;
    [image drawInRect:CGRectMake((size.width - drawWidth) / 2,
                                 (size.height - drawHeight) / 2,
                                 drawWidth, drawHeight)];
    UIImage *thumbnail = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return thumbnail;
}

- (UIImage *)coverImageForTitle:(NSString *)title size:(CGSize)size {
    NSString *key = [NSString stringWithFormat:@"title|%.0fx%.0f|%@",
                     size.width, size.height, title.length ? title : @"?"];
    NSMutableDictionary *cache = YLCoverCache();
    UIImage *cached = cache[key];
    if (cached) { return cached; }

    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat top[4] = {0.204, 0.435, 0.925, 1.0};
    CGFloat bottom[4] = {0.365, 0.545, 0.980, 1.0};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, top, bottom, 2);
    CGContextDrawLinearGradient(context, gradient,
        CGPointMake(0, 0), CGPointMake(0, size.height), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);

    CGContextSetFillColorWithColor(context,
        [UIColor colorWithWhite:1.0 alpha:0.08].CGColor);
    CGContextFillEllipseInRect(context,
        CGRectMake(size.width * 0.35, size.height * 0.62, size.width, size.width));

    // 用完整书名（自动换行）代替首字，避免所有书看起来一样
    NSString *name = title.length ? title : @"未命名";
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    ps.lineBreakMode = NSLineBreakByWordWrapping;
    CGFloat fontSize = MAX(9, MIN(size.width * 0.16, 16));
    NSDictionary *attributes = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:fontSize],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.95],
        NSParagraphStyleAttributeName: ps
    };
    CGRect textRect = CGRectInset(CGRectMake(0, 0, size.width, size.height),
                                  MAX(4, size.width * 0.08),
                                  MAX(6, size.height * 0.10));
    CGSize textSize = [name boundingRectWithSize:textRect.size
                                         options:NSStringDrawingUsesLineFragmentOrigin
                                      attributes:attributes context:nil].size;
    textRect.size.height = MIN(textSize.height, textRect.size.height);
    textRect.origin.y = (size.height - textRect.size.height) / 2.0;
    [name drawWithRect:textRect options:NSStringDrawingUsesLineFragmentOrigin
            attributes:attributes context:nil];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) { cache[key] = image; }
    return image;
}

#pragma mark - 工具条操作

- (void)openCloud {
    CloudViewController *controller = [[CloudViewController alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)pullProgress {
    [[API shared] post:@"/api/sync/pull" body:@{} completion:^(id result, NSError *error) {
        if (error) {
            [self showMessage:error.localizedDescription];
            return;
        }
        NSDictionary *payload = result;
        [self showMessage:[NSString stringWithFormat:@"已拉取 %@ 条进度，共 %@ 条",
                           payload[@"pulled"] ?: @0, payload[@"total"] ?: @0]];
        [self reload];
    }];
}

- (void)pushProgress {
    [[API shared] post:@"/api/sync/push" body:@{} completion:^(id result, NSError *error) {
        if (error) {
            [self showMessage:error.localizedDescription];
            return;
        }
        NSDictionary *payload = result;
        [self showMessage:[NSString stringWithFormat:@"已上传 %@ 条进度",
                           payload[@"pushed"] ?: @0]];
    }];
}

- (void)showSettings {
    SettingsViewController *controller =
        [[SettingsViewController alloc] initWithStyle:UITableViewStyleGrouped];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:controller];
    [[YLTheme shared] applyAppearance];
    [self presentViewController:navigation animated:YES completion:nil];
}

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
