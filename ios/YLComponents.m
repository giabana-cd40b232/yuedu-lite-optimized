#import "YLComponents.h"
#import "YLTheme.h"
#import <math.h>

static void YLFillRounded(CGContextRef ctx, CGRect rect, CGFloat radius) {
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect
                                                        cornerRadius:radius];
    [path fill];
}

static void YLStrokeArc(CGContextRef ctx, CGPoint center, CGFloat radius,
                        CGFloat start, CGFloat end) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path addArcWithCenter:center radius:radius startAngle:start endAngle:end clockwise:YES];
    [path stroke];
}

static void YLArrowHead(CGContextRef ctx, CGPoint tip, CGFloat direction, CGFloat length) {
    CGFloat spread = 0.58f;
    CGPoint a = CGPointMake(tip.x - length * cosf(direction - spread),
                            tip.y - length * sinf(direction - spread));
    CGPoint b = CGPointMake(tip.x - length * cosf(direction + spread),
                            tip.y - length * sinf(direction + spread));
    CGContextMoveToPoint(ctx, tip.x, tip.y);
    CGContextAddLineToPoint(ctx, a.x, a.y);
    CGContextAddLineToPoint(ctx, b.x, b.y);
    CGContextClosePath(ctx);
    CGContextFillPath(ctx);
}

@implementation YLComponents

+ (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.font = font;
    label.textColor = color;
    label.backgroundColor = [UIColor clearColor];
    return label;
}

+ (UIView *)hairline {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [[YLTheme shared] separatorColor];
    view.userInteractionEnabled = NO;
    return view;
}

+ (UIView *)cardView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    [[YLTheme shared] applyCardStyle:view];
    return view;
}

