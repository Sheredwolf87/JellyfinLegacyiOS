#import "ItemRouting.h"
#import "ItemListViewController.h"
#import "ItemDetailViewController.h"
#import "JFClient.h"
#import "JFPlayer.h"
#import "JFMusicPlayer.h"
#import "NowPlayingViewController.h"

NSString *JFFormatClock(double s) {
    if (isnan(s) || s < 0) s = 0;
    int t = (int)s, h = t / 3600, m = (t % 3600) / 60, sec = t % 60;
    return h > 0 ? [NSString stringWithFormat:@"%d:%02d:%02d", h, m, sec]
                 : [NSString stringWithFormat:@"%d:%02d", m, sec];
}

NSDate *JFDateFromString(NSString *s) {
    if ([s length] < 19) return nil;
    static NSDateFormatter *f; static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSDateFormatter alloc] init];
        f.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
    });
    return [f dateFromString:[s substringToIndex:19]];
}

static NSString *TimeRange(NSString *start, NSString *end) {
    NSDate *a = JFDateFromString(start), *b = JFDateFromString(end);
    if (!a || !b) return nil;
    static NSDateFormatter *f; static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSDateFormatter alloc] init];
        f.dateStyle = NSDateFormatterNoStyle; f.timeStyle = NSDateFormatterShortStyle;
    });
    return [NSString stringWithFormat:@"%@\u2013%@", [f stringFromDate:a], [f stringFromDate:b]];
}

NSString *JFTitleForItem(NSDictionary *it) {
    NSString *type = it[@"Type"], *name = it[@"Name"] ?: @"";
    if ([type isEqualToString:@"Audio"] && it[@"IndexNumber"])
        return [NSString stringWithFormat:@"%@. %@", it[@"IndexNumber"], name];
    if ([type isEqualToString:@"TvChannel"] && it[@"Number"])
        return [NSString stringWithFormat:@"%@  %@", it[@"Number"], name];
    return name;
}

NSString *JFSubtitleForItem(NSDictionary *it) {
    NSString *type = it[@"Type"];
    NSMutableArray *p = [NSMutableArray array];
    long long ticks = [it[@"RunTimeTicks"] longLongValue];

    if ([type isEqualToString:@"Audio"]) {
        NSString *artist = [it[@"Artists"] firstObject] ?: it[@"AlbumArtist"];
        if (artist) [p addObject:artist];
        if (ticks > 0) [p addObject:JFFormatClock(ticks / 10000000.0)];
    } else if ([type isEqualToString:@"MusicAlbum"]) {
        if (it[@"AlbumArtist"]) [p addObject:it[@"AlbumArtist"]];
        if (it[@"ProductionYear"]) [p addObject:[it[@"ProductionYear"] description]];
    } else if ([type isEqualToString:@"TvChannel"]) {
        NSDictionary *cp = it[@"CurrentProgram"];
        if (cp) {
            [p addObject:[@"Now: " stringByAppendingString:cp[@"Name"] ?: @""]];
            NSString *r = TimeRange(cp[@"StartDate"], cp[@"EndDate"]);
            if (r) [p addObject:r];
        }
    } else if ([type isEqualToString:@"Program"]) {
        if (it[@"ChannelName"]) [p addObject:it[@"ChannelName"]];
        NSString *r = TimeRange(it[@"StartDate"], it[@"EndDate"]);
        if (r) [p addObject:r];
    } else if ([type isEqualToString:@"MusicArtist"]) {
        // no subtitle
    } else {
        if ([type isEqualToString:@"Episode"]) {
            if (it[@"ParentIndexNumber"] && it[@"IndexNumber"])
                [p addObject:[NSString stringWithFormat:@"S%@E%@", it[@"ParentIndexNumber"], it[@"IndexNumber"]]];
            else if (it[@"IndexNumber"])
                [p addObject:[NSString stringWithFormat:@"Episode %@", it[@"IndexNumber"]]];
        }
        if (it[@"ProductionYear"]) [p addObject:[it[@"ProductionYear"] description]];
        if (ticks > 0) {
            long long pos = [it[@"UserData"][@"PlaybackPositionTicks"] longLongValue];
            if (pos > 100000000LL && pos < ticks) {
                [p addObject:[NSString stringWithFormat:@"%d min left", (int)((ticks - pos) / 600000000LL) + 1]];
            } else {
                [p addObject:[NSString stringWithFormat:@"%d min", (int)(ticks / 600000000LL)]];
            }
        }
        if (it[@"OfficialRating"]) [p addObject:it[@"OfficialRating"]];
    }
    return [p componentsJoinedByString:@" \u00B7 "];
}

