#import "JFClient.h"
#import "JFDevice.h"

static NSString *const kJFServer  = @"jf_server";
static NSString *const kJFUser    = @"jf_user";
static NSString *const kJFToken   = @"jf_token";
static NSString *const kJFDevice  = @"jf_device";
static NSString *const kJFDirect  = @"jf_directplay";
static NSString *const kJFMaxMbps = @"jf_maxmbps";

@implementation JFPlayback
- (NSString *)methodString {
    switch (self.method) {
        case JFPlayMethodDirectPlay:   return @"DirectPlay";
        case JFPlayMethodDirectStream: return @"DirectStream";
        default:                       return @"Transcode";
    }
}
@end

@implementation JFClient {
    NSCache *_imageCache;
}

+ (JFClient *)shared {
    static JFClient *c; static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[JFClient alloc] init]; });
    return c;
}

- (id)init {
    self = [super init];
    if (self) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        _serverURL = [d stringForKey:kJFServer];
        _userId    = [d stringForKey:kJFUser];
        _token     = [d stringForKey:kJFToken];
        _deviceId  = [d stringForKey:kJFDevice];
        if (!_deviceId) {
            _deviceId = [JFClient newUUID];
            [d setObject:_deviceId forKey:kJFDevice];
        }
        _imageCache = [[NSCache alloc] init];
        _imageCache.countLimit = 100; // iPad 2 / iPhone 4S have 512 MB of RAM
    }
    return self;
}

#pragma mark - Settings

- (BOOL)directPlayEnabled {
    NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:kJFDirect];
    return n ? [n boolValue] : YES;
}
- (void)setDirectPlayEnabled:(BOOL)b {
    [[NSUserDefaults standardUserDefaults] setBool:b forKey:kJFDirect];
}
- (int)maxBitrateMbps { return (int)[[NSUserDefaults standardUserDefaults] integerForKey:kJFMaxMbps]; }
- (void)setMaxBitrateMbps:(int)m { [[NSUserDefaults standardUserDefaults] setInteger:m forKey:kJFMaxMbps]; }

- (int)effectiveMaxBitrate {
    int m = self.maxBitrateMbps;
    return m > 0 ? m * 1000000 : [JFDevice current].defaultMaxBitrate;
}

#pragma mark - Helpers

+ (NSString *)newUUID {
    CFUUIDRef u = CFUUIDCreate(NULL);
    NSString *s = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, u);
    CFRelease(u);
    return s;
}

