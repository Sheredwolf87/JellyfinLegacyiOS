#import <UIKit/UIKit.h>

// A paged list of any Jellyfin query result (items, artists, channels, recordings...).
@interface ItemListViewController : UITableViewController
- (id)initWithTitle:(NSString *)title path:(NSString *)path query:(NSDictionary *)query;
@end
