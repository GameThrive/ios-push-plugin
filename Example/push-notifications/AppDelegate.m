/**
 * Copyright 2014 GameThrive
 * Portions Copyright 2014 StackMob
 *
 * This file includes portions from the StackMob iOS SDK and distributed under an Apache 2.0 license.
 * StackMob was acquired by PayPal and ceased operation on May 22, 2014.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "AppDelegate.h"

@implementation AppDelegate
@synthesize gameThrive = _gameThrive;

- (void)application:(UIApplication*)app didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken {
    NSLog(@"Device Registered with Apple.");
    [self.gameThrive registerDeviceToken:deviceToken onSuccess:^(NSDictionary* results) {
        NSLog(@"Device Registered with GameThrive.");
    } onFailure:^(NSError* error) {
        NSLog(@"Error in GameThrive Registration: %@", error);
    }];
}

- (void)application:(UIApplication*)app didFailToRegisterForRemoteNotificationsWithError:(NSError*)err {
    NSLog(@"Error in Apple registration. Error: %@", err);
}

- (void)applicationWillResignActive:(UIApplication*)application {
    [self.gameThrive onFocus:@"suspend"];
}

- (void)applicationDidBecomeActive:(UIApplication*)application {
    [self.gameThrive onFocus:@"resume"];
}


- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
    self.gameThrive = [[GameThrive alloc] init];
    
    NSDictionary* userInfo = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (userInfo)
        [self processNotificationOpened:userInfo isActive:false];
    
    return YES;
}

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo {
    [self processNotificationOpened:userInfo isActive:[application applicationState] == UIApplicationStateActive];
}

- (void)processNotificationOpened:(NSDictionary*) messageData isActive:(bool)isActive {
    // notificationOpened must be called here. Everything else below is optional in your game.
    [self.gameThrive notificationOpened:messageData];
    
    NSString* message = [self.gameThrive getMessageString];
    NSDictionary* additionalData = [self.gameThrive getAdditionalData];
    
    UIAlertView* alertView;
    
    if (additionalData != nil) {
        // Append AdditionalData at the end of the message
        message = [message stringByAppendingString:[NSString stringWithFormat:@":data:%@", additionalData]];
        
        NSString* messageTitle;
        if ([additionalData objectForKey:@"discount"] != nil)
            messageTitle = @"Discount!";
        else if ([additionalData objectForKey:@"bonusCredits"] != nil)
            messageTitle = @"Bonus Credits!";
        else
            messageTitle = @"Other Extra Data";
        
        alertView = [[UIAlertView alloc] initWithTitle:messageTitle
                                               message:message
                                              delegate:self
                                     cancelButtonTitle:@"Close"
                                     otherButtonTitles:@"Show", nil];
    }
    
    // If a push notification is received when the app is being used it does not go to the notifiction center so display in your app.
    if (alertView == nil && isActive) {
        alertView = [[UIAlertView alloc] initWithTitle:@"GameThrive Message"
                                               message:message
                                              delegate:self
                                     cancelButtonTitle:@"Close"
                                     otherButtonTitles:@"Show", nil];
    }
    
    // Add your game logic around this so the user is not interrupted during gameplay.
    if (alertView != nil)
        [alertView show];
}

@end
