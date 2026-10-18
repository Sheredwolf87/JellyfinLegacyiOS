#import "ItemListViewController.h"
#import "ItemRouting.h"
#import "JFClient.h"

static const int kPageSize = 100;

@implementation ItemListViewController {
    NSString *_path;
    NSDictionary *_query;
    NSMutableArray *_items;
    NSInteger _total;
    BOOL _loading;
}

- (id)initWithTitle:(NSString *)title path:(NSString *)path query:(NSDictionary *)query {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = title;
        _path = [path copy];
        _query = [query copy];
        _items = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 80;
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [self loadMore];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self jf_updateNowPlayingButton];
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad
        ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)reload {
    if (_loading) { [self.refreshControl endRefreshing]; return; }
    [_items removeAllObjects];
    _total = 0;
    [self.tableView reloadData];
    [self loadMore];
}

- (void)loadMore {
    if (_loading) return;
    _loading = YES;
    NSMutableDictionary *q = [_query mutableCopy];
    q[@"StartIndex"] = @([_items count]);
    q[@"Limit"] = @(kPageSize);
    [[JFClient shared] getPath:_path query:q completion:^(id json, NSError *error) {
        _loading = NO;
        [self.refreshControl endRefreshing];
        if (error) {
            [[[UIAlertView alloc] initWithTitle:@"Error" message:[error localizedDescription]
                                       delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            return;
        }
        NSArray *page = [json objectForKey:@"Items"];
        _total = [[json objectForKey:@"TotalRecordCount"] integerValue];
        [_items addObjectsFromArray:page];
        if (![page count]) _total = [_items count]; // stop paging if the server returned nothing
        [self.tableView reloadData];
    }];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [_items count]; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"item"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"item"];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    }
    if (ip.row >= (NSInteger)[_items count] - 10 && (NSInteger)[_items count] < _total) [self loadMore];

    NSDictionary *it = [_items objectAtIndex:ip.row];
    NSString *type = it[@"Type"];
    BOOL playable = [type isEqualToString:@"Audio"] || [type isEqualToString:@"TvChannel"] || [type isEqualToString:@"Program"];
    cell.accessoryType = playable ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.text = JFTitleForItem(it);
    cell.detailTextLabel.text = JFSubtitleForItem(it);

    CGSize ts = JFThumbSizeForItem(it);
    cell.imageView.image = [JFClient placeholderWithSize:ts];
    NSString *imgId = [JFClient imageItemIdForItem:it];
    if (imgId) {
        NSString *itemId = it[@"Id"];
        int h = (int)(ts.height * [UIScreen mainScreen].scale);
        [[JFClient shared] loadImageForItem:imgId maxHeight:h thumbSize:ts completion:^(UIImage *img) {
            if (!img || ip.row >= (NSInteger)[_items count]) return;
            if (![[[_items objectAtIndex:ip.row] objectForKey:@"Id"] isEqualToString:itemId]) return;
            UITableViewCell *c = [self.tableView cellForRowAtIndexPath:ip];
            c.imageView.image = img;
            [c setNeedsLayout];
        }];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    JFActivateItem([_items objectAtIndex:ip.row], _items, self);
}

@end
