#import <UIKit/UIKit.h>

// A short list of sections. Each entry: @{@"Title", @"Path", @"Query"}.
@interface MenuViewController : UITableViewController
- (id)initWithTitle:(NSString *)title entries:(NSArray *)entries;
@end
