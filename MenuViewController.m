#import "MenuViewController.h"
#import "ItemListViewController.h"
#import "ItemRouting.h"

@implementation MenuViewController {
    NSArray *_entries;
}

- (id)initWithTitle:(NSString *)title entries:(NSArray *)entries {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) { self.title = title; _entries = entries; }
    return self;
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

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [_entries count]; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"menu"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"menu"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
    }
    cell.textLabel.text = [[_entries objectAtIndex:ip.row] objectForKey:@"Title"];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *e = [_entries objectAtIndex:ip.row];
    ItemListViewController *vc = [[ItemListViewController alloc] initWithTitle:e[@"Title"]
                                                                          path:e[@"Path"] query:e[@"Query"]];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
