
#include <xpc/xpc.h>
#include <Foundation/Foundation.h>
#include <pwd.h>

/*
xpc_object_t reply = xpc_dictionary_create_reply(event);
xpc_dictionary_set_string(reply, "command", [[task launchPath] UTF8String]);
xpc_dictionary_set_int64(reply, "status", [task terminationStatus]);
xpc_dictionary_set_int64(reply, "pid", [task processIdentifier]);
xpc_connection_send_message(peer, reply);
*/

static NSString *varDir = nil;

static NSString *getDir() {
    if (varDir == nil) {
        char buf[4096];
        char *homeDir = "/";
        struct passwd* pwd = getpwuid(getuid());
        if (pwd) homeDir = pwd->pw_dir;
        snprintf(buf, 4096, "%s/Library/Containers/net.r0ml.transgres/Data/Library/Application Support/var", homeDir);
        varDir = [NSString stringWithUTF8String: (const char *)&buf];
    }
    return varDir;
}

static void do_kill(NSString *dir, xpc_connection_t peer, xpc_object_t event) {
    int t = 0, z = 0;
    NSString *pidPath = [dir stringByAppendingPathComponent:@"postmaster.pid"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:pidPath]) {
        NSString *pid = [[[NSString stringWithContentsOfFile:pidPath encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] objectAtIndex:0];
        t = [[NSNumberFormatter new] numberFromString: pid].intValue;
        int res = kill( (pid_t) t, SIGQUIT);
        z = errno;
        if (res != 0) {
            NSLog(@"failed to kill %d; error = %d", t, z);
        }
        else [[NSFileManager defaultManager] removeItemAtPath:pidPath error:nil];
    }
    xpc_object_t reply = xpc_dictionary_create_reply(event);
    xpc_dictionary_set_int64(reply, "status", z);
    xpc_dictionary_set_int64(reply, "pid", t);
    xpc_connection_send_message(peer, reply);
}

static void do_command(NSString *command, xpc_connection_t peer, xpc_object_t event) {
    NSMutableArray *mutableArguments = [NSMutableArray array];
    xpc_array_apply(xpc_dictionary_get_value(event, "arguments"), ^_Bool(size_t index, xpc_object_t obj) {
        const char *string = xpc_string_get_string_ptr(obj);
        [mutableArguments addObject:[NSString stringWithUTF8String:string]];
        return true;
    });
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = command;

    const char *cd = xpc_dictionary_get_string(event, "current_directory");
    if (cd != NULL) task.currentDirectoryPath = [NSString stringWithUTF8String:cd];

    task.arguments = mutableArguments;
    task.terminationHandler = ^(NSTask *task) {
        xpc_object_t reply = xpc_dictionary_create_reply(event);
        xpc_dictionary_set_string(reply, "command", [[task launchPath] UTF8String]);
        xpc_dictionary_set_int64(reply, "status", [task terminationStatus]);
        xpc_dictionary_set_int64(reply, "pid", [task processIdentifier]);
        xpc_connection_send_message(peer, reply);
    };
    [task launch];
}

static void peer_event_handler(xpc_connection_t peer, xpc_object_t event) {
	xpc_type_t type = xpc_get_type(event);
	if (type == XPC_TYPE_ERROR) {
        do_kill(getDir(), peer, event); // a hack to get the dir because I didn't get one
        return;
	}
    
	assert(type == XPC_TYPE_DICTIONARY);
    const char *cmd = xpc_dictionary_get_string(event, "command");
    if (cmd != NULL) { do_command( [NSString stringWithUTF8String: cmd], peer, event); return; }
    const char *k = xpc_dictionary_get_string(event, "kill");
    if ( k != NULL) do_kill( [NSString stringWithUTF8String: k], peer, event);
}


static void event_handler(xpc_connection_t peer)  {
	xpc_connection_set_event_handler(peer, ^(xpc_object_t event) { peer_event_handler(peer, event); });
    xpc_connection_resume(peer);
}

int main(int argc, const char *argv[]) {
	xpc_main(event_handler);
	return 0;
}
