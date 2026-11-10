#import "BookDetailViewController.h"
#import "API.h"
#import "YLComponents.h"
#import "YLTheme.h"
#import <math.h>

@interface BookDetailViewController ()
@property (nonatomic, strong) NSDictionary *book;
@property (nonatomic, strong) NSArray *chapters;
@property (nonatomic, strong) NSDictionary *progress;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UILabel *progressLabel;
@end

@implementation BookDetailViewController

- (instancetype)initWithBook:(NSDictionary *)book {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _book = [book isKindOfClass:[NSDictionary class]] ? book : @{};
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"书籍详情";
    self.tableView.rowHeight = 52;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 20, 0, 20);
    [[YLTheme shared] applyToViewController:self];
    [self loadDetail];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = YES;
    [[YLTheme shared] applyToViewController:self];
}

#pragma mark - 数据

- (NSString *)bookIntro {
    NSArray *keys = @[@"intro", @"introduce", @"summary", @"description", @"bookIntro", @"desc"];
    for (NSString *k in keys) {
        id v = self.book[k];
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) { return v; }
    }
    return nil;
}

- (void)loadDetail {
    NSString *source = self.book[@"sourceUrl"] ?: @"";
    NSString *url = self.book[@"bookUrl"] ?: self.book[@"key"] ?: @"";
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[@"source"] = source;
    query[@"url"] = url;
    if ([self.book[@"key"] isKindOfClass:[NSString class]]) {
        query[@"key"] = self.book[@"key"];
    }
    __weak BookDetailViewController *weakSelf = self;
    [[API shared] get:@"/api/toc" query:query completion:^(id result, NSError *error) {
        BookDetailViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        if (error) {
            [strongSelf buildHeader];
            [strongSelf.tableView reloadData];
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
        strongSelf.progress = strongSelf.book[@"progress"];
        if (![strongSelf.progress isKindOfClass:[NSDictionary class]]) {
            strongSelf.progress = nil;
        }
        [strongSelf buildHeader];
        [strongSelf.tableView reloadData];
    }];
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

- (NSInteger)chapterCount {
    NSInteger count = [self.book[@"chapterCount"] integerValue];
    if (count <= 0) { count = (NSInteger)self.chapters.count; }
    if (count <= 0) { count = [self.progress[@"chapterCount"] integerValue]; }
    return MAX(0, count);
}

- (CGFloat)overallRatio {
    CGFloat ratio = [self ratioFromProgress:self.progress];
    NSInteger count = [self chapterCount];
    NSInteger index = [self.progress[@"chapterIndex"] integerValue];
    if (count > 0 && index >= 0 && index < count) {
        return MIN(1.0, MAX(0.0, ((CGFloat)index + ratio) / (CGFloat)count));
    }
    return ratio;
}

#pragma mark - 头部（封面 + 信息）

- (void)buildHeader {
    YLTheme *theme = [YLTheme shared];
    CGFloat width = self.tableView.bounds.size.width;
    if (width < 1) { width = 320; }
    CGFloat headerHeight = 204;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, headerHeight)];
    header.backgroundColor = [UIColor clearColor];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 10, width - 32, 184)];
    [theme applyCardStyle:card];
    [header addSubview:card];

    UIImageView *cover = [[UIImageView alloc] initWithFrame:CGRectMake(14, 14, 82, 116)];
    cover.contentMode = UIViewContentModeScaleAspectFill;
    cover.clipsToBounds = YES;
    cover.layer.cornerRadius = 8;
    cover.image = [self coverImageForBook:self.book size:CGSizeMake(82, 116)];
    [card addSubview:cover];

    CGFloat textX = 110;
    CGFloat textWidth = card.bounds.size.width - textX - 14;
    NSString *name = self.book[@"name"];
    if (![name isKindOfClass:[NSString class]] || !name.length) { name = @"未命名"; }

    UILabel *title = [YLComponents labelWithFont:[theme uiFontOfSize:18 weight:UIFontWeightSemibold]
                                           color:theme.barTextColor];
    title.text = name;
    title.numberOfLines = 2;
    title.frame = CGRectMake(textX, 14, textWidth, 46);
    [card addSubview:title];

    NSString *author = self.book[@"author"];
    if (![author isKindOfClass:[NSString class]] || !author.length) { author = @"未知作者"; }
    UILabel *authorLabel = [YLComponents labelWithFont:[theme uiFontOfSize:12 weight:UIFontWeightRegular]
                                                 color:theme.tertiaryTextColor];
    authorLabel.text = author;
    authorLabel.frame = CGRectMake(textX, 62, textWidth, 16);
    [card addSubview:authorLabel];

    NSMutableArray *meta = [NSMutableArray array];
    NSString *source = self.book[@"sourceName"];
    if (![source isKindOfClass:[NSString class]] || !source.length) {
        source = [self.book[@"local"] boolValue] ? @"本地" : @"在线";
    }
    [meta addObject:source];
    NSInteger count = [self chapterCount];
    if (count > 0) { [meta addObject:[NSString stringWithFormat:@"%ld 章", (long)count]]; }
    long long words = [self.book[@"wordCount"] longLongValue];
    if (words > 0) { [meta addObject:[self wordText:words]]; }
    UILabel *metaLabel = [YLComponents labelWithFont:[theme uiFontOfSize:11 weight:UIFontWeightRegular]
                                               color:theme.tertiaryTextColor];
    metaLabel.text = [meta componentsJoinedByString:@"  ·  "];
    metaLabel.frame = CGRectMake(textX, 82, textWidth, 14);
    [card addSubview:metaLabel];

    self.progressLabel = [YLComponents labelWithFont:[theme uiFontOfSize:12 weight:UIFontWeightMedium]
                                               color:theme.accentColor];
    self.progressLabel.text = [self progressSummary];
    self.progressLabel.frame = CGRectMake(textX, 102, textWidth, 16);
    self.progressLabel.adjustsFontSizeToFitWidth = YES;
    self.progressLabel.minimumScaleFactor = 0.8;
    [card addSubview:self.progressLabel];

    self.progressTrack = [[UIView alloc] initWithFrame:CGRectMake(textX, 122, textWidth, 5)];
    self.progressTrack.backgroundColor = [theme.separatorColor colorWithAlphaComponent:0.6];
    self.progressTrack.layer.cornerRadius = 2.5;
    self.progressTrack.clipsToBounds = YES;
    [card addSubview:self.progressTrack];
    self.progressFill = [[UIView alloc] initWithFrame:CGRectZero];
    self.progressFill.backgroundColor = theme.accentColor;
    self.progressFill.layer.cornerRadius = 2.5;
    [self.progressTrack addSubview:self.progressFill];

    UIButton *readButton = [YLComponents filledButtonWithTitle:@"开始阅读"
                                                        target:self
                                                        action:@selector(startReading)];
    readButton.frame = CGRectMake(14, 142, 96, 30);
    [card addSubview:readButton];

    UIButton *tocButton = [YLComponents softButtonWithTitle:@"查看目录"
                                                     target:self
                                                     action:@selector(scrollToToc)];
    tocButton.frame = CGRectMake(118, 142, 88, 30);
    [card addSubview:tocButton];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(startReading)];
    [cover addGestureRecognizer:tap];
    cover.userInteractionEnabled = YES;

    self.headerView = header;
    self.tableView.tableHeaderView = header;
    [self layoutProgressFill];
}

