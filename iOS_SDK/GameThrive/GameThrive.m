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

#import "GameThrive.h"
#import "GTHTTPClient.h"
#import <stdlib.h>
#import <stdio.h>
#import <sys/types.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <UIKit/UIKit.h>

#define DEFAULT_PUSH_HOST @"https://gamethrive.com/api/v1/"

static GameThrive* defaultClient = nil;

@interface GameThrive ()

@property(nonatomic, readwrite, copy) NSString *app_id;
@property(nonatomic, readwrite, copy) NSDictionary *lastMessageReceived;
@property(nonatomic, readwrite, copy) NSString *deviceModel;
@property(nonatomic, readwrite, copy) NSString *systemVersion;
@property(nonatomic, retain) GTHTTPClient *httpClient;

@end

@implementation GameThrive

@synthesize app_id = _GT_publicKey;
@synthesize httpClient = _GT_httpRequest;
@synthesize lastMessageReceived;

NSMutableDictionary* tagsToSend;

NSString* mDeviceToken;
GTResultSuccessBlock tokenUpdateSuccessBlock;
GTFailureBlock tokenUpdateFailureBlock;
NSString* mPlayerId;

GTIdsAvailableBlock idsAvailableBlockWhenReady;

UIBackgroundTaskIdentifier focusBackgroundTask;


bool registeredWithApple = false;
bool gameThriveReg = false;
NSNumber* lastTrackedTime;

- (id)init {
    return [self init:nil autoRegister:true];
}

- (id)init:(BOOL)autoRegister {
    return [self init:nil autoRegister:autoRegister];
}

- (id)init:(NSString*)appId autoRegister:(BOOL)autoRegister {
    self = [super init];
    if (self) {
        lastTrackedTime = [NSNumber numberWithLongLong:[[NSDate date] timeIntervalSince1970]];
        
        if (appId)
            self.app_id = appId;
        else
            self.app_id = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"GameThrive_APPID"];
        
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@", DEFAULT_PUSH_HOST]];
        self.httpClient = [[GTHTTPClient alloc] initWithBaseURL:url];
        
        struct utsname systemInfo;
        uname(&systemInfo);
        self.deviceModel   = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
        self.systemVersion = [[UIDevice currentDevice] systemVersion];
        
        if ([GameThrive defaultClient] == nil)
            [GameThrive setDefaultClient:self];
        
        // Handle changes to the app id. This might happen on a developer's device when testing.
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        if (![self.app_id isEqualToString:[defaults stringForKey:@"GT_APP_ID"]]) {
            [defaults setObject:self.app_id forKey:@"GT_APP_ID"];
            [defaults setObject:nil forKey:@"GT_PLAYER_ID"];
            [defaults synchronize];
        }
        
        mPlayerId = [defaults stringForKey:@"GT_PLAYER_ID"];
        mDeviceToken = [defaults stringForKey:@"GT_DEVICE_TOKEN"];
        registeredWithApple = mDeviceToken != nil || [defaults boolForKey:@"GT_REGISTERED_WITH_APPLE"];
        
        // Register this device with Apple's APNS server.
        // Calls didRegisterForRemoteNotificationsWithDeviceToken in AppDelegate.m in their app,
        // which in turns calls back into our SDK via the registerDeviceToken method.
        if (autoRegister || registeredWithApple)
            [self registerForPushNotifications];
        
        if (mPlayerId != nil)
            [self registerPlayer];
        else // Fall back incase Apple does not responsed in time.
            [self performSelector:@selector(registerPlayer) withObject:nil afterDelay:30.0f];
    }
    
    clearBadgeCount();
    
    return self;
}

- (void)registerForPushNotifications {
    // For iOS 8 devices
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        // ClassFromString to work around pre Xcode 6 link errors when building an app using the GameThrive framework.
        Class uiUserNotificationSettings = NSClassFromString(@"UIUserNotificationSettings");
        NSUInteger notificationTypes = 1 << 0 | 1 << 1 | 1 << 2; // Badge, Sound, and Alert
        
        [[UIApplication sharedApplication] registerUserNotificationSettings:[uiUserNotificationSettings settingsForTypes:notificationTypes categories:nil]];
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    }
    else // For iOS 7 devices
        [[UIApplication sharedApplication] registerForRemoteNotificationTypes:UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound | UIRemoteNotificationTypeAlert];
}

