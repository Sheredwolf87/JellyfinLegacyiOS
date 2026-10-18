#import "LibraryListViewController.h"
#import "ItemListViewController.h"
#import "MenuViewController.h"
#import "SettingsViewController.h"
#import "ItemRouting.h"
#import "JFClient.h"
#import "AppDelegate.h"

@implementation LibraryListViewController {
    NSArray *_views;
    NSArray *_resume;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Libraries";
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Settings" style:UIBarButtonItemStyleBordered
                                        target:self action:@selector(showSettings)];

    self.refreshControl = [[UIRefreshControl alloc] init]; // new in iOS 6
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self jf_updateNowPlayingButton];
    if (_views) [self loadResume]; // refresh "Continue Watching" after returning from playback
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad
        ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)showSettings {
    SettingsViewController *vc = [[SettingsViewController alloc] initWithStyle:UITableViewStyleGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Loading

- (void)reload {
    NSString *path = [NSString stringWithFormat:@"/Users/%@/Views", [JFClient shared].userId];
    [[JFClient shared] getPath:path query:nil completion:^(id json, NSError *error) {
        [self.refreshControl endRefreshing];
        if (error) {
            if (error.code == 401) {
                [[JFClient shared] logout];
                [(AppDelegate *)[UIApplication sharedApplication].delegate showLogin];
                return;
            }
            [[[UIAlertView alloc] initWithTitle:@"Error" message:[error localizedDescription]
                                       delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            return;
        }
        _views = [json objectForKey:@"Items"];
        [self.tableView reloadData];
        [self loadResume];
    }];
}

- (void)loadResume {
    NSString *path = [NSString stringWithFormat:@"/Users/%@/Items/Resume", [JFClient shared].userId];
    NSDictionary *q = @{@"Limit": @"10", @"MediaTypes": @"Video", @"Recursive": @"true",
                        @"EnableImageTypes": @"Primary"};
    [[JFClient shared] getPath:path query:q completion:^(id json, NSError *error) {
        if (error) return;
        _resume = [json objectForKey:@"Items"];
        [self.tableView reloadData];
    }];
}

#pragma mark - Table

- (BOOL)isResumeSection:(NSInteger)s { return [_resume count] > 0 && s == 0; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return [_resume count] > 0 ? 2 : 1; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return [self isResumeSection:s] ? @"Continue Watching" : nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return [self isResumeSection:s] ? [_resume count] : [_views count];
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    return [self isResumeSection:ip.section] ? 80 : 56;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if ([self isResumeSection:ip.section]) {
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"resume"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"resume"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
        }
        NSDictionary *it = [_resume objectAtIndex:ip.row];
        BOOL ep = [it[@"Type"] isEqualToString:@"Episode"] && it[@"SeriesName"];
        cell.textLabel.text = ep ? it[@"SeriesName"] : it[@"Name"];
        NSString *sub = JFSubtitleForItem(it);
        cell.detailTextLabel.text = ep ? [NSString stringWithFormat:@"%@ \u00B7 %@", it[@"Name"], sub] : sub;

        CGSize ts = JFThumbSizeForItem(it);
        cell.imageView.image = [JFClient placeholderWithSize:ts];
        NSString *imgId = [JFClient imageItemIdForItem:it];
        if (imgId) {
            NSString *itemId = it[@"Id"];
            int h = (int)(ts.height * [UIScreen mainScreen].scale);
            [[JFClient shared] loadImageForItem:imgId maxHeight:h thumbSize:ts completion:^(UIImage *img) {
                if (!img || ip.row >= (NSInteger)[_resume count]) return;
                if (![[[_resume objectAtIndex:ip.row] objectForKey:@"Id"] isEqualToString:itemId]) return;
                UITableViewCell *c = [self.tableView cellForRowAtIndexPath:ip];
                c.imageView.image = img;
                [c setNeedsLayout];
            }];
        }
        return cell;
    }

    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"lib"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"lib"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:18];
    }
    NSDictionary *v = [_views objectAtIndex:ip.row];
    cell.textLabel.text = v[@"Name"];
    NSString *type = v[@"CollectionType"];
    cell.detailTextLabel.text = type ? [type capitalizedString] : @"";
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if ([self isResumeSection:ip.section]) {
        JFActivateItem([_resume objectAtIndex:ip.row], _resume, self);
        return;
    }

    NSDictionary *v = [_views objectAtIndex:ip.row];
    NSString *type = v[@"CollectionType"], *vid = v[@"Id"], *uid = [JFClient shared].userId;
    NSString *itemsPath = [NSString stringWithFormat:@"/Users/%@/Items", uid];

    if ([type isEqualToString:@"music"]) {
        NSArray *entries = @[
            @{@"Title": @"Artists", @"Path": @"/Artists/AlbumArtists",
              @"Query": @{@"UserId": uid, @"ParentId": vid, @"SortBy": @"SortName", @"SortOrder": @"Ascending", @"EnableImageTypes": @"Primary"}},
            @{@"Title": @"Albums", @"Path": itemsPath,
              @"Query": @{@"ParentId": vid, @"IncludeItemTypes": @"MusicAlbum", @"Recursive": @"true", @"SortBy": @"SortName", @"SortOrder": @"Ascending", @"EnableImageTypes": @"Primary"}},
            @{@"Title": @"Songs", @"Path": itemsPath,
              @"Query": @{@"ParentId": vid, @"IncludeItemTypes": @"Audio", @"Recursive": @"true", @"SortBy": @"SortName", @"SortOrder": @"Ascending", @"EnableImageTypes": @"Primary"}}
        ];
        [self.navigationController pushViewController:
            [[MenuViewController alloc] initWithTitle:v[@"Name"] entries:entries] animated:YES];
        return;
    }

    if ([type isEqualToString:@"livetv"]) {
        NSArray *entries = @[
            @{@"Title": @"On Now", @"Path": @"/LiveTv/Programs/Recommended",
              @"Query": @{@"UserId": uid, @"IsAiring": @"true", @"EnableImageTypes": @"Primary"}},
            @{@"Title": @"Channels", @"Path": @"/LiveTv/Channels",
              @"Query": @{@"UserId": uid, @"AddCurrentProgram": @"true", @"SortBy": @"SortName", @"SortOrder": @"Ascending", @"EnableImageTypes": @"Primary"}},
            @{@"Title": @"Favorite Channels", @"Path": @"/LiveTv/Channels",
              @"Query": @{@"UserId": uid, @"IsFavorite": @"true", @"AddCurrentProgram": @"true", @"SortBy": @"SortName", @"EnableImageTypes": @"Primary"}},
            @{@"Title": @"Recordings", @"Path": @"/LiveTv/Recordings",
              @"Query": @{@"UserId": uid, @"EnableImageTypes": @"Primary"}}
        ];
        [self.navigationController pushViewController:
            [[MenuViewController alloc] initWithTitle:v[@"Name"] entries:entries] animated:YES];
        return;
    }

    ItemListViewController *vc = [[ItemListViewController alloc] initWithTitle:v[@"Name"] path:itemsPath
        query:@{@"ParentId": vid, @"SortBy": @"SortName", @"SortOrder": @"Ascending", @"EnableImageTypes": @"Primary"}];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