- (void)layoutProgressFill {
    CGFloat ratio = [self overallRatio];
    CGFloat width = self.progressTrack.bounds.size.width * ratio;
    self.progressFill.frame = CGRectMake(0, 0, width, 5);
}

- (NSString *)progressSummary {
    CGFloat ratio = [self overallRatio];
    NSInteger percent = (NSInteger)lround(ratio * 100.0);
    NSInteger count = [self chapterCount];
    NSInteger index = [self.progress[@"chapterIndex"] integerValue];
    if (self.progress && count > 0) {
        return [NSString stringWithFormat:@"全书 %ld%% · 第 %ld/%ld 章",
                (long)percent, (long)MIN(count, MAX(1, index + 1)), (long)count];
    }
    if (self.progress) {
        NSInteger index = [self.progress[@"chapterIndex"] integerValue];
        return [NSString stringWithFormat:@"第 %ld 章 · 本章 %ld%%",
                (long)MAX(1, index + 1), (long)percent];
    }
    return count > 0
        ? [NSString stringWithFormat:@"尚未开始 · 共 %ld 章", (long)count]
        : @"尚未开始阅读";
}

- (NSString *)wordText:(long long)words {
    if (words >= 10000) {
        return [NSString stringWithFormat:@"%.1f 万字", words / 10000.0];
    }
    return [NSString stringWithFormat:@"%lld 字", words];
}

- (void)scrollToToc {
    NSInteger section = [self tocSection];
    if (section < 0 || section >= [self numberOfSectionsInTableView:self.tableView]) { return; }
    NSInteger rows = [self tableView:self.tableView numberOfRowsInSection:section];
    if (rows <= 0) { return; }
    [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]
                          atScrollPosition:UITableViewScrollPositionTop
                                  animated:YES];
}

#pragma mark - 表格

- (BOOL)hasIntro {
    NSString *intro = [self bookIntro];
    return intro.length > 0;
}

- (NSInteger)introSection {
    return [self hasIntro] ? 1 : -1;
}

- (NSInteger)tocSection {
    return [self hasIntro] ? 2 : 1;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self hasIntro] ? 3 : 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) { return 1; }
    if (section == [self introSection]) { return 1; }
    return self.chapters.count;
}