- (void)registerDeviceToken:(id)inDeviceToken onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    NSString* deviceToken = [[inDeviceToken description] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
    
    [self updateDeviceToken:[[deviceToken componentsSeparatedByString:@" "] componentsJoinedByString:@""] onSuccess:successBlock onFailure:failureBlock];
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:mDeviceToken forKey:@"GT_DEVICE_TOKEN"];
    [defaults synchronize];
}

- (void)updateDeviceToken:(NSString*)deviceToken onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    
    if (mPlayerId == nil) {
        mDeviceToken = deviceToken;
        tokenUpdateSuccessBlock = successBlock;
        tokenUpdateFailureBlock = failureBlock;
        
        [self registerPlayer];
        return;
    }
    
    if ([deviceToken isEqualToString:mDeviceToken]) {
        successBlock(nil);
        return;
    }
    
    mDeviceToken = deviceToken;
    
    NSMutableURLRequest* request;
    request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"players/%@", mPlayerId]];
    
    NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             self.app_id, @"app_id",
                             deviceToken, @"identifier",
                             nil];
    
    NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
    [request setHTTPBody:postData];
    
    [self enqueueRequest:request onSuccess:successBlock onFailure:failureBlock];
}


- (NSArray*)getSoundFiles {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSError* error = nil;
    
    NSArray* allFiles = [fm contentsOfDirectoryAtPath:[[NSBundle mainBundle] resourcePath] error:&error];
    NSMutableArray* soundFiles = [NSMutableArray new];
    if (error == nil) {
        for(id file in allFiles) {
            if ([file hasSuffix:@".wav"] || [file hasSuffix:@".mp3"])
                [soundFiles addObject:file];
        }
    }
    
    return soundFiles;
}

- (void)registerPlayer {
    if (gameThriveReg)
        return;
    
    gameThriveReg = true;
    
    NSMutableURLRequest* request;
    if (mPlayerId == nil)
        request = [self.httpClient requestWithMethod:@"POST" path:@"players"];
    else
        request = [self.httpClient requestWithMethod:@"POST" path:[NSString stringWithFormat:@"players/%@/on_session", mPlayerId]];
    
    NSDictionary* infoDictionary = [[NSBundle mainBundle]infoDictionary];
    NSString* build = infoDictionary[(NSString*)kCFBundleVersionKey];
    
    NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             self.app_id, @"app_id",
                             self.deviceModel, @"device_model",
                             self.systemVersion, @"device_os",
                             [[NSLocale preferredLanguages] objectAtIndex:0], @"language",
                             [NSNumber numberWithInt:(int)[[NSTimeZone localTimeZone] secondsFromGMT]], @"timezone",
                             build, @"game_version",
                             [NSNumber numberWithInt:0], @"device_type",
                             [[[UIDevice currentDevice] identifierForVendor] UUIDString], @"ad_id",
                             [self getSoundFiles], @"sounds",
                             @"iOS1.4.0", @"sdk",
                             mDeviceToken, @"identifier", // identifier MUST be at the end as it could be nil.
                             nil];
    
    NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
    [request setHTTPBody:postData];
    
    [self enqueueRequest:request onSuccess:^(NSDictionary* results) {
        if ([results objectForKey:@"id"] != nil) {
            NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
            mPlayerId = [results objectForKey:@"id"];
            [defaults setObject:mPlayerId forKey:@"GT_PLAYER_ID"];
            [defaults synchronize];
            
            if (mDeviceToken)
                [self updateDeviceToken:mDeviceToken onSuccess:tokenUpdateSuccessBlock onFailure:tokenUpdateFailureBlock];
            
            if (tagsToSend != nil) {
                [self sendTags:tagsToSend];
                tagsToSend = nil;
            }
            
            if (idsAvailableBlockWhenReady)
                idsAvailableBlockWhenReady(mPlayerId, mDeviceToken);
        }
    } onFailure:^(NSError* error) {
        NSLog(@"Error registering with GameThrive: %@", error);
    }];
}

- (void)IdsAvailable:(GTIdsAvailableBlock)idsAvailableBlock {
    if (mPlayerId)
        idsAvailableBlock(mPlayerId, mDeviceToken);
    else
        idsAvailableBlockWhenReady = idsAvailableBlock;
}

- (NSString*)getPlayerId {
    return mPlayerId;
}

- (NSString*)getDeviceToken {
    return mDeviceToken;
}

- (void)sendTags:(NSDictionary*)keyValuePair {
    [self sendTags:keyValuePair onSuccess:nil onFailure:nil];
}

