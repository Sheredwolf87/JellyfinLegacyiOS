#import <Foundation/Foundation.h>

// Knows what the hardware can decode and builds the Jellyfin DeviceProfile that
// lets the server decide between Direct Play, Direct Stream and Transcode.
// Tuned for: iPhone 4S, iPhone 5/5c, iPad 2, iPad mini (1st gen).
@interface JFDevice : NSObject
@property (nonatomic, readonly) NSString *modelIdentifier;   // e.g. "iPad2,5"
@property (nonatomic, readonly) NSString *name;              // e.g. "iPad mini"
@property (nonatomic, readonly) int maxWidth;                // max decodable H.264 frame
@property (nonatomic, readonly) int maxHeight;
@property (nonatomic, readonly) int maxLevel;                // H.264 level x10 (31, 41)
@property (nonatomic, readonly) BOOL supportsHighProfile;
@property (nonatomic, readonly) int defaultMaxBitrate;       // bits per second ("Auto")

+ (JFDevice *)current;
- (NSString *)summary;
- (NSDictionary *)deviceProfileWithMaxBitrate:(int)bps;
@end
