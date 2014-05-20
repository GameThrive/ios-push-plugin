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

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

#import "GameThrive.h"
#import "GTHTTPClient.h"
#import "AFJSONRequestOperation.h"
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
//#if TARGET_OS_MAC
//        /* Get this for mac */
//        self.systemVersion = [[NSProcessInfo processInfo] operatingSystemVersionString];
//        
//        size_t len = 0;
//        sysctlbyname("hw.model", NULL, &len, NULL, 0);
//        if(len)
//        {
//            char *model = malloc(len*sizeof(char));
//            sysctlbyname("hw.model", model, &len, NULL, 0);
//            
//            self.deviceModel = [[NSString alloc] initWithCString:model encoding:NSUTF8StringEncoding];
//            
//            free(model);
//        }
//#else
        struct utsname systemInfo;
        uname(&systemInfo);
        self.deviceModel   = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
        self.systemVersion = [[UIDevice currentDevice] systemVersion];
//#endif
        
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
        
        registeredWithApple = [[NSUserDefaults standardUserDefaults] boolForKey:@"GT_REGISTERED_WITH_APPLE"];
        
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
    
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
    
    return self;
}

- (void)registerDeviceToken:(id)inDeviceToken onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    NSString* deviceToken = [[inDeviceToken description] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
    
    [self updateDeviceToken:[[deviceToken componentsSeparatedByString:@" "] componentsJoinedByString:@""] onSuccess:successBlock onFailure:failureBlock];
    
    if (!registeredWithApple) {
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:@(YES) forKey:@"GT_REGISTERED_WITH_APPLE"];
        [defaults synchronize];
    }
}

- (void)registerForPushNotifications {
    [[UIApplication sharedApplication] registerForRemoteNotificationTypes:UIRemoteNotificationTypeAlert];
}

- (void)updateDeviceToken:(NSString*)deviceToken onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    if (mPlayerId == nil) {
        mDeviceToken = deviceToken;
        tokenUpdateSuccessBlock = successBlock;
        tokenUpdateFailureBlock = failureBlock;
        
        [self registerPlayer];
        return;
    }
    
    NSMutableURLRequest* request;
    request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"players/%@", mPlayerId]  parameters:nil];
    
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
        request = [self.httpClient requestWithMethod:@"POST" path:@"players" parameters:nil];
    else
        request = [self.httpClient requestWithMethod:@"POST" path:[NSString stringWithFormat:@"players/%@/on_session", mPlayerId]  parameters:nil];
    
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
                             @"iOS 1.2.2", @"sdk",
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
        }
    } onFailure:nil];
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
    
    NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"players/%@", mPlayerId]  parameters:nil];
    
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
    request = [self.httpClient requestWithMethod:@"GET" path:[NSString stringWithFormat:@"players/%@", mPlayerId]  parameters:nil];
    
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
    request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"players/%@", mPlayerId]  parameters:nil];
    
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
    if ([state isEqualToString:@"resume"]) {
        lastTrackedTime = [NSNumber numberWithLongLong:[[NSDate date] timeIntervalSince1970]];
        return;
    }
    
    if (mPlayerId == nil)
        return;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self beginBackgroundFocusTask];
        
        NSNumber* timeElapsed = @(([[NSDate date] timeIntervalSince1970] - [lastTrackedTime longLongValue]) + 0.5);
        timeElapsed = [NSNumber numberWithLongLong: [timeElapsed longLongValue]];
        lastTrackedTime = [NSNumber numberWithLongLong:[[NSDate date] timeIntervalSince1970]];
        
        NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"POST" path:[NSString stringWithFormat:@"players/%@/on_focus", mPlayerId]  parameters:nil];
        NSDictionary* dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                                 self.app_id, @"app_id",
                                 @"ping", @"state",
                                 timeElapsed, @"active_time",
                                 nil];
        
        NSData* postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
        [request setHTTPBody:postData];
        
        [self enqueueRequest:request
                   onSuccess:nil
                   onFailure:nil
               isSynchronous:true];
        
        [self endBackgroundFocusTask];
    });
}

- (void)sendPurchase:(NSNumber*)amount onSuccess:(GTResultSuccessBlock)successBlock onFailure:(GTFailureBlock)failureBlock {
    NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"POST" path:[NSString stringWithFormat:@"players/%@/on_purchase", mPlayerId]  parameters:nil];
    
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
    
    NSMutableURLRequest* request = [self.httpClient requestWithMethod:@"PUT" path:[NSString stringWithFormat:@"notifications/%@", messageId]  parameters:nil];
    
    NSDictionary *dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             self.app_id, @"app_id",
                             mPlayerId, @"player_id",
                             @(YES), @"opened",
                             nil];
    
    NSData *postData = [NSJSONSerialization dataWithJSONObject:dataDic options:0 error:nil];
    [request setHTTPBody:postData];
    
    [self enqueueRequest:request onSuccess:nil onFailure:nil];
    
    if ([customDict objectForKey:@"u"] != nil) {
        NSURL *url = [NSURL URLWithString:[customDict objectForKey:@"u"]];
        [[UIApplication sharedApplication] openURL:url];
    }
    
    self.lastMessageReceived = messageDict;
    
    // Clear bages and nofiications from this app. Setting to 1 then 0 was needed to clear the notifications.
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:1];
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
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
    AFJSONRequestOperation* op = [AFJSONRequestOperation JSONRequestOperationWithRequest:request success:^(NSURLRequest *urlRequest, NSHTTPURLResponse *response, id JSON) {
        if (successBlock != nil)
            successBlock(JSON);
    }failure:^(NSURLRequest *urlRequest, NSHTTPURLResponse *response, NSError *error, id JSON) {
        if (failureBlock != nil)
            failureBlock([NSError errorWithDomain:@"GTError" code:[response statusCode] userInfo:JSON]);
    }];
    [self.httpClient enqueueHTTPRequestOperation:op];
    
    if (isSynchronous)
        [op waitUntilFinished];
}


+ (void)setDefaultClient:(GameThrive *)client {
    defaultClient = client;
}

+ (GameThrive *)defaultClient {
    return defaultClient;
}

@end
