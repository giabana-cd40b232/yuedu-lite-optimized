#import "TocViewController.h"
#import "API.h"
#import "ReaderViewController.h"
#import "YLComponents.h"
#import "YLTheme.h"

@interface YLTocCell : UITableViewCell
@property (nonatomic, strong) UILabel *numberLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIView *marker;
- (void)applyTheme;
@end

@implementation YLTocCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
             reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault
                  reuseIdentifier:reuseIdentifier];
    if (self) {
        self.marker = [[UIView alloc] initWithFrame:CGRectZero];
        self.marker.layer.cornerRadius = 1.5;
        [self.contentView addSubview:self.marker];

        self.numberLabel = [YLComponents labelWithFont:[UIFont systemFontOfSize:11]
                                                 color:[UIColor lightGrayColor]];
        self.numberLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:self.numberLabel];

        self.titleLabel = [YLComponents labelWithFont:[UIFont systemFontOfSize:14]
                                                color:[UIColor blackColor]];
        self.titleLabel.numberOfLines = 1;
        [self.contentView addSubview:self.titleLabel];
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    YLTheme *theme = [YLTheme shared];
    self.backgroundColor = theme.cellBackground;
    self.contentView.backgroundColor = theme.cellBackground;
    self.numberLabel.textColor = theme.tertiaryTextColor;
    self.titleLabel.textColor = theme.barTextColor;
    self.marker.backgroundColor = [UIColor clearColor];
    UIView *selected = [[UIView alloc] init];
    selected.backgroundColor = [theme.separatorColor colorWithAlphaComponent:0.5];
    self.selectedBackgroundView = selected;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    self.marker.frame = CGRectMake(8, 17, 3, 18);
    self.numberLabel.frame = CGRectMake(18, 0, 26, self.contentView.bounds.size.height);
    self.titleLabel.frame = CGRectMake(52, 0, width - 68, self.contentView.bounds.size.height);
}

@end

@interface TocViewController ()
@property (nonatomic, strong) NSDictionary *book;
@property (nonatomic, strong) NSArray *chapters;
@property (nonatomic, assign) NSInteger progressIndex;
@property (nonatomic, strong) UILabel *countLabel;
@end

@implementation TocViewController

- (instancetype)initWithBook:(NSDictionary *)book {
    return [self initWithBook:book chapters:nil];
}

- (instancetype)initWithBook:(NSDictionary *)book chapters:(NSArray *)chapters {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _book = [book isKindOfClass:[NSDictionary class]] ? book : @{};
        _chapters = [chapters isKindOfClass:[NSArray class]] ? chapters : nil;
        _selectedIndex = -1;
        _progressIndex = -1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.book[@"name"] ?: @"目录";
    self.tableView.rowHeight = 52;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.tableFooterView = [[UIView alloc] init];
    [self buildTableHeader];
    [[YLTheme shared] applyToViewController:self];
    if (self.chapters.count) {
        [self setupProgressIndex];
        [self updateCountLabel];
        [self.tableView reloadData];
        [self scrollToProgress];
    } else {
        [self loadChapters];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = YES;
    [[YLTheme shared] applyToViewController:self];
    [self.tableView reloadData];
}

- (void)buildTableHeader {
    YLTheme *theme = [YLTheme shared];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 40)];
    header.backgroundColor = theme.appBackground;
    self.countLabel = [YLComponents labelWithFont:[theme uiFontOfSize:12 weight:UIFontWeightMedium]
                                            color:theme.tertiaryTextColor];
    self.countLabel.frame = CGRectMake(20, 12, header.bounds.size.width - 40, 18);
    [header addSubview:self.countLabel];
    self.tableView.tableHeaderView = header;
}

- (void)updateCountLabel {
    NSInteger count = (NSInteger)self.chapters.count;
    NSString *text = count > 0
        ? [NSString stringWithFormat:@"共 %ld 章", (long)count] : @"正在加载目录…";
    if (self.progressIndex >= 0) {
        text = [text stringByAppendingFormat:@"  ·  当前第 %ld 章", (long)self.progressIndex + 1];
    }
    self.countLabel.text = text;
}

#pragma mark - 数据

- (void)loadChapters {
    NSString *source = self.book[@"sourceUrl"] ?: @"";
    NSString *url = self.book[@"bookUrl"] ?: self.book[@"key"] ?: @"";
    __weak TocViewController *weakSelf = self;
    [[API shared] get:@"/api/toc" query:@{@"source": source, @"url": url}
           completion:^(id result, NSError *error) {
        TocViewController *strongSelf = weakSelf;
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
        [strongSelf setupProgressIndex];
        [strongSelf updateCountLabel];
        [strongSelf.tableView reloadData];
        [strongSelf scrollToProgress];
    }];
}

- (void)setupProgressIndex {
    NSInteger index = self.selectedIndex;
    if (index < 0) {
        NSDictionary *progress = self.book[@"progress"];
        if ([progress isKindOfClass:[NSDictionary class]]) {
            id value = progress[@"chapterIndex"];
            if ([value respondsToSelector:@selector(integerValue)]) {
                index = [value integerValue];
            }
        }
    }
    if (index < 0 || index >= (NSInteger)self.chapters.count) { index = -1; }
    self.progressIndex = index;
}

- (void)scrollToProgress {
    if (self.progressIndex < 0) { return; }
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.progressIndex inSection:0];
    [self.tableView scrollToRowAtIndexPath:indexPath
                          atScrollPosition:UITableViewScrollPositionMiddle
                                  animated:NO];
}

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.chapters.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"ChapterCell";
    YLTocCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[YLTocCell alloc] initWithStyle:UITableViewCellStyleDefault
                                reuseIdentifier:identifier];
    }
    YLTheme *theme = [YLTheme shared];
    [cell applyTheme];
    NSDictionary *chapter = self.chapters[indexPath.row];
    cell.numberLabel.text = [NSString stringWithFormat:@"%02ld", (long)indexPath.row + 1];
    cell.titleLabel.text = chapter[@"title"] ?: @"";
    if ((NSInteger)indexPath.row == self.progressIndex) {
        cell.titleLabel.textColor = theme.accentColor;
        cell.titleLabel.font = [theme uiFontOfSize:14 weight:UIFontWeightSemibold];
        cell.numberLabel.textColor = theme.accentColor;
        cell.marker.backgroundColor = theme.accentColor;
    } else {
        cell.titleLabel.textColor = theme.barTextColor;
        cell.titleLabel.font = [theme uiFontOfSize:14 weight:UIFontWeightRegular];
        cell.numberLabel.textColor = theme.tertiaryTextColor;
        cell.marker.backgroundColor = [UIColor clearColor];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.selectBlock) {
        self.selectBlock(indexPath.row, self.chapters, self.book);
        return;
    }
    ReaderViewController *reader = [[ReaderViewController alloc] initWithBook:self.book
                                                                   chapters:self.chapters
                                                                      index:indexPath.row];
    [self.navigationController pushViewController:reader animated:YES];
}

- (void)showMessage:(NSString *)text {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:nil message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
