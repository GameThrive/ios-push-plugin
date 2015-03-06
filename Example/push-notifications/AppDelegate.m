/**
 * Modified MIT License
 *
 * Copyright 2015 GameThrive
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * 1. The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * 2. All copies of substantial portions of the Software may only be used in connection
 * with services provided by GameThrive.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
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