+ (UIButton *)filledButtonWithTitle:(NSString *)title
                             target:(id)target
                             action:(SEL)action {
    YLTheme *theme = [YLTheme shared];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [theme uiFontOfSize:15 weight:UIFontWeightSemibold];
    [button setTitleColor:(theme.nightMode ? [UIColor colorWithRed:0.055 green:0.075 blue:0.125 alpha:1]
                                           : [UIColor whiteColor])
                 forState:UIControlStateNormal];
    button.backgroundColor = theme.accentColor;
    button.layer.cornerRadius = 16;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

+ (UIButton *)softButtonWithTitle:(NSString *)title
                           target:(id)target
                           action:(SEL)action {
    YLTheme *theme = [YLTheme shared];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [theme uiFontOfSize:13 weight:UIFontWeightMedium];
    [button setTitleColor:theme.accentColor forState:UIControlStateNormal];
    button.backgroundColor = theme.accentSoftColor;
    button.layer.cornerRadius = 14;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

+ (UIButton *)iconButtonWithName:(NSString *)name
                            size:(CGFloat)size
                           color:(UIColor *)color
                          target:(id)target
                          action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *image = [self iconNamed:name size:size color:color];
    [button setImage:image forState:UIControlStateNormal];
    button.adjustsImageWhenHighlighted = NO;
    button.tintColor = color;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

+ (UIImage *)iconNamed:(NSString *)name
                  size:(CGFloat)size
                 color:(UIColor *)color {
    if (!name.length || size <= 0) { return nil; }
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        UIGraphicsEndImageContext();
        return nil;
    }
    CGContextSaveGState(ctx);
    CGContextScaleCTM(ctx, size / 24.0, size / 24.0);
    CGContextSetStrokeColorWithColor(ctx, color.CGColor);
    CGContextSetFillColorWithColor(ctx, color.CGColor);
    CGContextSetLineWidth(ctx, 1.9);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);

    if ([name isEqualToString:@"book"]) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(3.5, 5.0)];
        [path addCurveToPoint:CGPointMake(12.0, 7.8)
                controlPoint1:CGPointMake(6.5, 3.8)
                controlPoint2:CGPointMake(9.5, 4.8)];
        [path addCurveToPoint:CGPointMake(20.5, 5.0)
                controlPoint1:CGPointMake(14.5, 4.8)
                controlPoint2:CGPointMake(17.5, 3.8)];
        [path addLineToPoint:CGPointMake(20.5, 18.6)];
        [path addCurveToPoint:CGPointMake(12.0, 21.0)
                controlPoint1:CGPointMake(17.5, 17.4)
                controlPoint2:CGPointMake(14.5, 18.4)];
        [path addCurveToPoint:CGPointMake(3.5, 18.6)
                controlPoint1:CGPointMake(9.5, 18.4)
                controlPoint2:CGPointMake(6.5, 17.4)];
        [path closePath];
        [path moveToPoint:CGPointMake(12.0, 7.8)];
        [path addLineToPoint:CGPointMake(12.0, 20.6)];
        [path stroke];
    } else if ([name isEqualToString:@"books"]) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(4.0, 6.5, 4.2, 12.5)
                                                        cornerRadius:1.2]];
        [path appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(9.9, 4.0, 4.2, 15.0)
                                                        cornerRadius:1.2]];
        [path appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(15.8, 7.0, 4.2, 12.0)
                                                        cornerRadius:1.2]];
        [path stroke];
        UIBezierPath *base = [UIBezierPath bezierPath];
        [base moveToPoint:CGPointMake(3.0, 20.4)];
        [base addLineToPoint:CGPointMake(21.0, 20.4)];
        [base stroke];
    } else if ([name isEqualToString:@"cloud"]) {
        CGContextFillEllipseInRect(ctx, CGRectMake(4.0, 9.0, 10.0, 9.5));
        CGContextFillEllipseInRect(ctx, CGRectMake(9.2, 6.0, 9.6, 9.6));
        CGContextFillEllipseInRect(ctx, CGRectMake(13.4, 9.5, 7.8, 8.0));
        CGContextFillRect(ctx, CGRectMake(5.6, 13.2, 14.4, 5.0));
    } else if ([name isEqualToString:@"refresh"]) {
        CGPoint center = CGPointMake(12.0, 12.0);
        CGFloat radius = 6.4;
        YLStrokeArc(ctx, center, radius, M_PI * 0.16, M_PI * 0.84);
        YLStrokeArc(ctx, center, radius, M_PI * 1.16, M_PI * 1.84);
        CGFloat end1 = M_PI * 0.84;
        CGPoint tip1 = CGPointMake(center.x + radius * cosf(end1),
                                   center.y + radius * sinf(end1));
        YLArrowHead(ctx, tip1, atan2f(cosf(end1), -sinf(end1)), 3.4);
        CGFloat end2 = M_PI * 1.84;
        CGPoint tip2 = CGPointMake(center.x + radius * cosf(end2),
                                   center.y + radius * sinf(end2));
        YLArrowHead(ctx, tip2, atan2f(cosf(end2), -sinf(end2)), 3.4);
    } else if ([name isEqualToString:@"settings"]) {
        CGFloat rows[3] = {7.6, 12.0, 16.4};
        CGFloat knobs[3] = {9.0, 15.0, 7.5};
        for (NSInteger i = 0; i < 3; i += 1) {
            CGContextMoveToPoint(ctx, 4.0, rows[i]);
            CGContextAddLineToPoint(ctx, knobs[i] - 3.2, rows[i]);
            CGContextStrokePath(ctx);
            CGContextMoveToPoint(ctx, knobs[i] + 3.2, rows[i]);
            CGContextAddLineToPoint(ctx, 20.0, rows[i]);
            CGContextStrokePath(ctx);
            CGContextFillEllipseInRect(ctx,
                CGRectMake(knobs[i] - 2.5, rows[i] - 2.5, 5.0, 5.0));
        }
    } else if ([name isEqualToString:@"chevron"]) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(9.5, 5.0)];
        [path addLineToPoint:CGPointMake(15.5, 12.0)];
        [path addLineToPoint:CGPointMake(9.5, 19.0)];
        [path stroke];
    } else if ([name isEqualToString:@"back"]) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(14.5, 4.5)];
        [path addLineToPoint:CGPointMake(7.0, 12.0)];
        [path addLineToPoint:CGPointMake(14.5, 19.5)];
        [path stroke];
    } else if ([name isEqualToString:@"check"]) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(4.8, 12.4)];
        [path addLineToPoint:CGPointMake(9.8, 17.4)];
        [path addLineToPoint:CGPointMake(19.2, 6.8)];
        [path stroke];
    } else if ([name isEqualToString:@"list"]) {
        CGFloat rows[3] = {6.5, 12.0, 17.5};
        for (NSInteger i = 0; i < 3; i += 1) {
            CGContextFillEllipseInRect(ctx, CGRectMake(4.0, rows[i] - 1.2, 2.4, 2.4));
            CGContextMoveToPoint(ctx, 9.0, rows[i]);
            CGContextAddLineToPoint(ctx, 20.0, rows[i]);
            CGContextStrokePath(ctx);
        }
    } else if ([name isEqualToString:@"grid"]) {
        YLFillRounded(ctx, CGRectMake(4.0, 4.0, 6.8, 6.8), 1.6);
        YLFillRounded(ctx, CGRectMake(13.2, 4.0, 6.8, 6.8), 1.6);
        YLFillRounded(ctx, CGRectMake(4.0, 13.2, 6.8, 6.8), 1.6);
        YLFillRounded(ctx, CGRectMake(13.2, 13.2, 6.8, 6.8), 1.6);
    } else if ([name isEqualToString:@"search"]) {
        UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:
            CGRectMake(4.0, 4.0, 12.5, 12.5)];
        [circle stroke];
        UIBezierPath *handle = [UIBezierPath bezierPath];
        [handle moveToPoint:CGPointMake(15.4, 15.4)];
        [handle addLineToPoint:CGPointMake(20.2, 20.2)];
        [handle stroke];
    } else if ([name isEqualToString:@"bookmark"]) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(6.2, 3.4)];
        [path addLineToPoint:CGPointMake(17.8, 3.4)];
        [path addLineToPoint:CGPointMake(17.8, 21.0)];
        [path addLineToPoint:CGPointMake(12.0, 16.4)];
        [path addLineToPoint:CGPointMake(6.2, 21.0)];
        [path closePath];
        [path fill];
    } else if ([name isEqualToString:@"download"]) {
        UIBezierPath *arrow = [UIBezierPath bezierPath];
        [arrow moveToPoint:CGPointMake(12.0, 4.0)];
        [arrow addLineToPoint:CGPointMake(12.0, 15.2)];
        [arrow moveToPoint:CGPointMake(7.0, 10.4)];
        [arrow addLineToPoint:CGPointMake(12.0, 15.4)];
        [arrow addLineToPoint:CGPointMake(17.0, 10.4)];
        [arrow stroke];
        UIBezierPath *tray = [UIBezierPath bezierPath];
        [tray moveToPoint:CGPointMake(5.0, 16.6)];
        [tray addLineToPoint:CGPointMake(5.0, 19.6)];
        [tray addLineToPoint:CGPointMake(19.0, 19.6)];
        [tray addLineToPoint:CGPointMake(19.0, 16.6)];
        [tray stroke];
    } else if ([name isEqualToString:@"upload"]) {
        UIBezierPath *arrow = [UIBezierPath bezierPath];
        [arrow moveToPoint:CGPointMake(12.0, 15.4)];
        [arrow addLineToPoint:CGPointMake(12.0, 4.2)];
        [arrow moveToPoint:CGPointMake(7.0, 9.2)];
        [arrow addLineToPoint:CGPointMake(12.0, 4.2)];
        [arrow addLineToPoint:CGPointMake(17.0, 9.2)];
        [arrow stroke];
        UIBezierPath *tray = [UIBezierPath bezierPath];
        [tray moveToPoint:CGPointMake(5.0, 16.6)];
        [tray addLineToPoint:CGPointMake(5.0, 19.6)];
        [tray addLineToPoint:CGPointMake(19.0, 19.6)];
        [tray addLineToPoint:CGPointMake(19.0, 16.6)];
        [tray stroke];
    } else if ([name isEqualToString:@"clock"]) {
        UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:
            CGRectMake(3.4, 3.4, 17.2, 17.2)];
        [circle stroke];
        UIBezierPath *hands = [UIBezierPath bezierPath];
        [hands moveToPoint:CGPointMake(12.0, 7.2)];
        [hands addLineToPoint:CGPointMake(12.0, 12.2)];
        [hands addLineToPoint:CGPointMake(15.4, 14.2)];
        [hands stroke];
    } else if ([name isEqualToString:@"folder"]) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(3.5, 7.0)];
        [path addLineToPoint:CGPointMake(9.5, 7.0)];
        [path addLineToPoint:CGPointMake(11.5, 9.4)];
        [path addLineToPoint:CGPointMake(20.5, 9.4)];
        [path addLineToPoint:CGPointMake(20.5, 19.0)];
        [path addLineToPoint:CGPointMake(3.5, 19.0)];
        [path closePath];
        [path stroke];
    } else if ([name isEqualToString:@"person"]) {
        UIBezierPath *head = [UIBezierPath bezierPathWithOvalInRect:
            CGRectMake(8.2, 3.6, 7.6, 7.6)];
        [head stroke];
        UIBezierPath *body = [UIBezierPath bezierPath];
        [body moveToPoint:CGPointMake(4.6, 20.4)];
        [body addCurveToPoint:CGPointMake(19.4, 20.4)
                controlPoint1:CGPointMake(5.4, 13.4)
                controlPoint2:CGPointMake(18.6, 13.4)];
        [body stroke];
    } else if ([name isEqualToString:@"moon"]) {
        UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:
            CGRectMake(3.0, 3.0, 18.0, 18.0)];
        [path appendPath:[UIBezierPath bezierPathWithOvalInRect:
            CGRectMake(8.6, 0.2, 18.0, 18.0)]];
        path.usesEvenOddFillRule = YES;
        [path fill];
    } else if ([name isEqualToString:@"phone"]) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:
            CGRectMake(7.0, 2.6, 10.0, 18.8) cornerRadius:2.2];
        [path stroke];
        UIBezierPath *dot = [UIBezierPath bezierPath];
        [dot moveToPoint:CGPointMake(10.4, 18.2)];
        [dot addLineToPoint:CGPointMake(13.6, 18.2)];
        [dot stroke];
    } else if ([name isEqualToString:@"trash"]) {
        UIBezierPath *lid = [UIBezierPath bezierPath];
        [lid moveToPoint:CGPointMake(4.4, 6.4)];
        [lid addLineToPoint:CGPointMake(19.6, 6.4)];
        [lid moveToPoint:CGPointMake(9.4, 6.4)];
        [lid addLineToPoint:CGPointMake(10.2, 3.4)];
        [lid addLineToPoint:CGPointMake(13.8, 3.4)];
        [lid addLineToPoint:CGPointMake(14.6, 6.4)];
        [lid stroke];
        UIBezierPath *body = [UIBezierPath bezierPath];
        [body moveToPoint:CGPointMake(6.4, 6.4)];
        [body addLineToPoint:CGPointMake(7.4, 20.6)];
        [body addLineToPoint:CGPointMake(16.6, 20.6)];
        [body addLineToPoint:CGPointMake(17.6, 6.4)];
        [body moveToPoint:CGPointMake(10.2, 10.0)];
        [body addLineToPoint:CGPointMake(10.6, 17.2)];
        [body moveToPoint:CGPointMake(13.8, 10.0)];
        [body addLineToPoint:CGPointMake(13.4, 17.2)];
        [body stroke];
    } else if ([name isEqualToString:@"info"]) {
        UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:
            CGRectMake(3.4, 3.4, 17.2, 17.2)];
        [circle stroke];
        CGContextFillEllipseInRect(ctx, CGRectMake(10.9, 7.4, 2.2, 2.2));
        UIBezierPath *line = [UIBezierPath bezierPath];
        [line moveToPoint:CGPointMake(12.0, 11.6)];
        [line addLineToPoint:CGPointMake(12.0, 16.8)];
        [line stroke];
    } else if ([name isEqualToString:@"text"]) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(4.6, 5.0)];
        [path addLineToPoint:CGPointMake(19.4, 5.0)];
        [path moveToPoint:CGPointMake(12.0, 5.0)];
        [path addLineToPoint:CGPointMake(12.0, 19.4)];
        [path stroke];
    } else if ([name isEqualToString:@"link"]) {
        UIBezierPath *a = [UIBezierPath bezierPath];
        [a addArcWithCenter:CGPointMake(8.8, 15.2) radius:4.0
                  startAngle:-M_PI * 0.25 endAngle:M_PI * 0.75 clockwise:YES];
        [a stroke];
        UIBezierPath *b = [UIBezierPath bezierPath];
        [b addArcWithCenter:CGPointMake(15.2, 8.8) radius:4.0
                  startAngle:M_PI * 0.75 endAngle:M_PI * 1.75 clockwise:YES];
        [b stroke];
        UIBezierPath *bar = [UIBezierPath bezierPath];
        [bar moveToPoint:CGPointMake(9.2, 14.8)];
        [bar addLineToPoint:CGPointMake(14.8, 9.2)];
        [bar stroke];
    } else if ([name isEqualToString:@"lock"]) {
        UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:
            CGRectMake(5.2, 10.6, 13.6, 9.8) cornerRadius:2.0];
        [body stroke];
        UIBezierPath *shackle = [UIBezierPath bezierPath];
        [shackle addArcWithCenter:CGPointMake(12.0, 10.4) radius:3.8
                       startAngle:M_PI endAngle:0 clockwise:NO];
        [shackle stroke];
    } else {
        // 未知图标：退化成圆点，避免空白。
        CGContextFillEllipseInRect(ctx, CGRectMake(10.0, 10.0, 4.0, 4.0));
    }

    CGContextRestoreGState(ctx);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@end
