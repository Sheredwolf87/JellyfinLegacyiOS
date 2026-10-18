#import "JFDevice.h"
#include <sys/types.h>
#include <sys/sysctl.h>

static NSDictionary *Cond(NSString *cond, NSString *prop, NSString *value) {
    return @{@"Condition": cond, @"Property": prop, @"Value": value, @"IsRequired": @NO};
}

@implementation JFDevice

+ (JFDevice *)current {
    static JFDevice *d; static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [[JFDevice alloc] init]; });
    return d;
}

- (id)init {
    self = [super init];
    if (!self) return nil;

    size_t sz = 0;
    sysctlbyname("hw.machine", NULL, &sz, NULL, 0);
    char *buf = malloc(sz + 1);
    sysctlbyname("hw.machine", buf, &sz, NULL, 0);
    buf[sz] = 0;
    _modelIdentifier = [NSString stringWithUTF8String:buf];
    free(buf);
    NSString *m = _modelIdentifier;

    // Conservative default (also what an unrecognised/older device gets):
    // 720p, H.264 Main L3.1.
    _name = m; _maxWidth = 1280; _maxHeight = 720; _maxLevel = 31;
    _supportsHighProfile = NO; _defaultMaxBitrate = 8000000;

    if ([m hasPrefix:@"iPhone4,"]) {                 // iPhone 4S (A5)
        _name = @"iPhone 4S"; _maxWidth = 1920; _maxHeight = 1080; _maxLevel = 41;
        _supportsHighProfile = YES; _defaultMaxBitrate = 12000000;
    } else if ([m hasPrefix:@"iPhone5,"]) {          // iPhone 5 / 5c (A6)
        _name = @"iPhone 5"; _maxWidth = 1920; _maxHeight = 1080; _maxLevel = 41;
        _supportsHighProfile = YES; _defaultMaxBitrate = 20000000;
    } else if ([m hasPrefix:@"iPad2,"]) {
        int minor = [[m substringFromIndex:6] intValue];
        if (minor >= 5) {                            // iPad mini 1st gen (A5)
            _name = @"iPad mini"; _maxWidth = 1920; _maxHeight = 1080; _maxLevel = 41;
            _supportsHighProfile = YES; _defaultMaxBitrate = 20000000;
        } else {                                     // iPad 2 (A5): 720p, Main 3.1
            _name = @"iPad 2"; _maxWidth = 1280; _maxHeight = 720; _maxLevel = 31;
            _supportsHighProfile = NO; _defaultMaxBitrate = 12000000;
        }
    } else if ([m hasPrefix:@"i386"] || [m hasPrefix:@"x86_64"]) { // Simulator
        _name = @"Simulator"; _maxWidth = 1920; _maxHeight = 1080; _maxLevel = 41;
        _supportsHighProfile = YES; _defaultMaxBitrate = 20000000;
    }
    return self;
}

- (NSString *)summary {
    return [NSString stringWithFormat:@"%dp H.264 %@ L%.1f", _maxHeight,
            _supportsHighProfile ? @"High" : @"Main", _maxLevel / 10.0];
}

- (NSDictionary *)deviceProfileWithMaxBitrate:(int)bps {
    NSString *profiles = _supportsHighProfile
        ? @"baseline|constrained baseline|main|high" : @"baseline|constrained baseline|main";

    NSArray *h264Conditions = @[
        Cond(@"EqualsAny",     @"VideoProfile",   profiles),
        Cond(@"LessThanEqual", @"VideoLevel",     [NSString stringWithFormat:@"%d", _maxLevel]),
        Cond(@"LessThanEqual", @"Width",          [NSString stringWithFormat:@"%d", _maxWidth]),
        Cond(@"LessThanEqual", @"Height",         [NSString stringWithFormat:@"%d", _maxHeight]),
        Cond(@"LessThanEqual", @"VideoFramerate", @"30"),
        Cond(@"LessThanEqual", @"VideoBitDepth",  @"8")
    ];
    NSArray *stereoOnly = @[ Cond(@"LessThanEqual", @"AudioChannels", @"2") ];

    return @{
        @"Name": [NSString stringWithFormat:@"Jellyfin iOS6 (%@)", _name],
        @"MaxStreamingBitrate": @(bps),
        @"MaxStaticBitrate": @(bps),
        @"MusicStreamingTranscodingBitrate": @(192000),
        @"DirectPlayProfiles": @[
            @{@"Type": @"Video", @"Container": @"mp4,m4v,mov",
              @"VideoCodec": @"h264", @"AudioCodec": @"aac,mp3"},
            @{@"Type": @"Audio", @"Container": @"mp3", @"AudioCodec": @"mp3"},
            @{@"Type": @"Audio", @"Container": @"m4a,m4b,aac", @"AudioCodec": @"aac,alac"},
            @{@"Type": @"Audio", @"Container": @"wav,aiff,aif"}
        ],
        @"TranscodingProfiles": @[
            @{@"Type": @"Video", @"Container": @"ts", @"Protocol": @"hls", @"Context": @"Streaming",
              @"VideoCodec": @"h264", @"AudioCodec": @"aac", @"MaxAudioChannels": @"2",
              @"BreakOnNonKeyFrames": @YES},
            @{@"Type": @"Audio", @"Container": @"mp3", @"Protocol": @"http", @"Context": @"Streaming",
              @"AudioCodec": @"mp3", @"MaxAudioChannels": @"2"}
        ],
        @"CodecProfiles": @[
            @{@"Type": @"Video", @"Codec": @"h264", @"Conditions": h264Conditions},
            @{@"Type": @"VideoAudio", @"Codec": @"aac,mp3", @"Conditions": stereoOnly},
            @{@"Type": @"Audio", @"Conditions": stereoOnly}
        ],
        @"ContainerProfiles": @[],
        @"ResponseProfiles": @[],
        @"SubtitleProfiles": @[]
    };
}

@end
