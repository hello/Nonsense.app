//
//  AppDelegate.m
//  Nonsense
//
//  Created by Delisa Mason on 6/12/15.
//  Copyright (c) 2015 Hello. All rights reserved.
//

#import "AppDelegate.h"

typedef void (^InputBlock)(NSFileHandle*);

@interface AppDelegate () <NSNetServiceDelegate>

@property (weak) IBOutlet NSWindow* window;
@property (weak) IBOutlet NSTextField* addressField;
@property (assign) IBOutlet NSTextView* logView;

@property (strong) NSTask* serverTask;
@property (strong) NSNetService* netService;

@property (nonatomic, readwrite) BOOL running;

@end

@implementation AppDelegate

NSString* const serverPort = @"3000";
NSString* const serviceType = @"_http._tcp.";
NSString* const serviceName = @"nonsense-server";

#pragma mark - Application Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
    if ([self.window respondsToSelector:@selector(setTitleVisibility:)]) {
        self.window.titleVisibility = NSWindowTitleHidden;
    }
    
    self.addressField.stringValue = [self hostNameAndPort];
}

- (void)applicationWillTerminate:(NSNotification*)aNotification
{
    [self stopWebServer];
    [self stopNetService];
}

#pragma mark - Server Task

/**
 *  Creates and returns the arguments to run the nonsense server,
 *  including any data caches chosen by the user.
 */
- (nonnull NSArray*)serverArguments {
    NSMutableArray<NSString*>* arguments = [NSMutableArray array];
    
    NSString* serverJarPath = [[NSBundle mainBundle] pathForResource:@"nonsense" ofType:@"jar"];
    [arguments addObject:@"-jar"];
    [arguments addObject:serverJarPath];
    
    if (self.timelineCachePath.length > 0) {
        [arguments addObject:@"--timeline-cache"];
        [arguments addObject:self.timelineCachePath];
    }
    
    if (self.trendsCachePath.length > 0) {
        [arguments addObject:@"--trends-cache"];
        [arguments addObject:self.trendsCachePath];
    }
    
    return [arguments copy];
}

/**
 *  Starts the nonsense web server with the options selected by the user.
 */
- (BOOL)launchWebServer
{
    NSTask* task = [NSTask new];
    [task setLaunchPath:@"/usr/bin/java"];
    task.arguments = [self serverArguments];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];
    [task.standardOutput fileHandleForReading].readabilityHandler = [self inputBlockWithTextColor:[NSColor blackColor]];
    [task.standardError fileHandleForReading].readabilityHandler = [self inputBlockWithTextColor:[NSColor redColor]];
    
    __weak __typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask* task) {
        [task.standardOutput fileHandleForReading].readabilityHandler = nil;
        [task.standardError fileHandleForReading].readabilityHandler = nil;
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [weakSelf appendOutput:@"Server stopped\n" withTextColor:[NSColor blueColor]];
        }];
    };
    self.serverTask = task;
    @try {
        [task launch];
    }
    @catch (NSException* exception) {
        [self.logView setString:[NSString stringWithFormat:@"The server launch failed! 🚀🔥 %@", exception]];
        return NO;
    }
    
    self.running = YES;
    
    return YES;
}

/**
 *  Shut down the web server
 */
- (void)stopWebServer
{
    [self.serverTask interrupt];
    self.serverTask = nil;
    self.running = NO;
}

#pragma mark - Output

/**
 *  Creates a block which when executed will write to the log view of the main window
 *  the contents of the input file handle in the specified color
 *
 *  @param textColor the color in which to draw the text
 *
 *  @return the block for handling text input from a file handle
 */
- (InputBlock)inputBlockWithTextColor:(nonnull NSColor*)textColor
{
    __weak typeof(self) weakSelf = self;
    return ^(NSFileHandle* file) {
        NSString* rawContent = [[NSString alloc] initWithData:[file availableData]
                                                     encoding:NSUTF8StringEncoding];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [weakSelf appendOutput:rawContent withTextColor:textColor];
        }];
    };
}

/**
 *  Appends a given string to the log output view using a given text color.
 *
 *  @param rawContent the content to append
 *  @param textColor the color in which to draw the text
 */