CGSize JFThumbSizeForItem(NSDictionary *it) {
    NSString *t = it[@"Type"];
    if ([t isEqualToString:@"Audio"] || [t isEqualToString:@"MusicAlbum"] || [t isEqualToString:@"MusicArtist"] ||
        [t isEqualToString:@"Playlist"]) return CGSizeMake(70, 70);
    if ([t isEqualToString:@"Episode"] || [t isEqualToString:@"TvChannel"] || [t isEqualToString:@"Program"] ||
        [t isEqualToString:@"Video"] || [t isEqualToString:@"Recording"]) return CGSizeMake(100, 56);
    return CGSizeMake(47, 70);
}

UIViewController *JFControllerForItem(NSDictionary *it) {
    NSString *type = it[@"Type"], *iid = it[@"Id"], *uid = [JFClient shared].userId;
    NSString *title = it[@"Name"] ?: @"";
    NSString *itemsPath = [NSString stringWithFormat:@"/Users/%@/Items", uid];

    if ([type isEqualToString:@"MusicArtist"]) {
        return [[ItemListViewController alloc] initWithTitle:title path:itemsPath query:@{
            @"ArtistIds": iid, @"IncludeItemTypes": @"MusicAlbum", @"Recursive": @"true",
            @"SortBy": @"ProductionYear,SortName", @"SortOrder": @"Descending,Ascending",
            @"EnableImageTypes": @"Primary"}];
    }
    if ([type isEqualToString:@"Playlist"]) {
        return [[ItemListViewController alloc] initWithTitle:title
            path:[NSString stringWithFormat:@"/Playlists/%@/Items", iid]
            query:@{@"UserId": uid, @"EnableImageTypes": @"Primary"}];
    }
    if ([it[@"IsFolder"] boolValue]) {
        NSString *sort = @"SortName";
        if ([type isEqualToString:@"Season"]) sort = @"IndexNumber,SortName";
        if ([type isEqualToString:@"MusicAlbum"]) sort = @"ParentIndexNumber,IndexNumber,SortName";
        return [[ItemListViewController alloc] initWithTitle:title path:itemsPath query:@{
            @"ParentId": iid, @"SortBy": sort, @"SortOrder": @"Ascending", @"EnableImageTypes": @"Primary"}];
    }
    return [[ItemDetailViewController alloc] initWithItem:it];
}

void JFActivateItem(NSDictionary *item, NSArray *siblings, UIViewController *from) {
    NSString *type = item[@"Type"];
    UIViewController *host = from.navigationController ?: from;

    if ([type isEqualToString:@"Audio"]) {
        NSMutableArray *q = [NSMutableArray array];
        NSInteger start = 0;
        for (NSDictionary *s in siblings) {
            if (![s[@"Type"] isEqualToString:@"Audio"]) continue;
            if ([s[@"Id"] isEqual:item[@"Id"]]) start = [q count];
            [q addObject:s];
        }
        [[JFMusicPlayer shared] playQueue:q startIndex:start];
        [NowPlayingViewController presentFrom:from];
        return;
    }
    if ([type isEqualToString:@"TvChannel"]) {
        [[JFPlayer shared] playItem:item startTicks:0 presenter:host];
        return;
    }
    if ([type isEqualToString:@"Program"]) {
        if (item[@"ChannelId"]) {
            NSDictionary *ch = @{@"Id": item[@"ChannelId"], @"Type": @"TvChannel", @"Name": item[@"ChannelName"] ?: @""};
            [[JFPlayer shared] playItem:ch startTicks:0 presenter:host];
        }
        return;
    }
    [from.navigationController pushViewController:JFControllerForItem(item) animated:YES];
}

@implementation UIViewController (JFNowPlaying)
- (void)jf_updateNowPlayingButton {
    if ([JFMusicPlayer shared].currentItem) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Now Playing"
            style:UIBarButtonItemStyleBordered target:self action:@selector(jf_showNowPlaying)];
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}
- (void)jf_showNowPlaying { [NowPlayingViewController presentFrom:self]; }
@end