+ (NSString *)escape:(NSString *)s {
    return (__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(
        NULL, (__bridge CFStringRef)s, NULL, CFSTR(":/?#[]@!$&'()*+,;="), kCFStringEncodingUTF8);
}

+ (NSError *)errorWithCode:(NSInteger)code message:(NSString *)msg {
    return [NSError errorWithDomain:@"Jellyfin" code:code
                           userInfo:@{NSLocalizedDescriptionKey: msg}];
}

- (NSString *)authHeader {
    NSString *h = [NSString stringWithFormat:
        @"MediaBrowser Client=\"Jellyfin iOS6\", Device=\"%@\", DeviceId=\"%@\", Version=\"1.1.0\"",
        [JFDevice current].name, self.deviceId];
    if (self.token) h = [h stringByAppendingFormat:@", Token=\"%@\"", self.token];
    return h;
}

- (NSURL *)URLForPath:(NSString *)path query:(NSDictionary *)query {
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@%@", self.serverURL, path];
    BOOL first = YES;
    for (NSString *k in query) {
        [s appendFormat:@"%@%@=%@", first ? @"?" : @"&", k, [JFClient escape:[query[k] description]]];
        first = NO;
    }
    return [NSURL URLWithString:s];
}

- (NSURL *)absoluteURLForServerPath:(NSString *)p {
    if ([p hasPrefix:@"http://"] || [p hasPrefix:@"https://"]) return [NSURL URLWithString:p];
    if (![p hasPrefix:@"/"]) p = [@"/" stringByAppendingString:p];
    return [NSURL URLWithString:[self.serverURL stringByAppendingString:p]];
}

- (void)saveCredentials {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (self.token) {
        [d setObject:self.serverURL forKey:kJFServer];
        [d setObject:self.userId forKey:kJFUser];
        [d setObject:self.token forKey:kJFToken];
    } else {
        [d removeObjectForKey:kJFUser];
        [d removeObjectForKey:kJFToken];
    }
    [d synchronize];
}

#pragma mark - Requests

- (void)request:(NSString *)method path:(NSString *)path query:(NSDictionary *)query
           body:(NSDictionary *)body completion:(JFJSONBlock)completion {
    NSURL *url = [self URLForPath:path query:query];
    if (!url) { completion(nil, [JFClient errorWithCode:-1 message:@"Invalid server address."]); return; }

    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url
                                                     cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                 timeoutInterval:30];
    r.HTTPMethod = method;
    NSString *auth = [self authHeader];
    [r setValue:auth forHTTPHeaderField:@"X-Emby-Authorization"]; // older servers
    [r setValue:auth forHTTPHeaderField:@"Authorization"];        // newer servers
    [r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (body) {
        [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        r.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    }

    [NSURLConnection sendAsynchronousRequest:r queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
            if (err) { completion(nil, err); return; }
            NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
            if (status == 401) {
                completion(nil, [JFClient errorWithCode:401 message:@"Wrong username or password, or session expired."]);
                return;
            }
            if (status >= 400) {
                completion(nil, [JFClient errorWithCode:status
                    message:[NSString stringWithFormat:@"Server returned HTTP %d.", (int)status]]);
                return;
            }
            id json = nil;
            if ([data length]) json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            completion(json, nil);
        }];
}

- (void)getPath:(NSString *)path query:(NSDictionary *)query completion:(JFJSONBlock)completion {
    [self request:@"GET" path:path query:query body:nil completion:completion];
}

#pragma mark - Auth

- (void)loginToServer:(NSString *)url username:(NSString *)user password:(NSString *)pass
           completion:(void (^)(NSError *))completion {
    url = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![url hasPrefix:@"http://"] && ![url hasPrefix:@"https://"]) url = [@"http://" stringByAppendingString:url];
    while ([url hasSuffix:@"/"]) url = [url substringToIndex:[url length] - 1];

    self.serverURL = url;
    self.token = nil;

    NSDictionary *body = @{@"Username": user ?: @"", @"Pw": pass ?: @""};
    [self request:@"POST" path:@"/Users/AuthenticateByName" query:nil body:body
       completion:^(id json, NSError *error) {
        if (error) { completion(error); return; }
        NSString *tok = [json objectForKey:@"AccessToken"];
        NSString *uid = [[json objectForKey:@"User"] objectForKey:@"Id"];
        if (![tok length] || ![uid length]) {
            completion([JFClient errorWithCode:-2 message:@"Unexpected response. Is this a Jellyfin server?"]);
            return;
        }
        self.token = tok;
        self.userId = uid;
        [self saveCredentials];
        completion(nil);
    }];
}

- (void)logout {
    self.token = nil;
    self.userId = nil;
    [self saveCredentials];
    [_imageCache removeAllObjects];
}

#pragma mark - Images

+ (NSString *)imageItemIdForItem:(NSDictionary *)it {
    if (it[@"ImageTags"][@"Primary"]) return it[@"Id"];
    if (it[@"AlbumPrimaryImageTag"] && it[@"AlbumId"]) return it[@"AlbumId"];
    if (it[@"SeriesPrimaryImageTag"] && it[@"SeriesId"]) return it[@"SeriesId"];
    return nil;
}

