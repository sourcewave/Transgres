
#import <ServiceManagement/ServiceManagement.h>
#import "AppDelegate.h"
#import "../Vendor/postgres/include/pg_config.h"

@implementation AppDelegate {
    NSStatusItem *_statusBarItem;
    NSWindowController *_welcomeWindow;
    NSTextField *socketDirectory;
    NSString *_binPath, *_varPath, *_sktPath;
}

@synthesize socketDirectory;


-(void) executeCommand: (NSString *)cmd arguments: (NSArray *)args whenDone: (void (^)(NSUInteger, NSString *))doneFunc {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath =  [_binPath stringByAppendingPathComponent: cmd];
    
    //    if (cd != NULL) task.currentDirectoryPath = [NSString stringWithUTF8String:cd];
    
    task.currentDirectoryPath = _varPath ;
    task.arguments = args;
    NSPipe *pipe = [NSPipe pipe];
    // NSPipe *pipe2 = [NSPipe pipe];
    // task.standardOutput = pipe2;
    task.standardError = pipe;
    task.standardInput = [NSPipe pipe];
    NSFileHandle * file = [pipe fileHandleForReading];
    // NSFileHandle * file2 = [pipe2 fileHandleForReading];
    task.terminationHandler = ^(NSTask *task) {
        NSData * data = [file readDataToEndOfFile];
        // NSData * data2 = [file2 readDataToEndOfFile];
        NSString * output = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
        // NSString * output2 =[[NSString alloc] initWithData: data2 encoding: NSUTF8StringEncoding];
        // output = [output stringByAppendingString: output2];
        doneFunc( [task terminationStatus], output); };
    [task launch];
}

- (void) startWithTerminationHandler:(void (^)(NSUInteger status, NSString *output))completionBlock {
    NSString *existingPGVersion = [NSString stringWithContentsOfFile:[_varPath stringByAppendingPathComponent:@"PG_VERSION"] encoding:NSUTF8StringEncoding error:nil];
    NSString *thisPGVersion = @PG_MAJORVERSION;
    
    if ( existingPGVersion && [thisPGVersion compare:existingPGVersion options:NSNumericSearch] == NSOrderedDescending) {
        NSAlert *alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:NSLocalizedString(@"Upgrade to Postgres Version %@?", nil), thisPGVersion] defaultButton:NSLocalizedString(@"OK", nil) alternateButton:NSLocalizedString(@"Quit", nil) otherButton:nil informativeTextWithFormat:NSLocalizedString(@"Your current database, configured for Postgres %@, will have its data moved to `var-%@`.\n\nA new data directory at `var`, configured for Postgres %@ will be initialized in its place.", nil), existingPGVersion, existingPGVersion, thisPGVersion];
        NSInteger result = [alert runModal];
        if (result != NSAlertDefaultReturn) [NSApp terminate:self];
        NSError *error = nil;
        BOOL ok = [[NSFileManager defaultManager] moveItemAtPath:_varPath toPath:[_varPath stringByAppendingFormat:@"-%@", existingPGVersion] error:&error];
        if (!ok) NSLog(@"Error: %@", error);

        [self executeCommand: @"pg_update" arguments: [NSArray arrayWithObjects: nil] whenDone:^(NSUInteger status, NSString *output) {
            if (status) NSLog(@"pg_update failed");
            NSAlert *alert = [NSAlert alertWithMessageText: [NSString stringWithFormat:NSLocalizedString(@"Postgres Version upgrade failed with status = %lld \n %@", nil), status, output] defaultButton: NSLocalizedString(@"OK",nil) alternateButton: nil otherButton: nil informativeTextWithFormat: NSLocalizedString(@"I must now quit", nil)];
            [alert runModal];
            [NSApp terminate: self];
        }];
        existingPGVersion = nil;
    }
    
    NSString *opts = [NSString stringWithFormat: @"-c unix_socket_directories=\"%@\"", _sktPath];
    
    if (!existingPGVersion) {
        [self executeCommand:@"initdb" arguments:[NSArray arrayWithObjects:[NSString stringWithFormat:@"-D%@", _varPath], [NSString stringWithFormat:@"-E%@", @"UTF8"], [NSString stringWithFormat:@"--locale=%@_%@", [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode], [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode]], nil] whenDone:^(NSUInteger status, NSString *output) {
            if (status) {
                NSLog(@"initdb failed");
            }
            NSLog(@"%@", output);
            
            /*
            // if upgrading....
              [self executeCommand:@"pg_upgrade" arguments:
              [NSArray arrayWithObjects:@"-d", [NSString stringWithFormat:@"%@-%@",_varPath,existingPGVersion],
               @"-D", [NSString stringWithFormat:@"%@", _varPath],
               @"-b", [NSString stringWithFormat:@"%@/postgres.%@",_binPath,existingPGVersion],
               @"-B", [NSString stringWithFormat:@"%@", _binPath],
               nil]
                        whenDone:^(NSUInteger status) {
                if (status) {
                    NSLog(@"pg_upgrade failed");
                }
            */
            
            [self executeCommand:@"pg_ctl" arguments:[NSArray arrayWithObjects:@"start", [NSString stringWithFormat:@"-D%@", _varPath], @"-w", @"-o", opts, nil] whenDone:^(NSUInteger status, NSString *output) {
                if (status) {
                    NSLog(@"pg_ctl start failed");
                }
                NSLog(@"%@", output);
                [self executeCommand:@"createdb" arguments:[NSArray arrayWithObjects: [NSString stringWithFormat: @"-h%@",_sktPath], NSUserName(), nil] whenDone:^(NSUInteger status, NSString *output) {
                        if (status) {
                            NSLog(@"createdb failed");
                        }
                    NSLog(@"%@", output);
                    if (completionBlock) {
                        completionBlock(status, output);
                    }
                }];
            }];
        }];
    } else {
        [self executeCommand:@"pg_ctl" arguments:[NSArray arrayWithObjects: @"start", [NSString stringWithFormat: @"-D%@", _varPath], @"-p", [_binPath stringByAppendingPathComponent: @"postgres"], @"-o", opts, nil] whenDone: ^(NSUInteger status, NSString *output) {
            if (completionBlock) completionBlock(status, output);

            /*NSError *err = [NSError errorWithDomain:@"pg" code: status userInfo:
                            [NSDictionary dictionaryWithObjectsAndKeys: output, NSLocalizedDescriptionKey, nil ] ]; // dictionary
            [[NSAlert alertWithError: err] beginSheetModalForWindow: nil modalDelegate: self didEndSelector: nil contextInfo: nil];
             */
        }];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _statusBarItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    _statusBarItem.menu = self.statusBarMenu;
    _statusBarItem.image = [NSImage imageNamed:@"phant2"];
    
    self.postgresStatusMenuItem = [self.statusBarMenu itemWithTag: 234];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *xsd = [[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] objectAtIndex: 0];
    NSURL *asd = [xsd URLByAppendingPathComponent: @"Transgres/var"];
    NSError *err = nil;
    [fm createDirectoryAtURL: asd withIntermediateDirectories: YES attributes: nil error: &err];

    NSURL *zzsd = [xsd URLByAppendingPathComponent: @"Transgres/ext"];
    err = nil;
    [fm createDirectoryAtURL: zzsd withIntermediateDirectories: YES attributes: nil error: &err];

    NSURL *tsd = [ [xsd URLByAppendingPathComponent: @"Transgres/tmp"] URLByStandardizingPath];
    [fm createDirectoryAtURL: tsd withIntermediateDirectories: YES attributes: nil error: &err];

    
    _binPath =[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"Resources/bin"];
    _varPath = [asd path];
    _sktPath = [tsd path];
    
    [self.postgresStatusMenuItem setEnabled:NO];
    self.postgresStatusMenuItem.title = @"Starting up";

    [self start: nil];
    
    [NSApp activateIgnoringOtherApps:YES];
    
    _welcomeWindow = [[NSWindowController alloc] initWithWindowNibName:@"WelcomeWindow"];
    NSTextField *tfv = [_welcomeWindow.window.contentView viewWithTag: 345 ];
    [tfv setStringValue: _sktPath];
    // self.socketDirectory.value = _sktPath;
    
    [_welcomeWindow.window makeKeyAndOrderFront:self];
    
}

