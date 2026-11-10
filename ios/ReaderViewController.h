#import <UIKit/UIKit.h>

@interface ReaderViewController : UIViewController

- (instancetype)initWithBook:(NSDictionary *)book;
- (instancetype)initWithBook:(NSDictionary *)book
                    chapters:(NSArray *)chapters
                       index:(NSInteger)index;

@end