+ (UIImage *)placeholderWithSize:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [[UIColor colorWithWhite:0.86 alpha:1] setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

+ (UIImage *)fitImage:(UIImage *)img inSize:(CGSize)size {
    if (img.size.width < 1 || img.size.height < 1) return [self placeholderWithSize:size];
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGFloat r = MIN(size.width / img.size.width, size.height / img.size.height);
    CGSize d = CGSizeMake(img.size.width * r, img.size.height * r);
    [img drawInRect:CGRectMake((size.width - d.width) / 2, (size.height - d.height) / 2, d.width, d.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

- (void)loadImageForItem:(NSString *)itemId maxHeight:(int)maxHeight
               thumbSize:(CGSize)thumbSize completion:(void (^)(UIImage *))completion {
    NSDictionary *q = @{@"maxHeight": @(maxHeight), @"quality": @"85", @"format": @"jpg"};
    NSURL *url = [self URLForPath:[NSString stringWithFormat:@"/Items/%@/Images/Primary", itemId] query:q];
    NSString *key = [NSString stringWithFormat:@"%@|%@", [url absoluteString], NSStringFromCGSize(thumbSize)];

    UIImage *cached = [_imageCache objectForKey:key];
    if (cached) { completion(cached); return; }

    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url];
    [r setValue:[self authHeader] forHTTPHeaderField:@"X-Emby-Authorization"];
    [NSURLConnection sendAsynchronousRequest:r queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
            UIImage *img = (!err && [data length]) ? [UIImage imageWithData:data] : nil;
            if (img && !CGSizeEqualToSize(thumbSize, CGSizeZero)) img = [JFClient fitImage:img inSize:thumbSize];
            if (img) [_imageCache setObject:img forKey:key];
            completion(img);
        }];
}

#pragma mark - Playback (video / live TV)

- (NSString *)extensionForContainer:(NSString *)c {
    NSArray *parts = [[c lowercaseString] componentsSeparatedByString:@","];
    for (NSString *want in @[@"mp4", @"m4v", @"mov"]) if ([parts containsObject:want]) return want;
    return [parts count] ? [parts objectAtIndex:0] : @"mp4";
}

- (NSURL *)URLByEnsuringAPIKey:(NSURL *)u {
    NSString *s = [u absoluteString];
    if ([s rangeOfString:@"api_key=" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        s = [s stringByAppendingFormat:@"%@api_key=%@",
             ([s rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&"), self.token];
    }
    return [NSURL URLWithString:s];
}

- (void)preparePlaybackForItem:(NSDictionary *)item startTicks:(long long)ticks
                   allowDirect:(BOOL)allowDirect
                    completion:(void (^)(JFPlayback *, NSError *))completion {
    NSString *itemId = item[@"Id"];
    BOOL live = [item[@"Type"] isEqualToString:@"TvChannel"];
    BOOL direct = allowDirect && self.directPlayEnabled && !live;
    BOOL directStream = live ? YES : direct;
    int bps = [self effectiveMaxBitrate];

    NSMutableDictionary *q = [@{
        @"UserId": self.userId,
        @"MaxStreamingBitrate": @(bps),
        @"SubtitleStreamIndex": @"-1",
        @"EnableDirectPlay": direct ? @"true" : @"false",
        @"EnableDirectStream": directStream ? @"true" : @"false",
        @"EnableTranscoding": @"true",
        @"AutoOpenLiveStream": live ? @"true" : @"false"
    } mutableCopy];
    if (ticks > 0) q[@"StartTimeTicks"] = @(ticks);

    NSMutableDictionary *body = [@{
        @"DeviceProfile": [[JFDevice current] deviceProfileWithMaxBitrate:bps],
        @"UserId": self.userId,
        @"MaxStreamingBitrate": @(bps),
        @"SubtitleStreamIndex": @(-1),
        @"EnableDirectPlay": @(direct),
        @"EnableDirectStream": @(directStream),
        @"EnableTranscoding": @YES,
        @"AutoOpenLiveStream": @(live)
    } mutableCopy];
    if (ticks > 0) body[@"StartTimeTicks"] = @(ticks);

    NSString *path = [NSString stringWithFormat:@"/Items/%@/PlaybackInfo", itemId];
    [self request:@"POST" path:path query:q body:body completion:^(id json, NSError *error) {
        NSDictionary *src = nil;
        if ([json isKindOfClass:[NSDictionary class]] && [json[@"MediaSources"] count]) {
            src = [json[@"MediaSources"] objectAtIndex:0];
        }
        if (!src) {
            if (error.code == 401) { completion(nil, error); return; }
            if (live) { completion(nil, error ?: [JFClient errorWithCode:-3 message:@"The server couldn't open this channel."]); return; }
            completion([self legacyTranscodeForItem:itemId startTicks:ticks], nil); // older server
            return;
        }

        JFPlayback *pb = [[JFPlayback alloc] init];
        pb.itemId = itemId;
        pb.mediaSourceId = src[@"Id"] ?: itemId;
        pb.playSessionId = json[@"PlaySessionId"] ?: [JFClient newUUID];
        pb.liveStreamId = src[@"LiveStreamId"];
        pb.isLive = live;

        NSString *tUrl = src[@"TranscodingUrl"];
        if (direct && [src[@"SupportsDirectPlay"] boolValue]) {
            NSString *ext = [self extensionForContainer:src[@"Container"]];
            NSDictionary *dq = @{@"Static": @"true", @"MediaSourceId": pb.mediaSourceId,
                                 @"PlaySessionId": pb.playSessionId, @"DeviceId": self.deviceId,
                                 @"api_key": self.token};
            pb.url = [self URLForPath:[NSString stringWithFormat:@"/Videos/%@/stream.%@", itemId, ext] query:dq];
            pb.method = JFPlayMethodDirectPlay;
        } else if ([tUrl length]) {
            pb.url = [self URLByEnsuringAPIKey:[self absoluteURLForServerPath:tUrl]];
            pb.method = [src[@"SupportsDirectStream"] boolValue] ? JFPlayMethodDirectStream : JFPlayMethodTranscode;
        } else {
            completion(nil, [JFClient errorWithCode:-4 message:@"The server can't stream this item to this device."]);
            return;
        }
        pb.isHLS = ([[pb.url absoluteString] rangeOfString:@".m3u8"].location != NSNotFound);
        completion(pb, nil);
    }];
}

// Forced HLS transcode for servers without a usable PlaybackInfo.
- (JFPlayback *)legacyTranscodeForItem:(NSString *)itemId startTicks:(long long)ticks {
    JFDevice *dev = [JFDevice current];
    CGSize s = [UIScreen mainScreen].bounds.size;
    int maxW = (int)(MAX(s.width, s.height) * [UIScreen mainScreen].scale);
    if (maxW > dev.maxWidth) maxW = dev.maxWidth;
    int bps = [self effectiveMaxBitrate];
    if (bps > 4000000) bps = 4000000;

    JFPlayback *pb = [[JFPlayback alloc] init];
    pb.itemId = itemId; pb.mediaSourceId = itemId; pb.playSessionId = [JFClient newUUID];
    pb.method = JFPlayMethodTranscode; pb.isHLS = YES;

    NSMutableDictionary *q = [@{
        @"MediaSourceId": itemId, @"VideoCodec": @"h264", @"AudioCodec": @"aac",
        @"TranscodingMaxAudioChannels": @"2", @"MaxWidth": @(maxW), @"VideoBitrate": @(bps),
        @"AudioBitrate": @"128000", @"SegmentContainer": @"ts", @"BreakOnNonKeyFrames": @"true",
        @"DeviceId": self.deviceId, @"PlaySessionId": pb.playSessionId, @"api_key": self.token ?: @""
    } mutableCopy];
    if (ticks > 0) q[@"StartTimeTicks"] = @(ticks);
    pb.url = [self URLForPath:[NSString stringWithFormat:@"/Videos/%@/master.m3u8", itemId] query:q];
    return pb;
}

#pragma mark - Playback (music)

- (JFPlayback *)audioPlaybackForItem:(NSDictionary *)item forceTranscode:(BOOL)force {
    NSString *itemId = item[@"Id"];
    NSString *container = [item[@"Container"] lowercaseString];
    NSSet *ok = [NSSet setWithObjects:@"mp3", @"m4a", @"m4b", @"aac", @"wav", @"aif", @"aiff", nil];

    JFPlayback *pb = [[JFPlayback alloc] init];
    pb.itemId = itemId; pb.mediaSourceId = itemId; pb.playSessionId = [JFClient newUUID];

    if (!force && self.directPlayEnabled && [ok containsObject:container]) {
        NSDictionary *q = @{@"Static": @"true", @"MediaSourceId": itemId, @"PlaySessionId": pb.playSessionId,
                            @"DeviceId": self.deviceId, @"api_key": self.token ?: @""};
        pb.url = [self URLForPath:[NSString stringWithFormat:@"/Audio/%@/stream.%@", itemId, container] query:q];
        pb.method = JFPlayMethodDirectPlay;
    } else {
        int kbps = MIN(192, [self effectiveMaxBitrate] / 1000);
        NSDictionary *q = @{@"AudioCodec": @"mp3", @"AudioBitRate": @(kbps * 1000), @"MaxAudioChannels": @"2",
                            @"MediaSourceId": itemId, @"PlaySessionId": pb.playSessionId,
                            @"DeviceId": self.deviceId, @"api_key": self.token ?: @""};
        pb.url = [self URLForPath:[NSString stringWithFormat:@"/Audio/%@/stream.mp3", itemId] query:q];
        pb.method = JFPlayMethodTranscode;
    }
    return pb;
}

#pragma mark - Session reporting

- (void)reportPlayback:(NSString *)event playback:(JFPlayback *)pb
         positionTicks:(long long)ticks paused:(BOOL)paused {
    if (!pb || !self.token) return;
    NSMutableDictionary *b = [@{
        @"ItemId": pb.itemId,
        @"MediaSourceId": pb.mediaSourceId ?: pb.itemId,
        @"PlaySessionId": pb.playSessionId ?: @"",
        @"PositionTicks": @(ticks),
        @"PlayMethod": [pb methodString],
        @"IsPaused": @(paused),
        @"CanSeek": @YES
    } mutableCopy];
    if (pb.liveStreamId) b[@"LiveStreamId"] = pb.liveStreamId;
    [self request:@"POST" path:[@"/Sessions/" stringByAppendingString:event] query:nil body:b
       completion:^(id json, NSError *error) {}];
}

- (void)endPlaybackSession:(JFPlayback *)pb {
    if (!pb) return;
    if ([pb.liveStreamId length]) {
        [self request:@"POST" path:@"/LiveStreams/Close" query:@{@"LiveStreamId": pb.liveStreamId}
                 body:nil completion:^(id j, NSError *e) {}];
    }
    if (pb.method != JFPlayMethodDirectPlay && [pb.playSessionId length]) {
        [self request:@"DELETE" path:@"/Videos/ActiveEncodings"
                query:@{@"DeviceId": self.deviceId, @"PlaySessionId": pb.playSessionId}
                 body:nil completion:^(id j, NSError *e) {}];
    }
}

@end
