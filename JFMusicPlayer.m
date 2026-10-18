#import "JFMusicPlayer.h"
#import "JFClient.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

NSString *const JFMusicPlayerChanged = @"JFMusicPlayerChanged";

@implementation JFMusicPlayer {
    AVPlayer *_player;
    AVPlayerItem *_observedItem;
    NSArray *_queue;
    NSInteger _index;
    JFPlayback *_pb;
    BOOL _wantsPlay, _reported;
    NSMutableDictionary *_info;
}

+ (JFMusicPlayer *)shared {
    static JFMusicPlayer *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [[JFMusicPlayer alloc] init]; });
    return p;
}

- (id)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interruption:)
            name:AVAudioSessionInterruptionNotification object:nil];
    }
    return self;
}

- (NSDictionary *)currentItem {
    return (_queue && _index >= 0 && _index < (NSInteger)[_queue count]) ? [_queue objectAtIndex:_index] : nil;
}
- (BOOL)playing { return _wantsPlay; }
- (BOOL)canSeek { return _pb && _pb.method == JFPlayMethodDirectPlay; }

- (void)notify {
    [[NSNotificationCenter defaultCenter] postNotificationName:JFMusicPlayerChanged object:self];
}

#pragma mark - Queue

- (void)playQueue:(NSArray *)items startIndex:(NSInteger)index {
    if (![items count]) return;
    _queue = [items copy];
    _index = MAX(0, MIN(index, (NSInteger)[items count] - 1));
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self startTrackForceTranscode:NO];
}

- (void)finishCurrentTrackReport {
    if (_reported) {
        [[JFClient shared] reportPlayback:@"Playing/Stopped" playback:_pb
                            positionTicks:(long long)([self currentTime] * 10000000.0) paused:NO];
        _reported = NO;
    }
    if (_observedItem) {
        [_observedItem removeObserver:self forKeyPath:@"status"];
        [[NSNotificationCenter defaultCenter] removeObserver:self
            name:AVPlayerItemDidPlayToEndTimeNotification object:_observedItem];
        _observedItem = nil;
    }
}

- (void)startTrackForceTranscode:(BOOL)force {
    [self finishCurrentTrackReport];
    NSDictionary *it = [self currentItem];
    if (!it) return;

    _pb = [[JFClient shared] audioPlaybackForItem:it forceTranscode:force];
    AVPlayerItem *pi = [AVPlayerItem playerItemWithURL:_pb.url];
    _observedItem = pi;
    [pi addObserver:self forKeyPath:@"status" options:0 context:NULL];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemEnded:)
        name:AVPlayerItemDidPlayToEndTimeNotification object:pi];

    if (!_player) _player = [[AVPlayer alloc] initWithPlayerItem:pi];
    else [_player replaceCurrentItemWithPlayerItem:pi];
    _wantsPlay = YES;
    [_player play];

    [[JFClient shared] reportPlayback:@"Playing" playback:_pb positionTicks:0 paused:NO];
    _reported = YES;
    [self updateNowPlaying];
    [self notify];
}

- (void)observeValueForKeyPath:(NSString *)kp ofObject:(id)obj change:(NSDictionary *)c context:(void *)ctx {
    if (obj == _observedItem && _observedItem.status == AVPlayerItemStatusFailed) {
        if (_pb.method == JFPlayMethodDirectPlay) [self startTrackForceTranscode:YES]; // codec we can't decode
        else [self next];                                                              // skip broken track
    }
}

- (void)itemEnded:(NSNotification *)n { [self next]; }

- (void)next {
    if (_index + 1 < (NSInteger)[_queue count]) {
        _index++;
        [self startTrackForceTranscode:NO];
    } else {
        [self stop];
    }
}

- (void)previous {
    if ([self currentTime] > 3 || _index == 0) { [self seekToSeconds:0]; return; }
    _index--;
    [self startTrackForceTranscode:NO];
}

- (void)stop {
    [self finishCurrentTrackReport];
    [_player pause];
    [_player replaceCurrentItemWithPlayerItem:nil];
    _wantsPlay = NO;
    _queue = nil;
    _pb = nil;
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [self notify];
}

#pragma mark - Transport

- (void)togglePlayPause {
    if (!_player || ![self currentItem]) return;
    if (_wantsPlay) { [_player pause]; _wantsPlay = NO; }
    else            { [_player play];  _wantsPlay = YES; }
    [self updateNowPlaying];
    [self notify];
}

- (void)seekToSeconds:(double)s {
    if (![self canSeek] && s > 0) return;
    [_player seekToTime:CMTimeMakeWithSeconds(s, 600)];
    [self updateNowPlaying];
}

- (double)currentTime {
    double t = CMTimeGetSeconds([_player currentTime]);
    return (isnan(t) || t < 0) ? 0 : t;
}

- (double)duration {
    double ticks = [[[self currentItem] objectForKey:@"RunTimeTicks"] doubleValue];
    if (ticks > 0) return ticks / 10000000.0;
    double d = CMTimeGetSeconds(_player.currentItem.duration);
    return isnan(d) ? 0 : d;
}

- (void)handleRemoteEvent:(UIEvent *)e {
    if (e.type != UIEventTypeRemoteControl) return;
    switch (e.subtype) {
        case UIEventSubtypeRemoteControlPlay:
            if (!_wantsPlay) [self togglePlayPause]; break;
        case UIEventSubtypeRemoteControlPause:
            if (_wantsPlay) [self togglePlayPause]; break;
        case UIEventSubtypeRemoteControlTogglePlayPause: [self togglePlayPause]; break;
        case UIEventSubtypeRemoteControlNextTrack:       [self next]; break;
        case UIEventSubtypeRemoteControlPreviousTrack:   [self previous]; break;
        default: break;
    }
}

- (void)interruption:(NSNotification *)n {
    NSUInteger type = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        _wantsPlay = NO;
        [self updateNowPlaying]; [self notify];
    } else {
        NSUInteger opts = [n.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        if ((opts & AVAudioSessionInterruptionOptionShouldResume) && [self currentItem]) {
            [[AVAudioSession sharedInstance] setActive:YES error:NULL];
            [_player play]; _wantsPlay = YES;
            [self updateNowPlaying]; [self notify];
        }
    }
}

#pragma mark - Now Playing info (lock screen / multitasking bar)

- (void)updateNowPlaying {
    NSDictionary *it = [self currentItem];
    if (!it) return;
    NSString *artist = [it[@"Artists"] firstObject] ?: it[@"AlbumArtist"] ?: @"";
    _info = [@{
        MPMediaItemPropertyTitle: it[@"Name"] ?: @"",
        MPMediaItemPropertyArtist: artist,
        MPMediaItemPropertyAlbumTitle: it[@"Album"] ?: @"",
        MPMediaItemPropertyPlaybackDuration: @([self duration]),
        MPNowPlayingInfoPropertyElapsedPlaybackTime: @([self currentTime]),
        MPNowPlayingInfoPropertyPlaybackRate: @(_wantsPlay ? 1.0 : 0.0)
    } mutableCopy];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = _info;

    NSString *imgId = [JFClient imageItemIdForItem:it];
    NSString *myId = it[@"Id"];
    if (imgId) {
        [[JFClient shared] loadImageForItem:imgId maxHeight:300 thumbSize:CGSizeZero completion:^(UIImage *img) {
            if (!img || ![[[self currentItem] objectForKey:@"Id"] isEqual:myId]) return;
            _info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithImage:img];
            [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = _info;
        }];
    }
}

@end
