#import <UIKit/UIKit.h>

NSString *JFFormatClock(double seconds);
NSDate   *JFDateFromString(NSString *iso);
NSString *JFTitleForItem(NSDictionary *item);
NSString *JFSubtitleForItem(NSDictionary *item);
CGSize    JFThumbSizeForItem(NSDictionary *item);
UIViewController *JFControllerForItem(NSDictionary *item);   // folder list or detail screen

// Does the right thing for any item: plays audio (queueing siblings), tunes live TV,
// otherwise pushes a folder list / detail screen.
void JFActivateItem(NSDictionary *item, NSArray *siblings, UIViewController *from);

@interface UIViewController (JFNowPlaying)
- (void)jf_updateNowPlayingButton;
- (void)jf_showNowPlaying;
@end
