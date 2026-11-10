#import <UIKit/UIKit.h>

@interface TocViewController : UITableViewController

/** 选择章节后回调（阅读页用它原地切章）。不设置时按旧逻辑打开阅读页。 */
@property (nonatomic, copy) void (^selectBlock)(NSInteger index, NSArray *chapters, NSDictionary *book);

/** 阅读页传入的当前章节，用于高亮。 */
@property (nonatomic, assign) NSInteger selectedIndex;

- (instancetype)initWithBook:(NSDictionary *)book;
- (instancetype)initWithBook:(NSDictionary *)book chapters:(NSArray *)chapters;

@end
