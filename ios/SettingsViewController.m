#import "SettingsViewController.h"
#import "API.h"
#import "YLComponents.h"
#import "YLFontManager.h"
#import "YLStore.h"
#import "YLTheme.h"
#import "YLUpdateUI.h"
#import <math.h>

@interface SettingsViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) NSDictionary *settings;
@property (nonatomic, strong) NSMutableDictionary *webdav;
@property (nonatomic, assign) BOOL autoPush;
@property (nonatomic, assign) BOOL webdavExpanded;
@property (nonatomic, assign) CGFloat headerWidth;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
    self.tableView.rowHeight = 50;
    self.tableView.tableFooterView = [[UIView alloc] init];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 58, 0, 16);
    self.tableView.estimatedRowHeight = 0;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"保存"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(saveAndClose)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(close)];

    self.webdav = [NSMutableDictionary dictionary];
    self.autoPush = YES;
    [[YLTheme shared] applyToViewController:self];
    [self buildTableHeader];
    [self loadSettings];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[YLTheme shared] applyToViewController:self];
    [self applyTheme];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (fabs(self.tableView.bounds.size.width - self.headerWidth) > 1.0) {
        [self buildTableHeader];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self persistSilently];
}

#pragma mark - 数据

- (void)loadSettings {
    __weak SettingsViewController *weakSelf = self;
    [[API shared] get:@"/api/settings" query:nil completion:^(id result, NSError *error) {
        SettingsViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        if (error) {
            [strongSelf showMessage:error.localizedDescription];
            return;
        }
        strongSelf.settings = [result isKindOfClass:[NSDictionary class]] ? result : @{};
        id webdav = strongSelf.settings[@"webdav"];
        strongSelf.webdav = [NSMutableDictionary dictionaryWithDictionary:
            [webdav isKindOfClass:[NSDictionary class]] ? webdav : @{}];
        strongSelf.autoPush = [strongSelf.settings[@"autoPush"] boolValue];
        [strongSelf.tableView reloadData];
    }];
}

- (void)persistSilently {
    NSDictionary *body = @{
        @"autoPush": @(self.autoPush),
        @"webdav": self.webdav ?: @{}
    };
    [[API shared] post:@"/api/settings" body:body completion:^(id result, NSError *error) {
        if (error) {
            NSLog(@"[settings] 保存失败: %@", error.localizedDescription);
        }
    }];
}

- (void)saveAndClose {
    NSDictionary *body = @{
        @"autoPush": @(self.autoPush),
        @"webdav": self.webdav ?: @{}
    };
    __weak SettingsViewController *weakSelf = self;
    [[API shared] post:@"/api/settings" body:body completion:^(id result, NSError *error) {
        SettingsViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        if (error) {
            [strongSelf showMessage:error.localizedDescription];
            return;
        }
        [strongSelf close];
    }];
}

