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

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
    self.gameThrive = [[GameThrive alloc] initWithLaunchOptions:launchOptions handleNotification:^(NSString* message, NSDictionary* additionalData, BOOL isActive) {
        UIAlertView* alertView;
        
        NSLog(@"APP LOG ADDITIONALDATA: %@", additionalData);
        
        if (additionalData) {
            // Append AdditionalData at the end of the message
            NSString* displayMessage = [NSString stringWithFormat:@"NotificationMessage:%@", message];
            
            NSString* messageTitle;
            if (additionalData[@"discount"])
                messageTitle = additionalData[@"discount"];
            else if (additionalData[@"bonusCredits"])
                messageTitle = additionalData[@"bonusCredits"];
            else if (additionalData[@"actionSelected"])
                messageTitle = [NSString stringWithFormat:@"Pressed ButtonId:%@", additionalData[@"actionSelected"]];
            
            alertView = [[UIAlertView alloc] initWithTitle:messageTitle
                                                   message:displayMessage
                                                  delegate:self
                                         cancelButtonTitle:@"Close"
                                         otherButtonTitles:nil, nil];
        }
        
        // If a push notification is received when the app is being used it does not go to the notifiction center so display in your app.
        if (alertView == nil && isActive) {
            alertView = [[UIAlertView alloc] initWithTitle:@"GameThrive Message"
                                                   message:message
                                                  delegate:self
                                         cancelButtonTitle:@"Close"
                                         otherButtonTitles:nil, nil];
        }
        
        // Highly recommend adding game logic around this so the user is not interrupted during gameplay.
        if (alertView != nil)
            [alertView show];

    }];
    
    return YES;
}

@end