- (NSString *)sectionTitle:(NSInteger)section {
    if (section == 0) { return @"阅读记录"; }
    if (section == [self introSection]) { return @"书籍简介"; }
    return @"书籍目录";
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self sectionTitle:section];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    YLTheme *theme = [YLTheme shared];
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 40)];
    view.backgroundColor = [UIColor clearColor];
    UILabel *label = [YLComponents labelWithFont:[theme uiFontOfSize:12 weight:UIFontWeightSemibold]
                                           color:theme.secondaryTextColor];
    label.text = [self sectionTitle:section];
    label.frame = CGRectMake(20, 16, tableView.bounds.size.width - 40, 18);
    [view addSubview:label];
    return view;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 40;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 6;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == [self introSection]) {
        NSString *intro = [self bookIntro] ?: @"";
        CGFloat w = MAX(200, tableView.bounds.size.width - 52);
        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        ps.lineSpacing = 4;
        CGSize s = [intro boundingRectWithSize:CGSizeMake(w, CGFLOAT_MAX)
                                       options:NSStringDrawingUsesLineFragmentOrigin
                                    attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:14],
                                                 NSParagraphStyleAttributeName:ps}
                                       context:nil].size;
        return MAX(56, MIN(ceil(s.height) + 32, 260));
    }
    return indexPath.section == 0 ? 64 : 48;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    YLTheme *theme = [YLTheme shared];
    if (indexPath.section == [self introSection]) {
        static NSString *introId = @"IntroCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:introId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:introId];
            cell.textLabel.numberOfLines = 0;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        [theme styleCell:cell];
        cell.textLabel.text = [self bookIntro] ?: @"";
        cell.textLabel.textColor = theme.secondaryTextColor;
        cell.textLabel.font = [theme uiFontOfSize:14 weight:UIFontWeightRegular];
        return cell;
    }

    static NSString *identifier = @"DetailCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
    }
    [theme styleCell:cell];
    cell.textLabel.textColor = theme.barTextColor;
    cell.detailTextLabel.textColor = theme.tertiaryTextColor;

    if (indexPath.section == 0) {
        if (self.progress) {
            NSString *chapter = self.progress[@"chapterTitle"];
            if (![chapter isKindOfClass:[NSString class]] || !chapter.length) {
                chapter = @"上次位置";
            }
            long long time = [self.progress[@"updatedAt"] longLongValue];
            NSString *timeText = @"";
            if (time > 0) {
                timeText = [NSDateFormatter localizedStringFromDate:
                    [NSDate dateWithTimeIntervalSince1970:time / 1000.0]
                    dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
            }
            cell.textLabel.text = [NSString stringWithFormat:@"读到 %@", chapter];
            cell.textLabel.font = [theme uiFontOfSize:15 weight:UIFontWeightMedium];
            cell.detailTextLabel.text = timeText.length
                ? [NSString stringWithFormat:@"%@ · 全书 %ld%%", timeText,
                   (long)lround([self overallRatio] * 100.0)]
                : [NSString stringWithFormat:@"全书 %ld%%",
                   (long)lround([self overallRatio] * 100.0)];
        } else {
            cell.textLabel.text = @"还没有阅读记录";
            cell.textLabel.font = [theme uiFontOfSize:15 weight:UIFontWeightRegular];
            cell.detailTextLabel.text = @"点上方“开始阅读”";
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    NSDictionary *chapter = self.chapters[indexPath.row];
    NSString *title = chapter[@"title"] ?: @"";
    NSInteger current = [self.progress[@"chapterIndex"] integerValue];
    BOOL isCurrent = self.progress && indexPath.row == current;
    cell.textLabel.font = [theme uiFontOfSize:14 weight:(isCurrent ? UIFontWeightSemibold
                                                                  : UIFontWeightRegular)];
    cell.textLabel.textColor = isCurrent ? theme.accentColor : theme.barTextColor;
    cell.textLabel.text = [NSString stringWithFormat:@"%02ld   %@",
                           (long)indexPath.row + 1, title];
    cell.detailTextLabel.text = nil;
    cell.accessoryType = isCurrent
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    cell.tintColor = theme.accentColor;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != [self tocSection]) { return; }
    [self readAtChapter:indexPath.row];
}

#pragma mark - 阅读

- (void)startReading {
    if (!self.readBlock) { return; }
    // 传 nil 让阅读器先同步云端进度，再定位到最新位置。
    self.readBlock(self.book, nil, 0);
}

- (void)readAtChapter:(NSInteger)index {
    if (!self.readBlock) { return; }
    if (!self.chapters.count) {
        self.readBlock(self.book, nil, 0);
        return;
    }
    if (index < 0 || index >= (NSInteger)self.chapters.count) { index = 0; }
    self.readBlock(self.book, self.chapters, index);
}

#pragma mark - 封面

- (UIImage *)coverImageForBook:(NSDictionary *)book size:(CGSize)size {
    NSString *path = book[@"coverPath"];
    if ([path isKindOfClass:[NSString class]] && path.length) {
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        if (image) { return [self thumbnailForImage:image size:size]; }
    }
    return [self coverImageForTitle:book[@"name"] ?: @"" size:size];
}

- (UIImage *)thumbnailForImage:(UIImage *)image size:(CGSize)size {
    if (!image || size.width <= 0 || size.height <= 0) { return nil; }
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:
        CGRectMake(0, 0, size.width, size.height) cornerRadius:8];
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

    NSString *name = title.length ? title : @"未命名";
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    ps.lineBreakMode = NSLineBreakByWordWrapping;
    CGFloat fontSize = MAX(10, MIN(size.width * 0.17, 17));
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
    return image;
}

@end
