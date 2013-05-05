
#import <ServiceManagement/ServiceManagement.h>
#import "AppDelegate.h"

@implementation AppDelegate {
    NSStatusItem *_statusBarItem;
    NSWindowController *_welcomeWindow;
    NSTextField *socketDirectory;
    NSString *_binPath;
    NSString *_varPath;
    NSString *_sktPath;
    xpc_connection_t _xpc_connection;
}

@synthesize socketDirectory;

- (void)executeCommandNamed:(NSString *)command
                  arguments:(NSArray *)arguments
         terminationHandler:(void (^)(NSUInteger status))terminationHandler
{
	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    
    xpc_dictionary_set_string(message, "command", [[_binPath stringByAppendingPathComponent:command] UTF8String]);
    
    xpc_object_t args = xpc_array_create(NULL, 0);
    [arguments enumerateObjectsUsingBlock:^(id argument, NSUInteger idx, BOOL *stop) {
        xpc_array_set_value(args, XPC_ARRAY_APPEND, xpc_string_create([argument UTF8String]));
    }];
    xpc_dictionary_set_value(message, "arguments", args);
    
    xpc_connection_send_message_with_reply(_xpc_connection, message, dispatch_get_main_queue(), ^(xpc_object_t object) {
        NSLog(@"%lld %s: Status %lld", xpc_dictionary_get_int64(object, "pid"), xpc_dictionary_get_string(object, "command"), xpc_dictionary_get_int64(object, "status"));
        
        if (terminationHandler) {
            terminationHandler(xpc_dictionary_get_int64(object, "status"));
        }
    });
}


- (BOOL)shouldMigrateFromVersion:(NSString *)fromVersion toVersion:(NSString *)toVersion {
    NSAlert *alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:NSLocalizedString(@"Upgrade to Postgres Version %@?", nil), toVersion] defaultButton:NSLocalizedString(@"OK", nil) alternateButton:NSLocalizedString(@"Quit", nil) otherButton:nil informativeTextWithFormat:NSLocalizedString(@"Your current database, configured for Postgres %@, will have its data moved to `var-%@`.\n\nA new data directory at `var`, configured for Postgres %@ will be initialized in its place.", nil), fromVersion, fromVersion, toVersion];
    NSInteger result = [alert runModal];
    
    return result == NSAlertDefaultReturn;
}

