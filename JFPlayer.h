#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Plays video, recordings and live TV channels in MPMoviePlayerViewController.
// Handles resume, Direct Play -> transcode fallback and server progress reports.
@interface JFPlayer : NSObject
+ (JFPlayer *)shared;
- (void)playItem:(NSDictionary *)item startTicks:(long long)ticks presenter:(UIViewController *)presenter;
@end
