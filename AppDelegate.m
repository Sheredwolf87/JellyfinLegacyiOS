#import "AppDelegate.h"
#import "JFClient.h"
#import "JFMusicPlayer.h"
#import "LoginViewController.h"
#import "LibraryListViewController.h"
#import <AVFoundation/AVFoundation.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Playback category: sound with the ring/silent switch off, and background audio for music.
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [session setActive:YES error:NULL];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    if ([JFClient shared].token) [self showMain]; else [self showLogin];
    [self.window makeKeyAndVisible];
    [self becomeFirstResponder]; // receives headset / multitasking-bar remote control events
    return YES;
}

- (BOOL)canBecomeFirstResponder { return YES; }

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    [[JFMusicPlayer shared] handleRemoteEvent:event];
}

- (void)showLogin {
    LoginViewController *vc = [[LoginViewController alloc] initWithStyle:UITableViewStyleGrouped];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:vc];
}

- (void)showMain {
    LibraryListViewController *vc = [[LibraryListViewController alloc] initWithStyle:UITableViewStylePlain];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:vc];
}

@end
