
#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (weak) IBOutlet NSMenu *statusBarMenu;
@property (weak) IBOutlet NSMenuItem *postgresStatusMenuItem;
@property IBOutlet NSTextField *socketDirectory;

- (IBAction)selectAbout:(id)sender;
- (IBAction)selectDocumentation:(id)sender;
- (IBAction)selectPsql:(id)sender;
- (IBAction)closeWelcome:(id)sender;
- (IBAction)start:(id)sender;

@property (readonly) NSString *version;

@end
