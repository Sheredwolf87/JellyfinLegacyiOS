#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern NSString *const JFMusicPlayerChanged; // posted on track / play-pause changes

// Background-capable music queue on AVPlayer, with lock-screen / control-centre-era
// remote controls (iOS 6 style: UIEvent remote control events + MPNowPlayingInfoCenter).
@interface JFMusicPlayer : NSObject
@property (nonatomic, readonly) NSDictionary *currentItem;
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, readonly) BOOL canSeek;

+ (JFMusicPlayer *)shared;
- (void)playQueue:(NSArray *)items startIndex:(NSInteger)index;
- (void)togglePlayPause;
- (void)next;
- (void)previous;
- (void)seekToSeconds:(double)seconds;
- (double)currentTime;
- (double)duration;
- (void)stop;
- (void)handleRemoteEvent:(UIEvent *)event;
@end
