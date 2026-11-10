#import <UIKit/UIKit.h>

/**
 * 一组轻量的现代 UI 组件工厂。
 * 全部使用 UIKit + Core Graphics 实现，不依赖第三方库，
 * 也不使用毛玻璃 / 阴影等开销较大的效果，保证 iPhone 4S 上的流畅度。
 */
@interface YLComponents : NSObject

+ (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color;

+ (UIView *)hairline;
+ (UIView *)cardView;

/** 主按钮：实心强调色 + 圆角。 */
+ (UIButton *)filledButtonWithTitle:(NSString *)title
                             target:(id)target
                             action:(SEL)action;
/** 次按钮：浅色底 + 强调色文字。 */
+ (UIButton *)softButtonWithTitle:(NSString *)title
                           target:(id)target
                           action:(SEL)action;
/** 纯图标按钮（矢量绘制，避免 emoji 风格不统一）。 */
+ (UIButton *)iconButtonWithName:(NSString *)name
                            size:(CGFloat)size
                           color:(UIColor *)color
                          target:(id)target
                          action:(SEL)action;

/** 24×24 逻辑坐标绘制的单色图标。name 见实现里的分支。 */
+ (UIImage *)iconNamed:(NSString *)name
                  size:(CGFloat)size
                 color:(UIColor *)color;

@end
