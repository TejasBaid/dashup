// Bridges the private MediaRemote framework for DashUp.
//
// Since macOS 15.4, MediaRemote only answers Apple-signed processes, so this library is loaded into
// /usr/bin/perl (see now-playing.pl) and driven from there. It reads DASHUP_MR_COMMAND:
//   stream          print one JSON line per now-playing change, forever
//   get             print the current state once
//   send <command>  play | pause | toggle | next | previous
//   seek <seconds>  jump to a position
#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef void (*GetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*SendCommandFn)(int, CFDictionaryRef);
typedef void (*SetElapsedFn)(double);
typedef CFStringRef (*ClientStringFn)(id);

static void *mr;
static GetInfoFn getInfo;
static GetClientFn getClient;
static GetIsPlayingFn getIsPlaying;
static ClientStringFn clientBundleID, clientParentBundleID;
static NSString *lastArtworkHash;

static BOOL load(void) {
    mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr) return NO;
    getInfo = (GetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getClient = (GetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    getIsPlaying = (GetIsPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    clientBundleID = (ClientStringFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    clientParentBundleID = (ClientStringFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
    return getInfo != NULL;
}

static void emit(NSDictionary *object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id value(NSDictionary *info, NSString *key) {
    id v = info[[@"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:key]];
    return v == [NSNull null] ? nil : v;
}

/// Gathers info, the playing flag and the client app, then prints one JSON object.
static void report(void (^done)(void)) {
    dispatch_queue_t queue = dispatch_get_main_queue();
    getInfo(queue, ^(CFDictionaryRef raw) {
        NSDictionary *info = (__bridge NSDictionary *)raw ?: @{};
        void (^finish)(Boolean, NSString *, NSString *) = ^(Boolean playing, NSString *bundle, NSString *parent) {
            NSMutableDictionary *out = [NSMutableDictionary dictionary];
            out[@"playing"] = playing ? @YES : @NO;
            if (bundle) out[@"bundleID"] = bundle;
            if (parent) out[@"parentBundleID"] = parent;
            for (NSString *key in @[@"Title", @"Artist", @"Album"]) {
                id v = value(info, key);
                if ([v isKindOfClass:NSString.class]) out[key.lowercaseString] = v;
            }
            for (NSString *key in @[@"Duration", @"ElapsedTime", @"PlaybackRate"]) {
                id v = value(info, key);
                if ([v isKindOfClass:NSNumber.class]) out[key.lowercaseString] = v;
            }
            NSDate *timestamp = value(info, @"Timestamp");
            if ([timestamp isKindOfClass:NSDate.class]) out[@"timestamp"] = @(timestamp.timeIntervalSince1970);
            NSData *artwork = value(info, @"ArtworkData");
            if ([artwork isKindOfClass:NSData.class] && artwork.length > 0) {
                // Only send artwork bytes when they change; it can be large.
                NSString *hash = [NSString stringWithFormat:@"%lu-%lu", (unsigned long)artwork.length, (unsigned long)artwork.hash];
                out[@"artworkID"] = hash;
                if (![hash isEqualToString:lastArtworkHash]) {
                    out[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
                    lastArtworkHash = hash;
                }
            }
            emit(out);
            if (done) done();
        };
        void (^withClient)(Boolean) = ^(Boolean playing) {
            if (!getClient) { finish(playing, nil, nil); return; }
            getClient(queue, ^(id client) {
                NSString *bundle = client && clientBundleID ? (__bridge NSString *)clientBundleID(client) : nil;
                NSString *parent = client && clientParentBundleID ? (__bridge NSString *)clientParentBundleID(client) : nil;
                finish(playing, bundle, parent);
            });
        };
        if (getIsPlaying) getIsPlaying(queue, ^(Boolean playing) { withClient(playing); });
        else withClient(NO);
    });
}

void dashup_main(void) {
    @autoreleasepool {
        if (!load()) { emit(@{@"error": @"MediaRemote unavailable"}); return; }
        NSString *command = NSProcessInfo.processInfo.environment[@"DASHUP_MR_COMMAND"] ?: @"get";
        NSArray *parts = [command componentsSeparatedByString:@" "];

        if ([parts[0] isEqualToString:@"send"] && parts.count > 1) {
            NSDictionary *codes = @{@"play": @0, @"pause": @1, @"toggle": @2, @"stop": @3, @"next": @4, @"previous": @5};
            NSNumber *code = codes[parts[1]];
            SendCommandFn send = (SendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
            Boolean ok = code && send ? send(code.intValue, NULL) : false;
            emit(@{@"ok": ok ? @YES : @NO});
            return;
        }
        if ([parts[0] isEqualToString:@"seek"] && parts.count > 1) {
            SetElapsedFn seek = (SetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
            if (seek) seek([parts[1] doubleValue]);
            emit(@{@"ok": seek ? @YES : @NO});
            return;
        }
        if ([parts[0] isEqualToString:@"stream"]) {
            RegisterFn registerFn = (RegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
            if (registerFn) registerFn(dispatch_get_main_queue());
            NSArray *names = @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                               @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                               @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"];
            __block BOOL pending = NO;
            for (NSString *name in names) {
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                    // Coalesce bursts of notifications into one report.
                    if (pending) return;
                    pending = YES;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                        pending = NO;
                        report(nil);
                    });
                }];
            }
            report(nil);
            // Exit when DashUp goes away (stdin closes).
            dispatch_source_t stdinSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
            dispatch_source_set_event_handler(stdinSource, ^{
                char buffer[64];
                if (read(STDIN_FILENO, buffer, sizeof buffer) <= 0) exit(0);
            });
            dispatch_resume(stdinSource);
            // Belt and braces: also exit if DashUp dies and we're reparented to launchd.
            pid_t parent = getppid();
            dispatch_source_t watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(watchdog, DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC, NSEC_PER_SEC);
            dispatch_source_set_event_handler(watchdog, ^{
                if (getppid() != parent) exit(0);
            });
            dispatch_resume(watchdog);
            CFRunLoopRun();
            return;
        }
        report(^{ CFRunLoopStop(CFRunLoopGetMain()); });
        CFRunLoopRun();
    }
}
