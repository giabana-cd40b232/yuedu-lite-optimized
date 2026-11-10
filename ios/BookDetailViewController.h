#import <UIKit/UIKit.h>

/**
 * 书籍详情：封面、作者、文件大小、字数、目录、阅读记录、简介。
 * readBlock(book, chapters, index) 用于“开始阅读”或点目录章节进入阅读页。
 */
@interface BookDetailViewController : UITableViewController

- (instancetype)initWithBook:(NSDictionary *)book;

@property (nonatomic, copy) void (^readBlock)(NSDictionary *book,
                                              NSArray *chapters,
                                              NSInteger index);

@end
