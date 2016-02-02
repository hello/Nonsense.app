//
//  AppDelegate.h
//  Nonsense
//
//  Created by Delisa Mason on 6/12/15.
//  Copyright (c) 2015 Hello. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

#pragma mark - Bindings

/**
 *  The location of the timeline cache; nil indicates no trends cache should be used.
 */
@property (nonatomic, copy) NSString* timelineCachePath;

/**
 *  The location of the trends cache; nil indicates no trends cache should be used.
 */
@property (nonatomic, copy) NSString* trendsCachePath;

/**
 *  Indicates whether or not the server is currently running.
 */
@property (nonatomic, readonly) BOOL running;

/**
 *  The title for the start/stop button.
 */
@property (nonatomic, readonly, copy) NSString* runTitle;

#pragma mark - Actions

/**
 *  Starts the nonsense server if it's not running; stops it if it is.
 */
- (IBAction)toggleRunning:(id)sender;

/**
 *  Displays a single file picker to populate the timeline cache option.
 */
- (IBAction)chooseTimelineCache:(id)sender;

/**
 *  Displays a single file picker to populate the trends cache option.
 */
- (IBAction)chooseTrendsCache:(id)sender;

@end