- (void)sendTags:(NSDictionary*)keyValuePair onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    if (mPlayerId == nil) {
        if (tagsToSend == nil)
            tagsToSend = [keyValuePair mutableCopy];
        else
            [tagsToSend addEntriesFromDictionary:keyValuePair];
        return;
    }
    
    NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"players/%@", mPlayerId]];
    
    NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             self.app_id, @"app_id",
                             keyValuePair, @"tags",
                             nil];
    
    NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
    [request setHTTPBody:postData];
    
    [self enqueueRequest:request
               onSuccess:successBlock
               onFailure:failureBlock];
}

- (void)sendTag:(NSString*)key value:(NSString*)value {
    [self sendTag:key value:value onSuccess:nil onFailure:nil];
}

- (void)sendTag:(NSString*)key value:(NSString*)value onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    [self sendTags:[NSDictionary dictionaryWithObjectsAndKeys: value, key, nil] onSuccess:successBlock onFailure:failureBlock];
}

- (void)getTags:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    NSMutableURLRequest* request;
    request = [self.httpClient requestWithMethod:@"GET" path:[NSString stringWithFormat:@"players/%@", mPlayerId]];
    
    [self enqueueRequest:request onSuccess:^(NSDictionary* results) {
        if ([results objectForKey:@"tags"] != nil)
            successBlock([results objectForKey:@"tags"]);
    } onFailure:failureBlock];
}

- (void)getTags:(GTResultSuccessBlock)successBlock {
    [self getTags:successBlock onFailure:nil];
}


- (void)deleteTag:(NSString*)key onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    [self deleteTags:@[key] onSuccess:successBlock onFailure:failureBlock];
}

- (void)deleteTag:(NSString*)key {
    [self deleteTags:@[key] onSuccess:nil onFailure:nil];
}

- (void)deleteTags:(NSArray*)keys onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    NSMutableURLRequest* request;
    request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"players/%@", mPlayerId]];
    
    NSMutableDictionary* deleteTagsDict = [NSMutableDictionary dictionary];
    for(id key in keys)
        [deleteTagsDict setObject:@"" forKey:key];
    
    NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             self.app_id, @"app_id",
                             deleteTagsDict, @"tags",
                             nil];
    
    NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
    [request setHTTPBody:postData];
    
    [self enqueueRequest:request onSuccess:successBlock onFailure:failureBlock];
}

- (void)deleteTags:(NSArray*)keys {
    [self deleteTags:keys onSuccess:nil onFailure:nil];
}


- (void) beginBackgroundFocusTask {
    focusBackgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [self endBackgroundFocusTask];
    }];
}

- (void) endBackgroundFocusTask {
    [[UIApplication sharedApplication] endBackgroundTask: focusBackgroundTask];
    focusBackgroundTask = UIBackgroundTaskInvalid;
}

- (void)onFocus:(NSString*)state {
    bool wasBadgeSet = false;
    
    if ([state isEqualToString:@"resume"]) {
        lastTrackedTime = [NSNumber numberWithLongLong:[[NSDate date] timeIntervalSince1970]];
        wasBadgeSet = clearBadgeCount();
    }
    
    if (mPlayerId == nil)
        return;
    
    // If resuming and badge was set, clear it on the server as well.
    if (wasBadgeSet && [state isEqualToString:@"resume"]) {
        NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"players/%@", mPlayerId]];
        
        NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                                 self.app_id, @"app_id",
                                 @0, @"badge_count",
                                 nil];
        
        NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
        [request setHTTPBody:postData];
        
        [self enqueueRequest:request onSuccess:nil onFailure:nil];
        return;
    }
    
    // Update the playtime on the server when the app put into the background or the device goes to sleep mode.
    if ([state isEqualToString:@"suspend"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self beginBackgroundFocusTask];
        
            NSNumber* timeElapsed = @(([[NSDate date] timeIntervalSince1970] - [lastTrackedTime longLongValue]) + 0.5);
            timeElapsed = [NSNumber numberWithLongLong: [timeElapsed longLongValue]];
            lastTrackedTime = [NSNumber numberWithLongLong:[[NSDate date] timeIntervalSince1970]];
            
            NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"POST" path:[NSString stringWithFormat:@"players/%@/on_focus", mPlayerId]];
            NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                                     self.app_id, @"app_id",
                                     @"ping", @"state",
                                     timeElapsed, @"active_time",
                                     nil];
            
            NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
            [request setHTTPBody:postData];
        
            // We are already running in a thread so send the request synchronous to keep the thread alive.
            [self enqueueRequest:request
                       onSuccess:nil
                       onFailure:nil
                   isSynchronous:true];
            [self endBackgroundFocusTask];
        });
    }
}

