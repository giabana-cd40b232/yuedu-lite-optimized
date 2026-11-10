#import <Foundation/Foundation.h>

/**
 * 本地书籍 / 字体 / 收件箱的统一存储目录。
 *
 * 默认是 Documents/yuedu，用户可以在“设置 - 字体与存储”里改成其他可写目录。
 * 引擎的 config/shelf/progress 等状态文件仍然固定在 Documents/yuedu，
 * 只有体积较大的书籍、字体和收件箱会跟着保存路径走。
 */
@interface YLStore : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSString *rootPath;
@property (nonatomic, readonly) NSString *booksPath;
@property (nonatomic, readonly) NSString *fontsPath;
@property (nonatomic, readonly) NSString *inboxPath;
@property (nonatomic, readonly) NSString *coversPath;
@property (nonatomic, readonly) NSString *defaultRootPath;

/** 启动时调用：确保目录存在；自定义目录失效时自动回退到默认目录。 */
- (BOOL)prepare;

/**
 * 切换保存目录。会先验证可写，再把旧目录里的书籍/字体/收件箱文件移动过去。
 * 失败时返回 NO 并给出原因，原目录保持不变。
 */
- (BOOL)setRootPath:(NSString *)path error:(NSString **)error;

/** 把用户输入（绝对路径 / 相对 Documents 的路径 / ~）转成标准路径。 */
- (NSString *)normalizePath:(NSString *)path;

@end
