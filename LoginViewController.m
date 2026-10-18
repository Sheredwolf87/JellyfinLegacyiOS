#import "LoginViewController.h"
#import "JFClient.h"
#import "AppDelegate.h"

@implementation LoginViewController {
    UITextField *_server, *_user, *_pass;
    UIButton *_signIn;
}

- (UITextField *)makeFieldWithPlaceholder:(NSString *)ph {
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(110, 12, 170, 22)];
    f.placeholder = ph;
    f.font = [UIFont systemFontOfSize:17];
    f.textColor = [UIColor colorWithRed:0.22 green:0.33 blue:0.53 alpha:1]; // iOS 6 table-field blue
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    f.delegate = self;
    return f;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Jellyfin";

    _server = [self makeFieldWithPlaceholder:@"192.168.1.10:8096"];
    _server.keyboardType = UIKeyboardTypeURL;
    _server.returnKeyType = UIReturnKeyNext;
    _server.text = [JFClient shared].serverURL;

    _user = [self makeFieldWithPlaceholder:@"Required"];
    _user.returnKeyType = UIReturnKeyNext;

    _pass = [self makeFieldWithPlaceholder:@"Optional"];
    _pass.secureTextEntry = YES;
    _pass.returnKeyType = UIReturnKeyGo;

    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 70)];
    _signIn = [UIButton buttonWithType:UIButtonTypeRoundedRect]; // default iOS 6 grouped-table button
    _signIn.frame = CGRectMake(10, 15, 300, 44);
    _signIn.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _signIn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [_signIn setTitle:@"Sign In" forState:UIControlStateNormal];
    [_signIn addTarget:self action:@selector(signInTapped) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:_signIn];
    self.tableView.tableFooterView = footer;
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad
        ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return s == 0 ? 1 : 2; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"Server" : @"Account";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSString *rid = [NSString stringWithFormat:@"login%d_%d", (int)ip.section, (int)ip.row];
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
        UITextField *f; NSString *label;
        if (ip.section == 0) { f = _server; label = @"Address"; }
        else if (ip.row == 0) { f = _user; label = @"Username"; }
        else { f = _pass; label = @"Password"; }
        cell.textLabel.text = label;
        [cell.contentView addSubview:f];
    }
    return cell;
}

#pragma mark - Actions

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    if (tf == _server) [_user becomeFirstResponder];
    else if (tf == _user) [_pass becomeFirstResponder];
    else [self signInTapped];
    return NO;
}

- (void)alert:(NSString *)msg {
    [[[UIAlertView alloc] initWithTitle:@"Couldn't Sign In" message:msg delegate:nil
                      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (void)signInTapped {
    [self.view endEditing:YES];
    if (![_server.text length] || ![_user.text length]) {
        [self alert:@"Enter the server address and a username."];
        return;
    }
    _signIn.enabled = NO;
    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [spin startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spin];

    [[JFClient shared] loginToServer:_server.text username:_user.text password:_pass.text
                          completion:^(NSError *error) {
        self.navigationItem.rightBarButtonItem = nil;
        _signIn.enabled = YES;
        if (error) { [self alert:[error localizedDescription]]; return; }
        [(AppDelegate *)[UIApplication sharedApplication].delegate showMain];
    }];
}

@end
