#import "JFPlayer.h"
#import "JFClient.h"
#import "JFMusicPlayer.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>

@implementation JFPlayer {
    MPMoviePlayerViewController *_mpvc;
    NSDictionary *_item;
    UIViewController *_presenter;
    JFPlayback *_pb;
    NSTimer *_timer;
    UIView *_hud;
    long long _startTicks;
    double _offset, _lastTotal;
    BOOL _retried, _started, _busy;
}

+ (JFPlayer *)shared {
    static JFPlayer *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [[JFPlayer alloc] init]; });
    return p;
}

#pragma mark - HUD

- (void)showHUD {
    UIWindow *w = [[UIApplication sharedApplication] keyWindow];
    _hud = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, 100)];
    _hud.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    _hud.layer.cornerRadius = 10;
    _hud.center = CGPointMake(w.bounds.size.width / 2, w.bounds.size.height / 2);
    _hud.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                            UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spin.center = CGPointMake(60, 38);
    [spin startAnimating];
    [_hud addSubview:spin];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 66, 120, 22)];
    l.text = @"Loading\u2026"; l.textAlignment = NSTextAlignmentCenter;
    l.textColor = [UIColor whiteColor]; l.backgroundColor = [UIColor clearColor];
    l.font = [UIFont boldSystemFontOfSize:15];
    [_hud addSubview:l];
    [w addSubview:_hud];
}

- (void)hideHUD { [_hud removeFromSuperview]; _hud = nil; }

#pragma mark - Start

- (void)playItem:(NSDictionary *)item startTicks:(long long)ticks presenter:(UIViewController *)presenter {
    if (_busy) return;
    _busy = YES;
    [[JFMusicPlayer shared] stop];
    _item = item;
    _startTicks = ticks;
    _presenter = presenter;
    _retried = NO;
    [self beginAllowDirect:YES];
}

- (void)beginAllowDirect:(BOOL)allowDirect {
    [self showHUD];
    [[JFClient shared] preparePlaybackForItem:_item startTicks:_startTicks allowDirect:allowDirect
                                   completion:^(JFPlayback *pb, NSError *error) {
        [self hideHUD];
        if (error || !pb) {
            _busy = NO;
            [[[UIAlertView alloc] initWithTitle:@"Can't Play"
                                        message:[error localizedDescription] ?: @"Unknown error."
                                       delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            return;
        }
        _pb = pb;
        [self presentPlayer];
    }];
}

- (void)presentPlayer {
    _started = NO;
    _lastTotal = 0;
    _offset = (_pb.method != JFPlayMethodDirectPlay && !_pb.isLive) ? _startTicks / 10000000.0 : 0;

    _mpvc = [[MPMoviePlayerViewController alloc] initWithContentURL:_pb.url];
    MPMoviePlayerController *mp = _mpvc.moviePlayer;
    mp.movieSourceType = (_pb.method == JFPlayMethodDirectPlay) ? MPMovieSourceTypeUnknown : MPMovieSourceTypeStreaming;
    if (_pb.method == JFPlayMethodDirectPlay && _startTicks > 0) {
        mp.initialPlaybackTime = _startTicks / 10000000.0;
    }

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(loadStateChanged:)
               name:MPMoviePlayerLoadStateDidChangeNotification object:mp];
    [nc addObserver:self selector:@selector(playbackFinished:)
               name:MPMoviePlayerPlaybackDidFinishNotification object:mp];

    [_presenter presentMoviePlayerViewControllerAnimated:_mpvc];
}

#pragma mark - Progress

- (void)loadStateChanged:(NSNotification *)n {
    MPMoviePlayerController *mp = _mpvc.moviePlayer;
    if (!_started && (mp.loadState & MPMovieLoadStatePlayable)) {
        _started = YES;
        [[JFClient shared] reportPlayback:@"Playing" playback:_pb
                            positionTicks:(long long)(_offset * 10000000.0) paused:NO];
        _timer = [NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    }
}

- (void)tick {
    MPMoviePlayerController *mp = _mpvc.moviePlayer;
    double cur = mp.currentPlaybackTime;
    if (!isnan(cur) && cur > 0) _lastTotal = _offset + cur;
    [[JFClient shared] reportPlayback:@"Playing/Progress" playback:_pb
                        positionTicks:(long long)(_lastTotal * 10000000.0)
                               paused:(mp.playbackState == MPMoviePlaybackStatePaused)];
}

- (void)teardownObservers {
    [_timer invalidate]; _timer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)playbackFinished:(NSNotification *)n {
    int reason = [n.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] intValue];

    double cur = _mpvc.moviePlayer.currentPlaybackTime;
    double total = (isnan(cur) || cur <= 0.5) ? _lastTotal : _offset + cur;

    JFPlayback *pb = _pb;
    NSDictionary *item = _item;
    UIViewController *presenter = _presenter;
    MPMoviePlayerViewController *vc = _mpvc;
    BOOL wasStarted = _started;

    [self teardownObservers];
    _mpvc = nil;

    long long ticks = (long long)(total * 10000000.0);
    if (reason == MPMovieFinishReasonPlaybackEnded && !pb.isLive) {
        long long rt = [item[@"RunTimeTicks"] longLongValue];
        if (rt > 0) ticks = rt;
    }
    if (wasStarted) [[JFClient shared] reportPlayback:@"Playing/Stopped" playback:pb positionTicks:ticks paused:NO];
    [[JFClient shared] endPlaybackSession:pb];

    if (reason == MPMovieFinishReasonPlaybackError) {
        BOOL canRetry = (!_retried && pb.method != JFPlayMethodTranscode && !pb.isLive);
        [presenter dismissMoviePlayerViewControllerAnimated];
        if (canRetry) {
            // Direct Play / Direct Stream failed on this device: retry as a full transcode.
            _retried = YES;
            _startTicks = (long long)(((total > 0) ? total : _startTicks / 10000000.0) * 10000000.0);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self beginAllowDirect:NO];
            });
        } else {
            _busy = NO;
            [[[UIAlertView alloc] initWithTitle:@"Can't Play"
                                        message:@"This device couldn't play the stream."
                                       delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
        return;
    }

    _busy = NO;
    // The player normally dismisses itself; make sure it does after a natural end.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (presenter.presentedViewController == vc) [presenter dismissMoviePlayerViewControllerAnimated];
    });
}

@end
