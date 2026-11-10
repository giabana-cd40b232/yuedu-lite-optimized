#import "YLStore.h"

static NSString *const kYLStoreRootKey = @"yl.store.root";

static NSString *YLStoreDocuments(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                        NSUserDomainMask, YES);
    return paths.firstObject ?: NSTemporaryDirectory();
}

static NSString *YLStoreTrim(NSString *text) {
    return [(text ?: @"") stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@interface YLStore ()
- (BOOL)ensureAtPath:(NSString *)root error:(NSString **)error;
- (void)migrateFrom:(NSString *)oldRoot to:(NSString *)newRoot;
@end

@implementation YLStore

+ (instancetype)shared {
    static YLStore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[YLStore alloc] init];
    });
    return instance;
}

- (NSString *)defaultRootPath {
    return [YLStoreDocuments() stringByAppendingPathComponent:@"yuedu"];
}

- (NSString *)normalizePath:(NSString *)path {
    NSString *text = YLStoreTrim(path);
    if (!text.length) { return nil; }
    if ([text isEqualToString:@"~"]) {
        text = NSHomeDirectory();
    } else if ([text hasPrefix:@"~/"]) {
        text = [NSHomeDirectory() stringByAppendingPathComponent:
            [text substringFromIndex:2]];
    }
    if (![text isAbsolutePath]) {
        text = [YLStoreDocuments() stringByAppendingPathComponent:text];
    }
    return [text stringByStandardizingPath];
}

- (NSString *)rootPath {
    NSString *stored = [[NSUserDefaults standardUserDefaults]
        stringForKey:kYLStoreRootKey];
    NSString *path = [self normalizePath:stored];
    return path.length ? path : self.defaultRootPath;
}

- (NSString *)booksPath {
    return [self.rootPath stringByAppendingPathComponent:@"books"];
}

- (NSString *)fontsPath {
    return [self.rootPath stringByAppendingPathComponent:@"fonts"];
}

- (NSString *)inboxPath {
    return [self.rootPath stringByAppendingPathComponent:@"inbox"];
}

- (NSString *)coversPath {
    return [self.rootPath stringByAppendingPathComponent:@"covers"];
}

#pragma mark - 目录准备

- (BOOL)ensureAtPath:(NSString *)root error:(NSString **)error {
    if (!root.length) {
        if (error) { *error = @"目录不能为空"; }
        return NO;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if ([manager fileExistsAtPath:root isDirectory:&isDir] && !isDir) {
        if (error) { *error = @"这个路径是一个文件，不是目录"; }
        return NO;
    }
    NSError *createError = nil;
    if (![manager createDirectoryAtPath:root
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:&createError]) {
        if (error) { *error = createError.localizedDescription ?: @"无法创建目录"; }
        return NO;
    }
    NSArray *subdirs = @[@"books", @"fonts", @"inbox", @"covers"];
    for (NSString *name in subdirs) {
        NSString *path = [root stringByAppendingPathComponent:name];
        if (![manager createDirectoryAtPath:path
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&createError]) {
            if (error) {
                *error = createError.localizedDescription ?: @"无法创建子目录";
            }
            return NO;
        }
    }

    // 真正写一次文件，避免选到只读的挂载点
    NSString *probe = [root stringByAppendingPathComponent:@".yl_write_test"];
    NSData *probeData = [@"ok" dataUsingEncoding:NSUTF8StringEncoding];
    if (![probeData writeToFile:probe atomically:YES]) {
        if (error) { *error = @"这个目录不可写"; }
        return NO;
    }
    [manager removeItemAtPath:probe error:NULL];
    return YES;
}

- (BOOL)prepare {
    NSString *root = self.rootPath;
    if ([self ensureAtPath:root error:NULL]) { return YES; }

    NSString *fallback = self.defaultRootPath;
    if ([root isEqualToString:fallback]) { return NO; }
    if (![self ensureAtPath:fallback error:NULL]) { return NO; }
    [[NSUserDefaults standardUserDefaults] setObject:fallback forKey:kYLStoreRootKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    return YES;
}

#pragma mark - 迁移

- (void)migrateFrom:(NSString *)oldRoot to:(NSString *)newRoot {
    if (!oldRoot.length || !newRoot.length ||
        [oldRoot isEqualToString:newRoot]) {
        return;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *subdirs = @[@"books", @"fonts", @"inbox", @"covers"];
    for (NSString *name in subdirs) {
        NSString *source = [oldRoot stringByAppendingPathComponent:name];
        NSString *target = [newRoot stringByAppendingPathComponent:name];
        NSArray *items = [manager contentsOfDirectoryAtPath:source error:NULL];
        if (!items.count) { continue; }
        [manager createDirectoryAtPath:target
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:NULL];
        for (NSString *item in items) {
            NSString *from = [source stringByAppendingPathComponent:item];
            NSString *to = [target stringByAppendingPathComponent:item];
            if ([from isEqualToString:to]) { continue; }
            [manager removeItemAtPath:to error:NULL];
            NSError *moveError = nil;
            if ([manager moveItemAtPath:from toPath:to error:&moveError]) {
                continue;
            }
            // 跨卷时 move 会失败，改成复制后删除
            if ([manager copyItemAtPath:from toPath:to error:NULL]) {
                [manager removeItemAtPath:from error:NULL];
            }
        }
        // 旧目录空了就一起删掉，避免留下空壳
        NSArray *left = [manager contentsOfDirectoryAtPath:source error:NULL];
        if (!left.count) {
            [manager removeItemAtPath:source error:NULL];
        }
    }
}

- (BOOL)setRootPath:(NSString *)path error:(NSString **)error {
    NSString *target = [self normalizePath:path];
    if (!target.length) {
        if (error) { *error = @"目录不能为空"; }
        return NO;
    }
    NSString *previous = self.rootPath;

    // 不允许把新目录设到旧的 books/fonts/inbox 里面，否则迁移会自己搬自己
    NSArray *protected = @[
        [previous stringByAppendingPathComponent:@"books"],
        [previous stringByAppendingPathComponent:@"fonts"],
        [previous stringByAppendingPathComponent:@"inbox"],
        [previous stringByAppendingPathComponent:@"covers"]
    ];
    for (NSString *item in protected) {
        if ([target isEqualToString:item] ||
            [target hasPrefix:[item stringByAppendingString:@"/"]]) {
            if (error) { *error = @"不能选择书籍/字体/收件箱目录本身或其子目录"; }
            return NO;
        }
    }

    if (![self ensureAtPath:target error:error]) { return NO; }
    if (![previous isEqualToString:target]) {
        [self migrateFrom:previous to:target];
        [[NSUserDefaults standardUserDefaults] setObject:target
                                                  forKey:kYLStoreRootKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    return YES;
}

@end
