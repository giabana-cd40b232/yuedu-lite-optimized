#import "YLFontManager.h"
#import "YLStore.h"
#import <CoreText/CoreText.h>

static NSString *YLFontExtension(NSString *path) {
    return [[path pathExtension] lowercaseString];
}

static BOOL YLFontSupported(NSString *path) {
    NSString *ext = YLFontExtension(path);
    return [ext isEqualToString:@"ttf"] || [ext isEqualToString:@"otf"];
}

static NSString *YLFontSafeFileName(NSString *name) {
    NSString *base = [[name lastPathComponent]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!base.length) { base = @"font.ttf"; }
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:
        @"\\/:*?\"<>|"];
    NSArray *parts = [base componentsSeparatedByCharactersInSet:bad];
    return [parts componentsJoinedByString:@"_"];
}

@interface YLFontManager ()
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, strong) NSMutableDictionary *byName;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation YLFontManager

+ (instancetype)shared {
    static YLFontManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[YLFontManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = [NSMutableArray array];
        _byName = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - 注册

- (NSDictionary *)infoForFontAtPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) { return nil; }

    CGDataProviderRef provider = CGDataProviderCreateWithCFData(
        (__bridge CFDataRef)data);
    if (!provider) { return nil; }
    CGFontRef graphicsFont = CGFontCreateWithDataProvider(provider);
    CGDataProviderRelease(provider);
    if (!graphicsFont) { return nil; }

    CTFontRef font = CTFontCreateWithGraphicsFont(graphicsFont, 14.0, NULL, NULL);
    CGFontRelease(graphicsFont);
    if (!font) { return nil; }

    NSString *postScript = CFBridgingRelease(CTFontCopyPostScriptName(font));
    NSString *fullName = CFBridgingRelease(CTFontCopyFullName(font));
    NSString *family = CFBridgingRelease(CTFontCopyFamilyName(font));
    CFRelease(font);

    if (!postScript.length) { return nil; }
    return @{
        @"name": postScript,
        @"display": fullName.length ? fullName : postScript,
        @"file": [path lastPathComponent],
        @"family": family.length ? family : @"",
        @"path": path
    };
}

- (void)registerFontAtPath:(NSString *)path {
    NSURL *url = [NSURL fileURLWithPath:path];
    if (!url) { return; }
    CFErrorRef error = NULL;
    CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url,
                                     kCTFontManagerScopeProcess,
                                     &error);
    if (error) { CFRelease(error); }
}

- (void)reload {
    [self.items removeAllObjects];
    [self.byName removeAllObjects];

    NSString *dir = [YLStore shared].fontsPath;
    NSArray *names = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:dir error:NULL];
    for (NSString *name in names) {
        if (!YLFontSupported(name)) { continue; }
        NSString *path = [dir stringByAppendingPathComponent:name];
        NSDictionary *info = [self infoForFontAtPath:path];
        if (!info) { continue; }
        [self registerFontAtPath:path];
        [self.items addObject:info];
        self.byName[info[@"name"]] = info;
    }
    [self.items sortUsingComparator:^NSComparisonResult(NSDictionary *a,
                                                       NSDictionary *b) {
        return [a[@"display"] localizedCaseInsensitiveCompare:b[@"display"]];
    }];
    self.loaded = YES;
}

- (NSArray *)fonts {
    if (!self.loaded) { [self reload]; }
    return [self.items copy];
}

- (NSString *)displayNameForFont:(NSString *)postScriptName {
    if (!postScriptName.length) { return @""; }
    if (!self.loaded) { [self reload]; }
    NSDictionary *info = self.byName[postScriptName];
    return info[@"display"] ?: postScriptName;
}

#pragma mark - 导入

- (BOOL)importFontAtPath:(NSString *)path error:(NSString **)error {
    NSString *source = [path stringByStandardizingPath];
    if (!YLFontSupported(source)) {
        if (error) { *error = @"只支持 .ttf / .otf 字体文件"; }
        return NO;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:source]) {
        if (error) { *error = @"找不到字体文件"; }
        return NO;
    }
    if (![self infoForFontAtPath:source]) {
        if (error) { *error = @"字体文件无法解析，可能已损坏"; }
        return NO;
    }

    NSString *dir = [YLStore shared].fontsPath;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    NSString *dest = [dir stringByAppendingPathComponent:
        YLFontSafeFileName(source)];

    if ([source isEqualToString:dest]) {
        [self reload];
        return YES;
    }

    // 替换同名文件前先注销，否则 CoreText 会继续使用内存里的旧字体
    if ([[NSFileManager defaultManager] fileExistsAtPath:dest]) {
        CTFontManagerUnregisterFontsForURL(
            (__bridge CFURLRef)[NSURL fileURLWithPath:dest],
            kCTFontManagerScopeProcess, NULL);
        [[NSFileManager defaultManager] removeItemAtPath:dest error:NULL];
    }

    NSError *copyError = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:source
                                                 toPath:dest
                                                  error:&copyError]) {
        if (error) {
            *error = copyError.localizedDescription ?: @"保存字体失败";
        }
        return NO;
    }

    [self reload];
    return YES;
}

- (NSInteger)importFontsFromInbox:(NSArray **)imported errors:(NSArray **)errors {
    NSMutableArray *okList = [NSMutableArray array];
    NSMutableArray *errList = [NSMutableArray array];
    NSString *inbox = [YLStore shared].inboxPath;
    NSArray *names = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:inbox error:NULL];
    for (NSString *name in names) {
        if (!YLFontSupported(name)) { continue; }
        NSString *path = [inbox stringByAppendingPathComponent:name];
        NSString *reason = nil;
        if ([self importFontAtPath:path error:&reason]) {
            [okList addObject:name];
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        } else {
            [errList addObject:[NSString stringWithFormat:@"%@: %@",
                name, reason ?: @"导入失败"]];
        }
    }
    if (imported) { *imported = [okList copy]; }
    if (errors) { *errors = [errList copy]; }
    return (NSInteger)okList.count;
}

@end
