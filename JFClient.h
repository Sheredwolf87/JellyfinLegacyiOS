#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef void (^JFJSONBlock)(id json, NSError *error);

typedef enum {
    JFPlayMethodDirectPlay = 0,
    JFPlayMethodDirectStream,
    JFPlayMethodTranscode
} JFPlayMethod;

// Result of asking the server how to play something.
@interface JFPlayback : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) JFPlayMethod method;
@property (nonatomic, copy) NSString *itemId, *mediaSourceId, *playSessionId, *liveStreamId;
@property (nonatomic, assign) BOOL isLive, isHLS;
- (NSString *)methodString;
@end

@interface JFClient : NSObject

@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *deviceId;

// Settings (persisted)
@property (nonatomic, assign) BOOL directPlayEnabled;   // default YES
@property (nonatomic, assign) int maxBitrateMbps;       // 0 = Auto (device default)

+ (JFClient *)shared;

- (void)loginToServer:(NSString *)url username:(NSString *)user password:(NSString *)pass
           completion:(void (^)(NSError *error))completion;
- (void)logout;

- (NSURL *)URLForPath:(NSString *)path query:(NSDictionary *)query;
- (NSString *)authHeader;
- (void)request:(NSString *)method path:(NSString *)path query:(NSDictionary *)query
           body:(NSDictionary *)body completion:(JFJSONBlock)completion;
- (void)getPath:(NSString *)path query:(NSDictionary *)query completion:(JFJSONBlock)completion;

// Images
+ (NSString *)imageItemIdForItem:(NSDictionary *)item;  // item, album or series that has art (or nil)
+ (UIImage *)placeholderWithSize:(CGSize)size;
+ (UIImage *)fitImage:(UIImage *)img inSize:(CGSize)size;
- (void)loadImageForItem:(NSString *)itemId maxHeight:(int)maxHeight
               thumbSize:(CGSize)thumbSize completion:(void (^)(UIImage *image))completion;

// Playback
- (int)effectiveMaxBitrate;
// Video, recordings and live TV channels. Asks /Items/{id}/PlaybackInfo with this
// device's profile; falls back to a forced HLS transcode on older servers.
- (void)preparePlaybackForItem:(NSDictionary *)item startTicks:(long long)ticks
                   allowDirect:(BOOL)allowDirect
                    completion:(void (^)(JFPlayback *playback, NSError *error))completion;
// Music: synchronous (direct play when the container is iOS-friendly, otherwise MP3 transcode).
- (JFPlayback *)audioPlaybackForItem:(NSDictionary *)item forceTranscode:(BOOL)force;

- (void)reportPlayback:(NSString *)event playback:(JFPlayback *)pb
         positionTicks:(long long)ticks paused:(BOOL)paused; // "Playing", "Playing/Progress", "Playing/Stopped"
- (void)endPlaybackSession:(JFPlayback *)pb;                  // closes live streams / kills transcodes

+ (NSString *)newUUID;
@end