- (void)stop {
    NSString *pidPath = [_varPath stringByAppendingPathComponent:@"postmaster.pid"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:pidPath]) {
        NSString *pid = [[[NSString stringWithContentsOfFile:pidPath encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] objectAtIndex:0];
        int t = [[NSNumberFormatter new] numberFromString: pid].intValue;
        int res = kill( (pid_t) t, SIGQUIT);
        int z = errno;
        if (res != 0) {
            NSLog(@"failed to kill %d; error = %d", t, z);
        }
    }
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    [self stop ];
    [ sender replyToApplicationShouldTerminate: YES];
    return NSTerminateNow;
}

#pragma mark - IBAction

- (IBAction)selectAbout:(id)sender {
    [NSApp activateIgnoringOtherApps: YES];
    [_welcomeWindow.window makeKeyAndOrderFront:  self];
}

- (IBAction)selectDocumentation:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"http://transgresql.org/documentation"]];
}

- (IBAction)selectPsql:(id)sender {
    // This is yet again another massive HACK
    NSString *binPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"Resources/bin"];
    NSString *psqlPath = [binPath stringByAppendingPathComponent:@"psql"];
    [[NSWorkspace sharedWorkspace] openFile:psqlPath withApplication:@"Terminal"];
}

- (IBAction)closeWelcome:(id)sender {
    [[sender window] orderOut: self];
}

-(IBAction) start:(id) sender {
    [self startWithTerminationHandler:^(NSUInteger status, NSString *output) {
        self.postgresStatusMenuItem.title = status == 0 ? @"Running" : @"Could not start";
        if ([output length] > 0) {
            NSAlert * alert= [NSAlert alertWithMessageText: output defaultButton: @"OK" alternateButton: nil otherButton: nil informativeTextWithFormat: @"stuff"];
            [alert runModal];
        }
    }];
    
}

-(NSString *)version {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *svs = [mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [NSString stringWithFormat: @"Version %@", svs];
}

@end

