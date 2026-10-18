#import "NowPlayingViewController.h"
#import "JFMusicPlayer.h"
#import "JFClient.h"
#import "ItemRouting.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>

@implementation NowPlayingViewController {
    UIImageView *_art;
    UILabel *_title, *_artist, *_album, *_elapsed, *_remaining;
    UISlider *_slider;
    UIToolbar *_toolbar;
    MPVolumeView *_volume;
    NSTimer *_timer;
    BOOL _scrubbing;
    NSString *_shownItemId;
}

+ (void)presentFrom:(UIViewController *)vc {
    UIViewController *host = vc.navigationController ?: vc;
    NowPlayingViewController *np = [[NowPlayingViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:np];
    nav.navigationBar.barStyle = UIBarStyleBlackOpaque;
    [host presentViewController:nav animated:YES completion:nil];
}

- (UILabel *)labelWithFont:(UIFont *)f color:(UIColor *)c align:(NSTextAlignment)a {
    UILabel *l = [[UILabel alloc] init];
    l.font = f; l.textColor = c; l.textAlignment = a;
    l.backgroundColor = [UIColor clearColor];
    l.shadowColor = [UIColor blackColor]; l.shadowOffset = CGSizeMake(0, -1);
    [self.view addSubview:l];
    return l;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Now Playing";
    self.view.backgroundColor = [UIColor blackColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done"
        style:UIBarButtonItemStyleDone target:self action:@selector(done)];

    _art = [[UIImageView alloc] init];
    _art.layer.shadowColor = [UIColor whiteColor].CGColor;
    _art.layer.shadowOpacity = 0.25f; _art.layer.shadowRadius = 6; _art.layer.shadowOffset = CGSizeZero;
    [self.view addSubview:_art];

    _title  = [self labelWithFont:[UIFont boldSystemFontOfSize:17] color:[UIColor whiteColor] align:NSTextAlignmentCenter];
    _artist = [self labelWithFont:[UIFont boldSystemFontOfSize:14] color:[UIColor lightGrayColor] align:NSTextAlignmentCenter];
    _album  = [self labelWithFont:[UIFont boldSystemFontOfSize:14] color:[UIColor grayColor] align:NSTextAlignmentCenter];
    _elapsed   = [self labelWithFont:[UIFont boldSystemFontOfSize:12] color:[UIColor lightGrayColor] align:NSTextAlignmentLeft];
    _remaining = [self labelWithFont:[UIFont boldSystemFontOfSize:12] color:[UIColor lightGrayColor] align:NSTextAlignmentRight];

    _slider = [[UISlider alloc] init];
    [_slider addTarget:self action:@selector(scrubBegan) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.view addSubview:_slider];

    _volume = [[MPVolumeView alloc] init];
    [self.view addSubview:_volume];

    _toolbar = [[UIToolbar alloc] init];
    _toolbar.barStyle = UIBarStyleBlack;
    _toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:_toolbar];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh)
        name:JFMusicPlayerChanged object:nil];
    [self refresh];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_timer invalidate]; _timer = nil;
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad
        ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    _toolbar.frame = CGRectMake(0, H - 44, W, 44);
    CGFloat availH = H - 44;
    BOOL wide = W > H;

    CGFloat colX, colW, infoTop, side;
    CGFloat volY = availH - 34, scrubY = volY - 44;
    if (wide) {
        side = MIN(availH - 20, W * 0.45);
        _art.frame = CGRectMake(10, 10, side, side);
        colX = side + 25; colW = W - colX - 15; infoTop = 14;
    } else {
        colX = 20; colW = W - 40;
        infoTop = scrubY - 74;
        side = MAX(60, MIN(colW, infoTop - 20));
        _art.frame = CGRectMake((W - side) / 2, 10, side, side);
    }
    _title.frame  = CGRectMake(colX, infoTop, colW, 22);
    _artist.frame = CGRectMake(colX, infoTop + 24, colW, 20);
    _album.frame  = CGRectMake(colX, infoTop + 46, colW, 20);
    _elapsed.frame   = CGRectMake(colX, scrubY, 44, 20);
    _slider.frame    = CGRectMake(colX + 48, scrubY - 2, colW - 96, 23);
    _remaining.frame = CGRectMake(colX + colW - 44, scrubY, 44, 20);
    _volume.frame    = CGRectMake(colX, volY, colW, 20);
}

#pragma mark - State

- (void)refresh {
    JFMusicPlayer *mp = [JFMusicPlayer shared];
    NSDictionary *it = mp.currentItem;
    if (!it) { [self done]; return; }

    _title.text  = it[@"Name"];
    _artist.text = [it[@"Artists"] firstObject] ?: it[@"AlbumArtist"];
    _album.text  = it[@"Album"];
    _slider.enabled = mp.canSeek;

    NSString *myId = it[@"Id"];
    if (![_shownItemId isEqual:myId]) {
        _shownItemId = myId;
        _art.image = [JFClient placeholderWithSize:CGSizeMake(10, 10)];
        NSString *imgId = [JFClient imageItemIdForItem:it];
        if (imgId) {
            int h = (int)(300 * [UIScreen mainScreen].scale);
            [[JFClient shared] loadImageForItem:imgId maxHeight:h thumbSize:CGSizeZero completion:^(UIImage *img) {
                if (img && [_shownItemId isEqual:myId]) _art.image = img;
            }];
        }
    }

    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *rw = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRewind target:self action:@selector(prev)];
    UIBarButtonItem *pp = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:mp.playing ? UIBarButtonSystemItemPause : UIBarButtonSystemItemPlay
                             target:self action:@selector(playPause)];
    UIBarButtonItem *ff = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFastForward target:self action:@selector(next)];
    _toolbar.items = @[flex, rw, flex, pp, flex, ff, flex];
}

- (void)tick {
    JFMusicPlayer *mp = [JFMusicPlayer shared];
    double d = [mp duration], t = [mp currentTime];
    _slider.maximumValue = MAX(d, 1);
    if (!_scrubbing) _slider.value = t;
    double shown = _scrubbing ? _slider.value : t;
    _elapsed.text = JFFormatClock(shown);
    _remaining.text = d > 0 ? [@"-" stringByAppendingString:JFFormatClock(MAX(0, d - shown))] : @"";
}

- (void)scrubBegan { _scrubbing = YES; }
- (void)scrubEnded {
    [[JFMusicPlayer shared] seekToSeconds:_slider.value];
    _scrubbing = NO;
}

- (void)playPause { [[JFMusicPlayer shared] togglePlayPause]; }
- (void)next      { [[JFMusicPlayer shared] next]; }
- (void)prev      { [[JFMusicPlayer shared] previous]; }

@end