- (void)close {
    if (self.navigationController.presentingViewController) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

#pragma mark - 主题

- (void)applyTheme {
    YLTheme *theme = [YLTheme shared];
    self.view.backgroundColor = theme.appBackground;
    self.tableView.backgroundColor = theme.appBackground;
    self.tableView.separatorColor = theme.separatorColor;
    self.tableView.indicatorStyle = theme.nightMode
        ? UIScrollViewIndicatorStyleWhite : UIScrollViewIndicatorStyleDefault;
    [self buildTableHeader];
    [self.tableView reloadData];
}

#pragma mark - 应用信息头部

- (void)buildTableHeader {
    YLTheme *theme = [YLTheme shared];
    CGFloat width = self.tableView.bounds.size.width;
    if (width < 1) { width = self.view.bounds.size.width; }
    if (width < 1) { width = 320; }
    self.headerWidth = width;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 108)];
    header.backgroundColor = [UIColor clearColor];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 14, width - 32, 80)];
    [theme applyCardStyle:card];
    [header addSubview:card];

    UIView *iconBG = [[UIView alloc] initWithFrame:CGRectMake(14, 18, 44, 44)];
    iconBG.backgroundColor = theme.accentSoftColor;
    iconBG.layer.cornerRadius = 12;
    [card addSubview:iconBG];

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(12, 12, 20, 20)];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.image = [YLComponents iconNamed:@"book" size:20 color:theme.accentColor];
    [iconBG addSubview:icon];

    NSBundle *bundle = [NSBundle mainBundle];
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"";

    UILabel *name = [YLComponents labelWithFont:[theme uiFontOfSize:17 weight:UIFontWeightSemibold]
                                          color:theme.barTextColor];
    name.text = @"阅读 Lite";
    name.frame = CGRectMake(72, 18, card.bounds.size.width - 86, 22);
    [card addSubview:name];

    UILabel *detail = [YLComponents labelWithFont:[theme uiFontOfSize:12 weight:UIFontWeightRegular]
                                            color:theme.tertiaryTextColor];
    detail.text = [NSString stringWithFormat:@"版本 %@ (build %@)", version, build];
    detail.frame = CGRectMake(72, 41, card.bounds.size.width - 86, 16);
    [card addSubview:detail];

    UILabel *hint = [YLComponents labelWithFont:[theme uiFontOfSize:11 weight:UIFontWeightRegular]
                                          color:theme.secondaryTextColor];
    hint.text = @"本地阅读 · WebDAV 进度同步";
    hint.frame = CGRectMake(72, 58, card.bounds.size.width - 86, 14);
    [card addSubview:hint];

    self.tableView.tableHeaderView = header;
}

#pragma mark - 表格结构

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 6;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) { return self.webdavExpanded ? 5 : 1; } // 折叠时只显示摘要
    if (section == 1) { return 3; } // 夜间模式 + 书架风格 + 阅读方向
    if (section == 2) { return 1; }
    if (section == 3) { return 3; } // 路径、导入字体、扫描字体
    if (section == 4) { return 4; } // 测试、上传、拉取、清空缓存
    return 5; // 应用：缓存、文件、检查更新、自动检查、关于
}

- (NSString *)sectionTitle:(NSInteger)section {
    if (section == 0) { return @"WebDAV"; }
    if (section == 1) { return @"外观"; }
    if (section == 2) { return @"同步"; }
    if (section == 3) { return @"字体与存储"; }
    if (section == 4) { return @"工具"; }
    return @"应用";
}

- (NSString *)footerTextForSection:(NSInteger)section {
    if (section == 0 && self.webdavExpanded) {
        return @"坚果云请使用“应用密码”。地址填 WebDAV 根地址，远程目录默认 legado，与安卓版“阅读”一致：书在 books/，进度在 bookProgress/。";
    }
    if (section == 1) {
        return @"阅读页的字号、字体、行距、背景和翻页方式，在阅读时点右下角“Aa”调整。书架风格在“设置”里统一切换。";
    }
    if (section == 2) {
        return @"保存进度后只上传当前书，并先比对云端；云端更靠前时不会覆盖。与安卓版共用 legado/bookProgress/。";
    }
    if (section == 3) {
        return [NSString stringWithFormat:
            @"书籍目录：%@\n字体目录：%@\n导入字体支持 TTF / OTF。",
            [YLStore shared].booksPath, [YLStore shared].fontsPath];
    }
    if (section == 5) {
        return @"更新会从 Gitee / GitHub 下载最新 IPA 并直接覆盖安装。覆盖安装会保留书籍、阅读进度和全部设置，无需重新导入。需要已安装 AppSync Unified。";
    }
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    YLTheme *theme = [YLTheme shared];
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 34)];
    view.backgroundColor = [UIColor clearColor];
    UILabel *label = [YLComponents labelWithFont:[theme uiFontOfSize:12 weight:UIFontWeightSemibold]
                                           color:theme.secondaryTextColor];
    label.text = [[self sectionTitle:section] uppercaseString];
    label.frame = CGRectMake(20, 14, view.bounds.size.width - 40, 18);
    [view addSubview:label];
    return view;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? 42 : 34;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self footerTextForSection:section];
    if (!text.length) { return nil; }
    YLTheme *theme = [YLTheme shared];
    CGFloat width = tableView.bounds.size.width - 40;
    CGFloat height = [self footerHeightForSection:section width:width];
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, height)];
    view.backgroundColor = [UIColor clearColor];
    UILabel *label = [YLComponents labelWithFont:[theme uiFontOfSize:11.5 weight:UIFontWeightRegular]
                                           color:theme.tertiaryTextColor];
    label.text = text;
    label.numberOfLines = 0;
    label.frame = CGRectMake(20, 3, width, height - 8);
    [view addSubview:label];
    return view;
}

