#import "ItemDetailViewController.h"
#import "JFClient.h"
#import "JFPlayer.h"
#import "ItemRouting.h"
#import <QuartzCore/QuartzCore.h>

@implementation ItemDetailViewController {
    NSDictionary *_item;
    UIScrollView *_scroll;
    UIImageView *_poster;
    UILabel *_titleLabel, *_metaLabel, *_overviewLabel;
    UIButton *_playButton, *_resumeButton;
    long long _resumeTicks;
}

- (id)initWithItem:(NSDictionary *)item {
    self = [super init];
    if (self) { _item = item; self.title = item[@"Name"]; }
    return self;
}

- (UILabel *)label:(UIFont *)font color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] init];
    l.font = font;
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    l.shadowColor = [UIColor whiteColor];
    l.shadowOffset = CGSizeMake(0, 1);
    l.numberOfLines = 0;
    l.lineBreakMode = NSLineBreakByWordWrapping;
    [_scroll addSubview:l];
    return l;
}

- (UIButton *)button:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [b setTitle:title forState:UIControlStateNormal];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:b];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor]; // iOS 6 pinstripes

    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_scroll];

    _poster = [[UIImageView alloc] init];
    _poster.backgroundColor = [UIColor lightGrayColor];
    _poster.layer.shadowColor = [UIColor blackColor].CGColor;
    _poster.layer.shadowOpacity = 0.5f;
    _poster.layer.shadowOffset = CGSizeMake(0, 2);
    _poster.layer.shadowRadius = 3;
    [_scroll addSubview:_poster];

    _titleLabel    = [self label:[UIFont boldSystemFontOfSize:18] color:[UIColor colorWithWhite:0.2 alpha:1]];
    _titleLabel.text = _item[@"Name"];
    _metaLabel     = [self label:[UIFont systemFontOfSize:14] color:[UIColor colorWithRed:0.30 green:0.34 blue:0.42 alpha:1]];
    _overviewLabel = [self label:[UIFont systemFontOfSize:15] color:[UIColor colorWithWhite:0.25 alpha:1]];

    _resumeButton = [self button:@"Resume" action:@selector(resume)];
    _playButton   = [self button:@"Play" action:@selector(playFromStart)];

    [self applyItem:_item];

    BOOL pad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
    if (_item[@"ImageTags"][@"Primary"]) {
        int h = (int)((pad ? 300 : 200) * [UIScreen mainScreen].scale);
        [[JFClient shared] loadImageForItem:_item[@"Id"] maxHeight:h thumbSize:CGSizeZero completion:^(UIImage *img) {
            if (img) { _poster.image = img; _poster.backgroundColor = [UIColor clearColor]; [self.view setNeedsLayout]; }
        }];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Fetch full details (overview) and refresh the resume position after returning from playback.
    NSString *path = [NSString stringWithFormat:@"/Users/%@/Items/%@", [JFClient shared].userId, _item[@"Id"]];
    [[JFClient shared] getPath:path query:nil completion:^(id json, NSError *error) {
        if ([json isKindOfClass:[NSDictionary class]]) { _item = json; [self applyItem:json]; }
    }];
}

- (void)applyItem:(NSDictionary *)it {
    NSMutableArray *parts = [NSMutableArray array];
    if (it[@"ProductionYear"]) [parts addObject:[it[@"ProductionYear"] description]];
    if (it[@"OfficialRating"]) [parts addObject:it[@"OfficialRating"]];
    long long ticks = [it[@"RunTimeTicks"] longLongValue];
    if (ticks > 0) [parts addObject:[NSString stringWithFormat:@"%d min", (int)(ticks / 600000000LL)]];
    _metaLabel.text = [parts componentsJoinedByString:@" \u00B7 "];
    _overviewLabel.text = it[@"Overview"] ?: @"";

    long long pos = [it[@"UserData"][@"PlaybackPositionTicks"] longLongValue];
    BOOL canResume = (pos >= 100000000LL) && (ticks == 0 || pos < ticks); // at least 10 seconds in
    _resumeTicks = canResume ? pos : 0;
    _resumeButton.hidden = !canResume;
    if (canResume) {
        [_resumeButton setTitle:[NSString stringWithFormat:@"Resume %@", JFFormatClock(pos / 10000000.0)]
                       forState:UIControlStateNormal];
    }
    [_playButton setTitle:canResume ? @"Play from Start" : @"Play" forState:UIControlStateNormal];
    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL pad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
    CGFloat W = _scroll.bounds.size.width, margin = 15, y = 15;

    CGSize box = pad ? CGSizeMake(200, 300) : CGSizeMake(150, 200);
    CGSize ps = pad ? CGSizeMake(160, 240) : CGSizeMake(120, 180);
    if (_poster.image) {
        CGFloat r = MIN(box.width / _poster.image.size.width, box.height / _poster.image.size.height);
        ps = CGSizeMake(_poster.image.size.width * r, _poster.image.size.height * r);
    }
    _poster.frame = CGRectMake(margin, y, ps.width, ps.height);

    CGFloat x = margin + ps.width + 12, tw = W - x - margin, ty = y;
    CGSize ts = [_titleLabel.text sizeWithFont:_titleLabel.font constrainedToSize:CGSizeMake(tw, 90)
                                 lineBreakMode:NSLineBreakByWordWrapping];
    _titleLabel.frame = CGRectMake(x, ty, tw, ts.height);
    ty += ts.height + 4;

    CGSize ms = [_metaLabel.text sizeWithFont:_metaLabel.font constrainedToSize:CGSizeMake(tw, 40)
                                lineBreakMode:NSLineBreakByWordWrapping];
    _metaLabel.frame = CGRectMake(x, ty, tw, ms.height);
    ty += ms.height + 12;

    CGFloat bw = MIN(tw, 210);
    if (!_resumeButton.hidden) {
        _resumeButton.frame = CGRectMake(x, ty, bw, 44);
        ty += 44 + 8;
    }
    _playButton.frame = CGRectMake(x, ty, bw, 44);
    ty += 44;

    y = MAX(y + ps.height, ty) + 20;

    CGSize os = [_overviewLabel.text sizeWithFont:_overviewLabel.font
                                constrainedToSize:CGSizeMake(W - 2 * margin, 5000)
                                    lineBreakMode:NSLineBreakByWordWrapping];
    _overviewLabel.frame = CGRectMake(margin, y, W - 2 * margin, os.height);
    _scroll.contentSize = CGSizeMake(W, y + os.height + 20);
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad
        ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)resume { [self playFrom:_resumeTicks]; }
- (void)playFromStart { [self playFrom:0]; }

- (void)playFrom:(long long)ticks {
    [[JFPlayer shared] playItem:_item startTicks:ticks presenter:self.navigationController ?: self];
}

@end
