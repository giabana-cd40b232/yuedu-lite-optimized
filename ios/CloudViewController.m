#import "CloudViewController.h"
#import "API.h"
#import "YLComponents.h"
#import "YLTheme.h"

@interface YLCloudCell : UITableViewCell
@property (nonatomic, strong) UIView *iconBG;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UIImageView *chevronView;
- (void)applyTheme;
@end

@implementation YLCloudCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
             reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault
                  reuseIdentifier:reuseIdentifier];
    if (self) {
        self.iconBG = [[UIView alloc] initWithFrame:CGRectZero];
        self.iconBG.layer.cornerRadius = 10;
        [self.contentView addSubview:self.iconBG];

        self.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.iconBG addSubview:self.iconView];

        self.nameLabel = [YLComponents labelWithFont:[UIFont systemFontOfSize:15]
                                               color:[UIColor blackColor]];
        self.nameLabel.numberOfLines = 1;
        [self.contentView addSubview:self.nameLabel];

        self.detailLabel = [YLComponents labelWithFont:[UIFont systemFontOfSize:11]
                                                 color:[UIColor grayColor]];
        self.detailLabel.numberOfLines = 1;
        [self.contentView addSubview:self.detailLabel];

        self.badgeLabel = [YLComponents labelWithFont:[UIFont systemFontOfSize:10]
                                                color:[UIColor blueColor]];
        self.badgeLabel.textAlignment = NSTextAlignmentCenter;
        self.badgeLabel.layer.cornerRadius = 4;
        self.badgeLabel.layer.masksToBounds = YES;
        self.badgeLabel.layer.borderWidth = 0.5;
        [self.contentView addSubview:self.badgeLabel];

        self.chevronView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.chevronView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:self.chevronView];
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    YLTheme *theme = [YLTheme shared];
    self.backgroundColor = theme.cellBackground;
    self.contentView.backgroundColor = theme.cellBackground;
    self.nameLabel.font = [theme uiFontOfSize:15 weight:UIFontWeightMedium];
    self.nameLabel.textColor = theme.barTextColor;
    self.detailLabel.textColor = theme.tertiaryTextColor;
    self.iconBG.backgroundColor = theme.accentSoftColor;
    self.badgeLabel.textColor = theme.accentColor;
    self.badgeLabel.layer.borderColor = theme.accentColor.CGColor;
    self.chevronView.image = [YLComponents iconNamed:@"chevron" size:13
                                               color:theme.tertiaryTextColor];
    UIView *selected = [[UIView alloc] init];
    selected.backgroundColor = [theme.separatorColor colorWithAlphaComponent:0.5];
    self.selectedBackgroundView = selected;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    self.iconBG.frame = CGRectMake(16, 14, 38, 38);
    self.iconView.frame = CGRectMake(10, 10, 18, 18);
    self.nameLabel.frame = CGRectMake(66, 15, width - 66 - 64, 20);
    self.detailLabel.frame = CGRectMake(66, 36, width - 66 - 64, 16);
    self.badgeLabel.frame = CGRectMake(width - 58, 22, 40, 20);
    self.chevronView.frame = CGRectMake(width - 28, 25, 13, 13);
}

@end

@interface CloudViewController ()
@property (nonatomic, strong) NSArray *files;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, strong) UIView *emptyView;
@end

@implementation CloudViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"云端书籍";
    self.tableView.rowHeight = 66;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 66, 0, 16);
    self.tableView.tableFooterView = [[UIView alloc] init];
    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = [[YLTheme shared] accentColor];
    [self.refreshControl addTarget:self action:@selector(reload)
                  forControlEvents:UIControlEventValueChanged];
    [self buildEmptyView];
    [[YLTheme shared] applyToViewController:self];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = YES;
    [[YLTheme shared] applyToViewController:self];
    self.tableView.backgroundColor = [[YLTheme shared] appBackground];
    self.tableView.backgroundView = self.files.count ? nil : self.emptyView;
}

- (void)buildEmptyView {
    YLTheme *theme = [YLTheme shared];
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 300)];

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 60, view.bounds.size.width, 48)];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    icon.image = [YLComponents iconNamed:@"cloud" size:48 color:theme.tertiaryTextColor];
    icon.tag = 1;
    [view addSubview:icon];

    UILabel *title = [YLComponents labelWithFont:[theme uiFontOfSize:15 weight:UIFontWeightMedium]
                                           color:theme.secondaryTextColor];
    title.text = @"云端还没有书籍";
    title.textAlignment = NSTextAlignmentCenter;
    title.tag = 2;
    title.frame = CGRectMake(16, 120, view.bounds.size.width - 32, 22);
    [view addSubview:title];

    UILabel *hint = [YLComponents labelWithFont:[theme uiFontOfSize:12 weight:UIFontWeightRegular]
                                          color:theme.tertiaryTextColor];
    hint.text = @"把 txt / epub / zip 放到 WebDAV 后下拉刷新";
    hint.textAlignment = NSTextAlignmentCenter;
    hint.tag = 3;
    hint.frame = CGRectMake(16, 146, view.bounds.size.width - 32, 18);
    [view addSubview:hint];

    self.emptyView = view;
}