- (CGFloat)footerHeightForSection:(NSInteger)section width:(CGFloat)width {
    NSString *text = [self footerTextForSection:section];
    if (!text.length) { return 8; }
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineSpacing = 2;
    CGRect rect = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                     options:NSStringDrawingUsesLineFragmentOrigin
                                  attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:11.5],
                                               NSParagraphStyleAttributeName:ps}
                                     context:nil];
    return MAX(20, ceil(rect.size.height) + 14);
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return [self footerHeightForSection:section width:tableView.bounds.size.width - 40];
}

#pragma mark - 图标

// 把矢量图标绘制进一个浅色圆角方块，作为列表行的“图标胶囊”。
- (UIImage *)chipIconNamed:(NSString *)name color:(UIColor *)color {
    CGFloat size = 28;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) { return nil; }
    UIBezierPath *background = [UIBezierPath bezierPathWithRoundedRect:
        CGRectMake(0, 0, size, size) cornerRadius:8];
    [[color colorWithAlphaComponent:0.12] setFill];
    [background fill];

    UIImage *glyph = [[YLComponents iconNamed:name size:16 color:color]
        imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [glyph drawInRect:CGRectMake(6, 6, 16, 16)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (UIColor *)destructiveColor {
    return [YLTheme shared].nightMode
        ? [UIColor colorWithRed:0.976 green:0.443 blue:0.459 alpha:1.0]
        : [UIColor colorWithRed:0.847 green:0.239 blue:0.267 alpha:1.0];
}

#pragma mark - 单元格

- (UITableViewCell *)cellWithStyle:(UITableViewCellStyle)style {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    YLTheme *theme = [YLTheme shared];
    cell.textLabel.font = [theme uiFontOfSize:15.5 weight:UIFontWeightRegular];
    cell.detailTextLabel.font = [theme uiFontOfSize:13 weight:UIFontWeightRegular];
    cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
    cell.detailTextLabel.minimumScaleFactor = 0.7;
    [theme styleCell:cell];
    cell.tintColor = theme.accentColor;
    return cell;
}

- (UITableViewCell *)cellWithStyle:(UITableViewCellStyle)style
                             title:(NSString *)title
                              icon:(NSString *)icon
                             color:(UIColor *)color
                             value:(NSString *)value {
    UITableViewCell *cell = [self cellWithStyle:style];
    cell.textLabel.text = title;
    cell.textLabel.textColor = [YLTheme shared].barTextColor;
    cell.imageView.image = [self chipIconNamed:icon color:color ?: [YLTheme shared].accentColor];
    if (value.length) { cell.detailTextLabel.text = value; }
    return cell;
}

- (UITableViewCell *)switchCellWithTitle:(NSString *)title
                                    icon:(NSString *)icon
                                   color:(UIColor *)color
                                      on:(BOOL)on
                                  action:(SEL)action {
    UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleDefault
                                          title:title
                                           icon:icon
                                          color:color
                                          value:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = on;
    toggle.onTintColor = [YLTheme shared].accentColor;
    [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    YLTheme *theme = [YLTheme shared];
    UIColor *accent = theme.accentColor;

    if (indexPath.section == 0) {
        if (!self.webdavExpanded) {
            NSString *url = self.webdav[@"url"];
            BOOL configured = [url isKindOfClass:[NSString class]] && url.length > 0;
            UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleValue1
                                                   title:@"WebDAV 设置"
                                                    icon:@"cloud"
                                                   color:accent
                                                   value:(configured ? @"已配置 · 点按展开"
                                                                     : @"未配置 · 点按展开")];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        if (indexPath.row == 4) {
            UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleDefault
                                                   title:@"收起"
                                                    icon:@"chevron"
                                                   color:theme.secondaryTextColor
                                                   value:nil];
            cell.textLabel.textColor = theme.secondaryTextColor;
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.imageView.image = nil;
            return cell;
        }
        NSArray *keys = @[@"url", @"username", @"password", @"dir"];
        NSArray *titles = @[@"地址", @"用户名", @"密码", @"远程目录"];
        NSArray *icons = @[@"link", @"person", @"lock", @"folder"];
        UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleValue1];
        NSString *key = keys[indexPath.row];
        cell.textLabel.text = titles[indexPath.row];
        cell.imageView.image = [self chipIconNamed:icons[indexPath.row] color:accent];
        id value = self.webdav[key];
        NSString *text = [value isKindOfClass:[NSString class]] ? value : @"";
        if ([key isEqualToString:@"password"]) {
            text = text.length ? @"••••••" : @"未设置";
        } else if (!text.length) {
            if ([key isEqualToString:@"url"]) { text = @"未配置"; }
            else if ([key isEqualToString:@"dir"]) { text = @"legado（与安卓一致）"; }
        }
        cell.detailTextLabel.text = text;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            return [self switchCellWithTitle:@"夜间模式"
                                        icon:@"moon"
                                       color:theme.nightMode ? theme.accentColor
                                                             : theme.secondaryTextColor
                                          on:theme.nightMode
                                      action:@selector(nightModeChanged:)];
        }
        if (indexPath.row == 1) {
            UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleValue1
                                                   title:@"书架风格"
                                                    icon:@"grid"
                                                   color:accent
                                                   value:[self shelfStyleName]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        NSArray *names = @[@"自动", @"竖屏锁定", @"横屏锁定"];
        NSInteger o = theme.readerOrientation;
        if (o < 0 || o > 2) { o = 0; }
        UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleValue1
                                               title:@"阅读方向"
                                                icon:@"phone"
                                               color:accent
                                               value:names[o]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (indexPath.section == 2) {
        return [self switchCellWithTitle:@"自动上传进度"
                                    icon:@"upload"
                                   color:accent
                                      on:self.autoPush
                                  action:@selector(autoPushChanged:)];
    }

    if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleValue1
                                                   title:@"本地保存路径"
                                                    icon:@"folder"
                                                   color:accent
                                                   value:[YLStore shared].rootPath];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        if (indexPath.row == 1) {
            NSInteger count = (NSInteger)[[YLFontManager shared] fonts].count;
            UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleValue1
                                                   title:@"导入字体（TTF / OTF）"
                                                    icon:@"text"
                                                   color:accent
                                                   value:[NSString stringWithFormat:@"%ld 个", (long)count]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleDefault
                                               title:@"扫描收件箱字体"
                                                icon:@"search"
                                               color:accent
                                               value:nil];
        cell.textLabel.textColor = accent;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (indexPath.section == 4) {
        NSArray *titles2 = @[@"测试 WebDAV 连接", @"立即上传进度", @"立即拉取进度", @"清空章节缓存"];
        NSArray *icons = @[@"cloud", @"upload", @"download", @"trash"];
        UIColor *color = (indexPath.row == 3) ? [self destructiveColor] : accent;
        UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleDefault
                                               title:titles2[indexPath.row]
                                                icon:icons[indexPath.row]
                                               color:color
                                               value:nil];
        cell.textLabel.textColor = accent;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    // section 5: 应用
    NSArray *appTitles = @[@"缓存管理", @"文件管理（Filza）", @"检查更新", @"自动检查更新", @"关于软件"];
    NSArray *appIcons = @[@"refresh", @"folder", @"download", @"clock", @"info"];
    if (indexPath.row == 3) {
        return [self switchCellWithTitle:appTitles[indexPath.row]
                                    icon:appIcons[indexPath.row]
                                   color:accent
                                      on:[YLUpdateUI autoCheckEnabled]
                                  action:@selector(autoCheckChanged:)];
    }
    UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleDefault
                                           title:appTitles[indexPath.row]
                                            icon:appIcons[indexPath.row]
                                           color:accent
                                           value:(indexPath.row == 2 ? [YLUpdateUI currentVersionText] : nil)];
    cell.textLabel.textColor = (indexPath.row == 2) ? accent : theme.barTextColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (!self.webdavExpanded || indexPath.row == 4) {
            self.webdavExpanded = !self.webdavExpanded;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                          withRowAnimation:UITableViewRowAnimationFade];
            return;
        }
        [self editWebdavField:indexPath.row];
        return;
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 1) { [self chooseShelfStyle]; }
        else if (indexPath.row == 2) { [self chooseReadingOrientation]; }
        return;
    }
    if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            [self editStoreRoot];
        } else if (indexPath.row == 1) {
            [self importFontFile];
        } else {
            [self importFontsFromInbox];
        }
        return;
    }
    if (indexPath.section == 4) {
        [self runTool:indexPath.row];
        return;
    }
    if (indexPath.section == 5) {
        if (indexPath.row != 3) { [self runAppTool:indexPath.row]; }
    }
}

