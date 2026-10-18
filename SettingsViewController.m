#import "SettingsViewController.h"
#import "JFClient.h"
#import "JFDevice.h"
#import "JFMusicPlayer.h"
#import "AppDelegate.h"

enum { kSheetQuality = 1, kSheetSignOut = 2 };

@implementation SettingsViewController {
    NSArray *_qualityValues;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    _qualityValues = @[@0, @20, @8, @4, @2, @1];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done"
        style:UIBarButtonItemStyleDone target:self action:@selector(done)];
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad
        ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (NSString *)qualityText {
    int m = [JFClient shared].maxBitrateMbps;
    if (m > 0) return [NSString stringWithFormat:@"%d Mbps", m];
    return [NSString stringWithFormat:@"Auto (%d Mbps)", [JFDevice current].defaultMaxBitrate / 1000000];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? 2 : (s == 1 ? 2 : 2);
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"Playback" : (s == 1 ? @"This Device" : @"Account");
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"Direct Play uses the original file when this device can decode it. Otherwise the server converts it. If Direct Play fails, playback retries as a transcode automatically.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    JFClient *c = [JFClient shared];
    JFDevice *d = [JFDevice current];

    if (ip.section == 0 && ip.row == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"Direct Play";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = c.directPlayEnabled;
        [sw addTarget:self action:@selector(directPlayChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (ip.section == 0) {
        cell.textLabel.text = @"Max Quality";
        cell.detailTextLabel.text = [self qualityText];
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.section == 1) {
        if (ip.row == 0) { cell.textLabel.text = @"Device"; cell.detailTextLabel.text = d.name; }
        else             { cell.textLabel.text = @"Decodes";  cell.detailTextLabel.text = [d summary]; }
    } else {
        if (ip.row == 0) {
            cell.textLabel.text = @"Server";
            cell.detailTextLabel.text = c.serverURL;
            cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
        } else {
            cell.textLabel.text = @"Sign Out";
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = [UIColor colorWithRed:0.75 green:0.1 blue:0.1 alpha:1];
            cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        }
    }
    return cell;
}

- (void)directPlayChanged:(UISwitch *)sw { [JFClient shared].directPlayEnabled = sw.on; }

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0 && ip.row == 1) {
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Max Streaming Quality" delegate:self
            cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
        sheet.tag = kSheetQuality;
        [sheet addButtonWithTitle:[NSString stringWithFormat:@"Auto (%d Mbps)", [JFDevice current].defaultMaxBitrate / 1000000]];
        for (NSNumber *n in [_qualityValues subarrayWithRange:NSMakeRange(1, [_qualityValues count] - 1)])
            [sheet addButtonWithTitle:[NSString stringWithFormat:@"%@ Mbps", n]];
        sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
        [sheet showInView:self.navigationController.view];
    } else if (ip.section == 2 && ip.row == 1) {
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self
            cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Sign Out" otherButtonTitles:nil];
        sheet.tag = kSheetSignOut;
        [sheet showInView:self.navigationController.view];
    }
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)i {
    if (i == sheet.cancelButtonIndex) return;
    if (sheet.tag == kSheetQuality) {
        [JFClient shared].maxBitrateMbps = [[_qualityValues objectAtIndex:i] intValue];
        [self.tableView reloadData];
    } else if (sheet.tag == kSheetSignOut) {
        [[JFMusicPlayer shared] stop];
        [[JFClient shared] logout];
        [(AppDelegate *)[UIApplication sharedApplication].delegate showLogin];
    }
}

@end