- (void) startWithTerminationHandler:(void (^)(NSUInteger status))completionBlock {
    //    [self stop ];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:_varPath]) {
        
    }
    
    NSString *existingPGVersion = [NSString stringWithContentsOfFile:[_varPath stringByAppendingPathComponent:@"PG_VERSION"] encoding:NSUTF8StringEncoding error:nil];
    NSString *thisPGVersion = @"9.2";
    
    NSLog(@"Existing PGVersion: %@", existingPGVersion);
    NSLog(@"This PGVersion: %@", thisPGVersion);
    
    if ( existingPGVersion) {
        if ([thisPGVersion compare:existingPGVersion options:NSNumericSearch] == NSOrderedDescending) {
            if (![self shouldMigrateFromVersion:existingPGVersion toVersion:thisPGVersion]) [NSApp terminate:self];
            NSError *error = nil;
            BOOL ok = [[NSFileManager defaultManager] moveItemAtPath:_varPath toPath:[_varPath stringByAppendingFormat:@"-%@", existingPGVersion] error:&error];
            if (!ok) NSLog(@"Error: %@", error);
            existingPGVersion = nil;
        }
    }
    
    NSString *opts = [NSString stringWithFormat: /*@"-p  %ld*/ @"-c log_destination=syslog -c logging_collector=on -c log_connections=yes -c log_min_error_statement=LOG -c unix_socket_directory=\"%@\"", /*port, */ _sktPath];
    
    if (!existingPGVersion) {
        [self executeCommandNamed:@"initdb" arguments:[NSArray arrayWithObjects:[NSString stringWithFormat:@"-D%@", _varPath], [NSString stringWithFormat:@"-E%@", @"UTF8"], [NSString stringWithFormat:@"--locale=%@_%@", [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode], [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode]], nil] terminationHandler:^(NSUInteger status) {
            if (status) {
                NSLog(@"initdb failed");
            }
            [self executeCommandNamed:@"pg_ctl" arguments:[NSArray arrayWithObjects:@"start", [NSString stringWithFormat:@"-D%@", _varPath], @"-w", @"-o", opts, nil] terminationHandler:^(NSUInteger status) {
                if (status) {
                    NSLog(@"pg_ctl start failed");
                }
                    [self executeCommandNamed:@"createdb" arguments:[NSArray arrayWithObjects: NSUserName(), nil] terminationHandler:^(NSUInteger status) {
                        if (status) {
                            NSLog(@"createdb failed");
                        }
                    if (completionBlock) {
                        completionBlock(status);
                    }
                }];
            }];
        }];
    } else {
        [self executeCommandNamed:@"pg_ctl" arguments:[NSArray arrayWithObjects:@"start", [NSString stringWithFormat:@"-D%@", _varPath], @"-o", opts, nil] terminationHandler:^(NSUInteger status) {
            // Kill server and try one more time if server can't be started
            if (status != 0) {
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    //                    [self stop ];
                    [self startWithTerminationHandler:completionBlock];
                });
            }
            
            if (completionBlock) {
                completionBlock(status);
            }
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
    NSURL *asd = [xsd URLByAppendingPathComponent: @"var"];
    NSError *err = nil;
    [fm createDirectoryAtURL: asd withIntermediateDirectories: YES attributes: nil error: &err];

    NSURL *zzsd = [xsd URLByAppendingPathComponent: @"ext"];
    err = nil;
    [fm createDirectoryAtURL: zzsd withIntermediateDirectories: YES attributes: nil error: &err];

    NSURL *tsd = [ [xsd URLByAppendingPathComponent: @"../../tmp"] URLByStandardizingPath];
    [fm createDirectoryAtURL: tsd withIntermediateDirectories: YES attributes: nil error: &err];

    
    _binPath =[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"bin"];
    _varPath = [asd path];
    _sktPath = [tsd path];
    
    _xpc_connection = xpc_connection_create("net.r0ml.postgres-service", dispatch_get_main_queue());
    xpc_connection_set_event_handler(_xpc_connection, ^(xpc_object_t event) {
        xpc_dictionary_apply(event, ^bool(const char *key, xpc_object_t value) { return true; });
    });
    xpc_connection_resume(_xpc_connection);
        
    [self start: nil];
    
    [NSApp activateIgnoringOtherApps:YES];
    
    _welcomeWindow = [[NSWindowController alloc] initWithWindowNibName:@"WelcomeWindow"];
    NSTextField *tfv = [_welcomeWindow.window.contentView viewWithTag: 345 ];
    [tfv setStringValue: _sktPath];
    // self.socketDirectory.value = _sktPath;
    
    [_welcomeWindow.window makeKeyAndOrderFront:self];
    
    [self.postgresStatusMenuItem setEnabled:NO];
    self.postgresStatusMenuItem.title = @"Starting up";
}

- (void)stopThen: (void (^)())completionBlock  {
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(message, "kill", [_varPath UTF8String]);
    xpc_connection_send_message_with_reply(_xpc_connection, message, dispatch_get_main_queue(), ^(xpc_object_t object) {
        NSLog(@"kill pid %lld status = %lld", xpc_dictionary_get_int64(object, "pid"), xpc_dictionary_get_int64(object, "status"));
        if (completionBlock) completionBlock();
    });
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {    
    [self stopThen: ^() { [ sender replyToApplicationShouldTerminate: YES]; } ];
    return NSTerminateLater;
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
    NSString *binPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"bin"];
    NSString *psqlPath = [binPath stringByAppendingPathComponent:@"psql"];
    [[NSWorkspace sharedWorkspace] openFile:psqlPath withApplication:@"Terminal"];
}

- (IBAction)closeWelcome:(id)sender {
    [[sender window] orderOut: self];
}

-(IBAction) start:(id) sender {
    [self startWithTerminationHandler:^(NSUInteger status) {
        self.postgresStatusMenuItem.title = status == 0 ? @"Running" : @"Could not start";
    }];
    
}

@end