#pragma mark - WebDAV 字段

- (void)editWebdavField:(NSInteger)row {
    NSArray *keys = @[@"url", @"username", @"password", @"dir"];
    NSArray *titles = @[@"WebDAV 地址", @"用户名", @"密码", @"远程目录"];
    NSString *key = keys[row];
    BOOL isPassword = [key isEqualToString:@"password"];
    id current = self.webdav[key];
    NSString *value = [current isKindOfClass:[NSString class]] ? current : @"";
    BOOL hasStoredPassword = isPassword && value.length > 0;
    if (isPassword) {
        // 不要把掩码填进输入框，否则用户一改就会变成“******新密码”
        value = @"";
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:titles[row]
                         message:nil
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = value;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        if ([key isEqualToString:@"url"]) {
            textField.keyboardType = UIKeyboardTypeURL;
            textField.placeholder = @"https://dav.example.com/dav/";
        } else if (isPassword) {
            textField.secureTextEntry = YES;
            textField.placeholder = hasStoredPassword ? @"已保存，留空表示不修改" : @"应用密码";
        } else if ([key isEqualToString:@"dir"]) {
            textField.placeholder = @"留空 = legado（与安卓版一致）";
            if (!value.length) { textField.text = @"legado"; }
        }
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    __weak SettingsViewController *weakSelf = self;
    if (hasStoredPassword) {
        [alert addAction:[UIAlertAction actionWithTitle:@"清空密码"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            SettingsViewController *strongSelf = weakSelf;
            if (!strongSelf) { return; }
            strongSelf.webdav[@"password"] = @"";
            [strongSelf persistSilently];
            [strongSelf.tableView reloadData];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        SettingsViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        NSString *text = alert.textFields.firstObject.text ?: @"";
        text = [text stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (isPassword && !text.length && hasStoredPassword) {
            return; // 留空 = 保持原密码
        }
        strongSelf.webdav[key] = text;
        [strongSelf persistSilently];
        [strongSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 存储目录与字体

- (void)editStoreRoot {
    YLStore *store = [YLStore shared];
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"本地保存路径"
                         message:@"书籍、字体和收件箱会保存到这里。可以填绝对路径，也可以填相对 Documents 的路径。修改后会把现有文件移动到新目录。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = store.rootPath;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.placeholder = store.defaultRootPath;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    __weak SettingsViewController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        SettingsViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        NSString *path = alert.textFields.firstObject.text ?: @"";
        path = [path stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!path.length) { return; }
        [[API shared] post:@"/api/store/root"
                      body:@{@"path": path}
                completion:^(id result, NSError *error) {
            SettingsViewController *innerSelf = weakSelf;
            if (!innerSelf) { return; }
            if (error) {
                [innerSelf showMessage:error.localizedDescription];
                return;
            }
            [[YLFontManager shared] reload];
            [innerSelf.tableView reloadData];
            [innerSelf showMessage:[NSString stringWithFormat:@"已切换到：\n%@",
                [YLStore shared].rootPath]];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)importFontFile {
    // iOS 9 越狱设备上 UIDocumentPickerViewController 会直接闪退，
    // 改用收件箱方式：用 Filza / iTunes 文件共享把字体放进收件箱目录，
    // 在这里输入文件名导入（留空则扫描整个收件箱）。
    NSString *inbox = [YLStore shared].inboxPath;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"导入字体（TTF / OTF）"
                         message:[NSString stringWithFormat:
                             @"请先把字体文件放进收件箱目录：\n%@", inbox]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"文件名，如 myfont.ttf（留空扫描全部）";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak SettingsViewController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"导入"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        SettingsViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        NSString *name = [alert.textFields.firstObject.text
            stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length) {
            [strongSelf importFontFromInboxByName:name];
        } else {
            [strongSelf importFontsFromInbox];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)importFontFromInboxByName:(NSString *)name {
    NSString *path = [[YLStore shared].inboxPath stringByAppendingPathComponent:name];
    NSString *reason = nil;
    BOOL ok = [[YLFontManager shared] importFontAtPath:path error:&reason];
    if (ok) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    }
    [self.tableView reloadData];
    [self showMessage:ok
        ? [NSString stringWithFormat:@"字体已导入：%@", name]
        : (reason ?: @"字体导入失败")];
}

- (void)importFontsFromInbox {
    NSArray *imported = nil;
    NSArray *errors = nil;
    NSInteger count = [[YLFontManager shared] importFontsFromInbox:&imported
                                                           errors:&errors];
    NSString *text;
    if (count > 0) {
        text = [NSString stringWithFormat:@"已导入 %ld 个字体", (long)count];
    } else {
        text = @"收件箱里没有新的 TTF / OTF 字体";
    }
    if (errors.count) {
        text = [text stringByAppendingFormat:@"\n失败 %lu 个：%@",
            (unsigned long)errors.count, errors.firstObject];
    }
    [self.tableView reloadData];
    [self showMessage:text];
}

- (void)handlePickedFontURLs:(NSArray *)urls {
    if (!urls.count) { return; }
    NSURL *url = urls.firstObject;
    BOOL accessed = [url startAccessingSecurityScopedResource];
    NSString *tempName = [NSString stringWithFormat:@"font-%@-%@",
        [[NSUUID UUID] UUIDString], url.lastPathComponent ?: @"font.ttf"];
    NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:tempName];
    NSError *copyError = nil;
    BOOL copied = [[NSFileManager defaultManager] copyItemAtPath:url.path
                                                         toPath:temp
                                                          error:&copyError];
    if (accessed) { [url stopAccessingSecurityScopedResource]; }
    if (!copied) {
        [self showMessage:copyError.localizedDescription ?: @"无法读取所选字体"];
        return;
    }
    NSString *reason = nil;
    BOOL ok = [[YLFontManager shared] importFontAtPath:temp error:&reason];
    [[NSFileManager defaultManager] removeItemAtPath:temp error:NULL];
    [self.tableView reloadData];
    if (ok) {
        [self showMessage:[NSString stringWithFormat:@"字体已导入：%@",
            url.lastPathComponent ?: @"字体"]];
    } else {
        [self showMessage:reason ?: @"字体导入失败"];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
 didPickDocumentAtURL:(NSURL *)url {
    [self handlePickedFontURLs:@[url]];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
 didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self handlePickedFontURLs:urls];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
}

- (void)autoPushChanged:(UISwitch *)toggle {
    self.autoPush = toggle.on;
    [self persistSilently];
}

- (void)nightModeChanged:(UISwitch *)toggle {
    YLTheme *theme = [YLTheme shared];
    theme.nightMode = toggle.on;
    // 阅读页跟着一起切夜间，避免“界面黑了、正文还是白底”的割裂感
    if (theme.nightMode && theme.readerTheme != YLReaderThemeNight) {
        theme.readerTheme = YLReaderThemeNight;
    } else if (!theme.nightMode && theme.readerTheme == YLReaderThemeNight) {
        theme.readerTheme = YLReaderThemeWhite;
    }
    [theme save];
    [theme applyAppearance];
    [self applyTheme];
}

#pragma mark - 工具

- (void)runTool:(NSInteger)row {
    if (row == 0) {
        [self persistSilently];
        [self runAction:@"sync.test" message:^(NSDictionary *result) {
            return [NSString stringWithFormat:@"连接成功，目录里有 %@ 个条目",
                    result[@"count"] ?: @0];
        }];
    } else if (row == 1) {
        [self runAction:@"sync.push" message:^(NSDictionary *result) {
            return [NSString stringWithFormat:@"已上传 %@ 条进度", result[@"pushed"] ?: @0];
        }];
    } else if (row == 2) {
        __weak SettingsViewController *weakSelf = self;
        [[API shared] post:@"/api/sync/pull" body:@{} completion:^(id result, NSError *error) {
            SettingsViewController *strongSelf = weakSelf;
            if (!strongSelf) { return; }
            if (error) {
                [strongSelf showMessage:error.localizedDescription];
                return;
            }
            [strongSelf showMessage:[NSString stringWithFormat:@"已拉取 %@ 条，合并后共 %@ 条",
                result[@"pulled"] ?: @0, result[@"total"] ?: @0]];
            [strongSelf loadSettings];
        }];
    } else {
        [self confirmClearCache];
    }
}

- (void)runAppTool:(NSInteger)row {
    if (row == 0) {
        [self showCacheManager];
    } else if (row == 1) {
        [self openInFileManager];
    } else if (row == 2) {
        [self openGitHubReleases];
    } else if (row == 4) {
        [self showAbout];
    }
}

- (void)autoCheckChanged:(UISwitch *)sender {
    [YLUpdateUI setAutoCheckEnabled:sender.isOn];
}

#pragma mark - 书架风格

- (NSString *)shelfStyleName {
    NSInteger mode = [[NSUserDefaults standardUserDefaults]
        integerForKey:@"yl.bookshelf.mode"];
    return mode == 1 ? @"大图标" : @"列表";
}

- (void)chooseShelfStyle {
    NSArray *names = @[@"列表", @"大图标"];
    NSInteger current = [[NSUserDefaults standardUserDefaults]
        integerForKey:@"yl.bookshelf.mode"];
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:@"书架风格"
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < (NSInteger)names.count; i += 1) {
        NSString *title = names[i];
        if (i == current) { title = [title stringByAppendingString:@"  ✓"]; }
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [[NSUserDefaults standardUserDefaults] setInteger:i
                                                       forKey:@"yl.bookshelf.mode"];
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)chooseReadingOrientation {
    NSArray *names = @[@"自动", @"竖屏锁定", @"横屏锁定"];
    NSInteger current = [YLTheme shared].readerOrientation;
    if (current < 0 || current > 2) { current = 0; }
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:@"阅读方向"
                         message:@"控制阅读界面的屏幕方向"
                  preferredStyle:UIAlertControllerStyleActionSheet];
    __weak SettingsViewController *weakSelf = self;
    for (NSInteger i = 0; i < (NSInteger)names.count; i += 1) {
        NSString *title = names[i];
        if (i == current) { title = [title stringByAppendingString:@"  ✓"]; }
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [YLTheme shared].readerOrientation = i;
            [[YLTheme shared] save];
            [weakSelf.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 缓存管理

- (void)showCacheManager {
    __weak SettingsViewController *weakSelf = self;
    [[API shared] post:@"/api/cache/info" body:@{} completion:^(id result, NSError *error) {
        SettingsViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        if (error) {
            [strongSelf showMessage:error.localizedDescription];
            return;
        }
        NSDictionary *payload = [result isKindOfClass:[NSDictionary class]] ? result : @{};
        double mega = [payload[@"bytes"] doubleValue] / 1048576.0;
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"缓存管理"
                             message:[NSString stringWithFormat:
                                 @"章节缓存约 %.1f MB\n只缓存目录和正文，不影响书架与进度。", mega]
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"清空缓存"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            [[API shared] post:@"/api/cache/clear" body:@{} completion:nil];
        }]];
        [strongSelf presentViewController:alert animated:YES completion:nil];
    }];
}

#pragma mark - 文件管理 / GitHub / 关于

// 用 Filza 直接打开书籍存储目录，方便管理本地书、字体文件
- (void)openInFileManager {
    NSString *path = [YLStore shared].rootPath;
    NSString *encoded = [path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    // Filza 不同版本注册的 scheme 不一样，逐个尝试
    NSArray *schemes = @[
        [NSString stringWithFormat:@"filza://view%@", encoded],
        [NSString stringWithFormat:@"filza://%@", encoded],
        [NSString stringWithFormat:@"ifile://%@", encoded]
    ];
    BOOL opened = NO;
    for (NSString *scheme in schemes) {
        NSURL *url = [NSURL URLWithString:scheme];
        if (url && [[UIApplication sharedApplication] openURL:url]) {
            opened = YES;
            break;
        }
    }
    if (!opened) {
        [self showMessage:[NSString stringWithFormat:
            @"无法打开 Filza，请手动前往：\n%@", path]];
    }
}

// 应用内更新：查询 Gitee / GitHub 最新 release → 下载 IPA → 本机直接安装。
- (void)openGitHubReleases {
    [YLUpdateUI checkForUpdatesFrom:self silent:NO];
}

- (void)promptInstallRelease:(NSDictionary *)info {
    (void)info;
    // 已迁移到 YLUpdateUI（设置页与启动自动检查共用）。
}

- (void)installRelease:(NSDictionary *)info {
    (void)info;
    // 已迁移到 YLUpdateUI（设置页与启动自动检查共用）。
}

- (BOOL)isVersion:(NSString *)newer newerThan:(NSString *)current {
    NSArray *a = [newer componentsSeparatedByString:@"."];
    NSArray *b = [current componentsSeparatedByString:@"."];
    NSInteger count = MAX((NSInteger)a.count, (NSInteger)b.count);
    for (NSInteger i = 0; i < count; i += 1) {
        NSInteger x = i < (NSInteger)a.count ? [a[i] integerValue] : 0;
        NSInteger y = i < (NSInteger)b.count ? [b[i] integerValue] : 0;
        if (x != y) { return x > y; }
    }
    return NO;
}

- (void)showAbout {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"";
    NSString *minOS = [bundle objectForInfoDictionaryKey:@"MinimumOSVersion"] ?: @"9.0";
    [self showMessage:[NSString stringWithFormat:
        @"阅读 Lite v%@ (build %@)\n最低 iOS %@ · armv7\n\n本地 TXT / EPUB 阅读，WebDAV 与安卓版“阅读”(legado) 互通书籍和进度，全部数据只存在手机内。\n\n开源地址：github.com/Daniel123999/yuedu-lite",
        version, build, minOS]];
}

- (void)runAction:(NSString *)action message:(NSString *(^)(NSDictionary *))message {
    __weak SettingsViewController *weakSelf = self;
    [[API shared] callAction:action params:@{} completion:^(id result, NSError *error) {
        SettingsViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        if (error) {
            [strongSelf showMessage:error.localizedDescription];
            return;
        }
        [strongSelf showMessage:message(result)];
        [strongSelf loadSettings];
    }];
}

- (void)scanInbox {
    __weak SettingsViewController *weakSelf = self;
    [[API shared] post:@"/api/inbox/scan" body:@{} completion:^(id result, NSError *error) {
        SettingsViewController *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        if (error) {
            [strongSelf showMessage:error.localizedDescription];
            return;
        }
        NSArray *errors = result[@"errors"];
        NSString *text = [NSString stringWithFormat:@"导入书籍 %@ 本，进度 %@ 条",
                          result[@"books"] ?: @0, result[@"progress"] ?: @0];
        if ([errors isKindOfClass:[NSArray class]] && errors.count) {
            text = [text stringByAppendingFormat:@"\n失败 %lu 个：%@",
                    (unsigned long)errors.count, errors.firstObject];
        }
        [strongSelf showMessage:text];
        [strongSelf loadSettings];
    }];
}

- (void)confirmClearCache {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"清空章节缓存"
                         message:@"只删除缓存的目录和正文，不影响书架和进度。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    __weak SettingsViewController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"清空"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [[API shared] post:@"/api/cache/clear" body:@{} completion:^(id result, NSError *error) {
            SettingsViewController *strongSelf = weakSelf;
            if (!strongSelf) { return; }
            [strongSelf showMessage:error ? error.localizedDescription : @"缓存已清空"];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 提示

- (void)showMessage:(NSString *)text {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:nil message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