- (void)appendOutput:(nonnull NSString*)rawContent withTextColor:(nonnull NSColor*)textColor
{
    NSFont* font = [NSFont userFixedPitchFontOfSize:12.0];
    NSDictionary<NSString*, id>* attributes = @{ NSForegroundColorAttributeName : textColor,
                                                 NSFontAttributeName : font };
    NSAttributedString* content = [[NSAttributedString alloc] initWithString:rawContent
                                                                  attributes:attributes];
    [[self.logView textStorage] appendAttributedString:content];
    [self.logView scrollRangeToVisible:NSMakeRange([self.logView.string length], 0)];
}

#pragma mark - Utilities

/**
 *  Computes the host name and port of the web server to display in the window bar
 *
 *  @return host name and port delimited by a colon
 */
- (nullable NSString*)hostNameAndPort
{
    NSString* const localhostAddressIPv4 = @"127.0.0.1";
    NSString* const IPv4Matcher = @"^\\d+\\.\\d+\\.\\d+\\.\\d+$";
    
    NSError* error = nil;
    NSRegularExpression* regex = [[NSRegularExpression alloc] initWithPattern:IPv4Matcher
                                                                      options:kNilOptions
                                                                        error:&error];
    if (error) {
        return nil;
    }
    
    for (NSString* address in [[NSHost currentHost] addresses]) {
        if ([address isEqualToString:localhostAddressIPv4]) {
            continue;
        }
        
        NSRange range = [regex rangeOfFirstMatchInString:address
                                                 options:kNilOptions
                                                   range:NSMakeRange(0, address.length)];
        if (range.location != NSNotFound) {
            return [NSString stringWithFormat:@"%@:%@", address, serverPort];
        }
    }
    
    return nil;
}

#pragma mark - Net Discovery

/**
 *  Begins broadcasting the availability of the nonsense server over zero-conf/bonjour.
 */
- (void)startNetService
{
    self.netService = [[NSNetService alloc] initWithDomain:@""
                                                      type:serviceType
                                                      name:serviceName
                                                      port:serverPort.intValue];
    self.netService.delegate = self;
    [self.netService publish];
}

/**
 *  Stops broadcasting the availability of the nonsense server over zero-conf/bonjour.
 */
- (void)stopNetService
{
    [self.netService stop];
    self.netService = nil;
}

#pragma mark -

- (void)netServiceWillPublish:(NSNetService*)sender
{
    [self appendOutput:@"Preparing auto-discovery\n" withTextColor:[NSColor blueColor]];
}

- (void)netServiceDidPublish:(NSNetService*)sender
{
    NSString* output = [NSString stringWithFormat:@"Auto-discovery ready as '%@'\n", sender.name];
    [self appendOutput:output withTextColor:[NSColor blueColor]];
}

- (void)netServiceDidStop:(NSNetService *)sender {
    [self appendOutput:@"Auto-discovery stopped\n" withTextColor:[NSColor blueColor]];
}

- (void)netService:(NSNetService*)sender didNotPublish:(NSDictionary<NSString*, NSNumber*>*)errorDict
{
    NSLog(@"*** Auto-discovery failed to start: %@", errorDict);
    [self appendOutput:@"Auto-discovery failed to start\n" withTextColor:[NSColor redColor]];
}

#pragma mark - Bindings

+ (NSSet *)keyPathsForValuesAffectingRunTitle
{
    return [NSSet setWithObjects:@"running", nil];
}

- (NSString *)runTitle
{
    if (self.running) {
        return @"Stop Server";
    } else {
        return @"Start Server";
    }
}

#pragma mark - Actions

- (IBAction)toggleRunning:(id)sender
{
    if (self.running) {
        [self stopWebServer];
        [self stopNetService];
    } else {
        if ([self launchWebServer]) {
            [self startNetService];
        }
    }
}

- (IBAction)chooseTimelineCache:(id)sender
{
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    openPanel.title = @"Choose Timeline Cache";
    openPanel.prompt = @"Choose";
    openPanel.allowsMultipleSelection = NO;
    openPanel.allowedFileTypes = @[(id)kUTTypeText];
    [openPanel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result) {
        if (result == NSFileHandlingPanelOKButton) {
            self.timelineCachePath = openPanel.URL.path;
        }
    }];
}

- (IBAction)chooseTrendsCache:(id)sender
{
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    openPanel.title = @"Choose Trends Cache";
    openPanel.prompt = @"Choose";
    openPanel.allowsMultipleSelection = NO;
    openPanel.allowedFileTypes = @[(id)kUTTypeText];
    if ([openPanel runModal] == NSFileHandlingPanelOKButton) {
        self.trendsCachePath = openPanel.URL.path;
    }
}

@end