- (void)sendPurchase:(NSNumber*)amount onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"POST" path:[NSString stringWithFormat:@"players/%@/on_purchase", mPlayerId]];
    
    NSDictionary *dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             self.app_id, @"app_id",
                             amount, @"amount",
                             nil];
    
    NSData *postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
    [request setHTTPBody:postData];
    
    [self enqueueRequest:request
               onSuccess:successBlock
               onFailure:failureBlock];
}
- (void)sendPurchase:(NSNumber*)amount {
    [self sendPurchase:amount onSuccess:nil onFailure:nil];
}

- (void)notificationOpened:(NSDictionary*)messageDict {
    NSDictionary* customDict = [messageDict objectForKey:@"custom"];
    NSString* messageId = [customDict objectForKey:@"i"];
    
    NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"notifications/%@", messageId]];
    
    NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             self.app_id, @"app_id",
                             mPlayerId, @"player_id",
                             @(YES), @"opened",
                             nil];
    
    NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
    [request setHTTPBody:postData];
    
    [self enqueueRequest:request onSuccess:nil onFailure:nil];
    
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive && [customDict objectForKey:@"u"] != nil) {
        NSURL *url = [NSURL URLWithString:[customDict objectForKey:@"u"]];
        [[UIApplication sharedApplication] openURL:url];
    }
    
    self.lastMessageReceived = messageDict;
    
    // Clear bages and nofiications from this app. Setting to 1 then 0 was needed to clear the notifications.
    clearBadgeCount();
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
}

bool clearBadgeCount() {
    bool wasBadgeSet = false;
    
    if ([UIApplication sharedApplication].applicationIconBadgeNumber > 0)
        wasBadgeSet = true;
    
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:1];
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
    
    return wasBadgeSet;
}

- (NSDictionary*)getAdditionalData {
    return [[self.lastMessageReceived objectForKey:@"custom"] objectForKey:@"a"];
}

- (NSString*)getMessageString {
    return [[self.lastMessageReceived objectForKey:@"aps"] objectForKey:@"alert"];
}

- (void)enqueueRequest:(NSURLRequest*)request onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    [self enqueueRequest:request onSuccess:successBlock onFailure:failureBlock isSynchronous:false];
}

- (void)enqueueRequest:(NSURLRequest*)request onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock isSynchronous:(BOOL)isSynchronous {
    if (isSynchronous) {
        NSURLResponse* response = nil;
        NSError* error = nil;
        
        [NSURLConnection sendSynchronousRequest:request
            returningResponse:&response
            error:&error];
        
        [self handleJSONNSURLResponse:response data:nil error:error onSuccess:successBlock onFailure:failureBlock];
    }
    else {
		[NSURLConnection
            sendAsynchronousRequest:request
            queue:[[NSOperationQueue alloc] init]
            completionHandler:^(NSURLResponse* response,
                                NSData* data,
                                NSError* error) {
                [self handleJSONNSURLResponse:response data:data error:error onSuccess:successBlock onFailure:failureBlock];
            }];
    }
}

- (void)handleJSONNSURLResponse:(NSURLResponse*) response data:(NSData*) data error:(NSError*) error onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    NSHTTPURLResponse* HTTPResponse = (NSHTTPURLResponse*)response;
    NSInteger statusCode = [HTTPResponse statusCode];
    NSError* jsonError;
    NSMutableDictionary* innerJson;
    
    if (data != nil && [data length] > 0) {
        innerJson = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
        if (jsonError != nil) {
            if (failureBlock != nil)
                failureBlock([NSError errorWithDomain:@"GTError" code:statusCode userInfo:@{@"returned" : jsonError}]);
            return;
        }
    }
    
    if (error == nil && statusCode == 200) {
        if (successBlock != nil) {
            if (innerJson != nil)
                successBlock(innerJson);
            else
                successBlock(nil);
        }
    }
    else if (failureBlock != nil) {
        if (innerJson != nil && error == nil)
            failureBlock([NSError errorWithDomain:@"GTError" code:statusCode userInfo:@{@"returned" : innerJson}]);
        else if (error != nil)
            failureBlock([NSError errorWithDomain:@"GTError" code:statusCode userInfo:@{@"error" : error}]);
        else
            failureBlock([NSError errorWithDomain:@"GTError" code:statusCode userInfo:nil]);
    }
}


+ (void)setDefaultClient:(GameThrive *)client {
    defaultClient = client;
}

+ (GameThrive *)defaultClient {
    return defaultClient;
}

@end
