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

@property (nonatomic, copy) NSString *timelineCachePath;
@property (nonatomic, copy) NSString *trendsCachePath;
@property (nonatomic) BOOL running;

#pragma mark - Actions

@property (nonatomic, readonly, copy) NSString *runTitle;
- (IBAction)toggleRunning:(id)sender;
- (IBAction)chooseTimelineCache:(id)sender;
- (IBAction)chooseTrendsCache:(id)sender;

@end