- (void)applyEmptyTheme {
    YLTheme *theme = [YLTheme shared];
    ((UIImageView *)[self.emptyView viewWithTag:1]).image =
        [YLComponents iconNamed:@"cloud" size:48 color:theme.tertiaryTextColor];
    ((UILabel *)[self.emptyView viewWithTag:2]).textColor = theme.secondaryTextColor;
    ((UILabel *)[self.emptyView viewWithTag:3]).textColor = theme.tertiaryTextColor;
}

- (void)reload {
    __weak CloudViewController *weakSelf = self;
    [[API shared] get:@"/api/cloud/books" query:nil completion:^(id result, NSError *error) {
        CloudViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        [strongSelf.refreshControl endRefreshing];
        if (error) {
            [strongSelf showMessage:error.localizedDescription];
            return;
        }
        NSDictionary *payload = [result isKindOfClass:[NSDictionary class]] ? result : nil;
        strongSelf.files = [payload[@"books"] isKindOfClass:[NSArray class]]
            ? payload[@"books"] : @[];
        [strongSelf applyEmptyTheme];
        strongSelf.tableView.backgroundView = strongSelf.files.count ? nil : strongSelf.emptyView;
        [strongSelf.tableView reloadData];
    }];
}

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.files.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"CloudCell";
    YLCloudCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[YLCloudCell alloc] initWithStyle:UITableViewCellStyleDefault
                                  reuseIdentifier:identifier];
    }
    YLTheme *theme = [YLTheme shared];
    [cell applyTheme];

    NSDictionary *file = self.files[indexPath.row];
    NSString *name = file[@"name"] ?: @"";
    BOOL isZip = [name.lowercaseString hasSuffix:@".zip"];
    cell.nameLabel.text = name;
    cell.iconView.image = [YLComponents iconNamed:(isZip ? @"folder" : @"book")
                                             size:18
                                            color:theme.accentColor];

    NSString *folder = file[@"folder"];
    NSString *place = ([folder isKindOfClass:[NSString class]] && folder.length)
        ? folder : @"根目录";
    double size = [file[@"size"] doubleValue];
    NSString *sizeText = size >= 1048576
        ? [NSString stringWithFormat:@"%.1f MB", size / 1048576.0]
        : [NSString stringWithFormat:@"%.0f KB", size / 1024.0];
    cell.detailLabel.text = [NSString stringWithFormat:@"%@ · %@", place, sizeText];

    if (isZip) {
        cell.badgeLabel.hidden = NO;
        cell.chevronView.hidden = YES;
        cell.badgeLabel.text = @"备份";
    } else {
        cell.badgeLabel.hidden = YES;
        cell.chevronView.hidden = NO;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.busy) { return; }

    NSDictionary *file = self.files[indexPath.row];
    NSString *name = file[@"name"] ?: @"";
    NSString *path = file[@"path"] ?: name;
    BOOL isZip = [name.lowercaseString hasSuffix:@".zip"];
    NSString *endpoint = isZip ? @"/api/cloud/import" : @"/api/cloud/fetch";
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithDictionary:@{@"path": path}];
    if ([file[@"root"] boolValue]) { body[@"root"] = @YES; }
    NSString *cover = file[@"cover"];
    if (!isZip && [cover isKindOfClass:[NSString class]] && cover.length) {
        body[@"cover"] = cover;
    }

    YLCloudCell *cell = (YLCloudCell *)[tableView cellForRowAtIndexPath:indexPath];
    self.busy = YES;
    cell.chevronView.hidden = YES;
    cell.badgeLabel.hidden = YES;
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:([[YLTheme shared] nightMode]
            ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray)];
    spinner.frame = CGRectMake(cell.contentView.bounds.size.width - 40, 23, 20, 20);
    [spinner startAnimating];
    [cell.contentView addSubview:spinner];

    __weak CloudViewController *weakSelf = self;
    [[API shared] post:endpoint body:body completion:^(id result, NSError *error) {
        CloudViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        strongSelf.busy = NO;
        [spinner removeFromSuperview];
        [strongSelf.tableView reloadData];
        if (error) {
            [strongSelf showMessage:[NSString stringWithFormat:@"下载失败：%@",
                                     error.localizedDescription]];
            return;
        }
        NSDictionary *payload = [result isKindOfClass:[NSDictionary class]] ? result : nil;
        if (isZip) {
            [strongSelf showMessage:[NSString stringWithFormat:
                @"备份导入完成：%@ 本，%@ 条进度",
                payload[@"books"] ?: @0, payload[@"progress"] ?: @0]];
        } else {
            NSString *bookName = payload[@"book"][@"name"];
            [strongSelf showMessage:[NSString stringWithFormat:
                @"已下载到书架：%@", bookName.length ? bookName : name]];
        }
    }];
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
