/**
 * Copyright 2014 GameThrive
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

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "GTTrackPlayerPurchase.h"
#import "GameThrive.h"

@implementation GTTrackPlayerPurchase

static Class skPaymentQueue;
NSMutableDictionary* skusToTrack;

+ (BOOL)canTrack {
    skPaymentQueue = NSClassFromString(@"SKPaymentQueue");
    return (skPaymentQueue != nil && [skPaymentQueue performSelector:@selector(canMakePayments)]);
}

- (id)init {
    self = [super init];
    
    if (self)
        [[skPaymentQueue performSelector:@selector(defaultQueue)] performSelector:@selector(addTransactionObserver:) withObject:self];
    
    return self;
}

- (void)paymentQueue:(id)queue updatedTransactions:(NSArray*)transactions {
    skusToTrack = [NSMutableDictionary new];
    id skPayment;
    
    for (id transaction in transactions) {
        NSInteger state = [transaction performSelector:@selector(transactionState)];
        switch (state) {
            case 1: // SKPaymentTransactionStatePurchased
                skPayment = [transaction performSelector:@selector(payment)];
                NSString* sku = [skPayment performSelector:@selector(productIdentifier)];
                NSInteger quantity = [skPayment performSelector:@selector(quantity)];
                
                if (skusToTrack[sku])
                    [skusToTrack[sku] setObject:[NSNumber numberWithInt:[skusToTrack[sku][@"count"] intValue] + quantity] forKey:@"count"];
                else
                    skusToTrack[sku] = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:quantity], @"count", nil];
                break;
        }
    }
    
    if (skusToTrack.count > 0)
        [self getProductInfo:[skusToTrack allKeys]];
}


- (void)getProductInfo:(NSArray*)productIdentifiers {
    Class SKProductsRequestClass = NSClassFromString(@"SKProductsRequest");
    id productsRequest = [[SKProductsRequestClass alloc]
                            performSelector:@selector(initWithProductIdentifiers:) withObject:[NSSet setWithArray:productIdentifiers]];
    [productsRequest setDelegate:self];
    [productsRequest start];
}

- (void)productsRequest:(id)request didReceiveResponse:(id)response {
    NSMutableArray* arrayOfPruchases = [NSMutableArray new];
    
    for(id skProduct in [response performSelector:@selector(products)]) {
        NSString* productSku = [skProduct performSelector:@selector(productIdentifier)];
        NSMutableDictionary* purchase = skusToTrack[productSku];
        purchase[@"sku"] = productSku;
        purchase[@"amount"] = [skProduct performSelector:@selector(price)];
        purchase[@"iso"] = [[skProduct performSelector:@selector(priceLocale)] objectForKey:NSLocaleCurrencyCode];
        if ([purchase[@"count"] intValue] == 1)
             [purchase removeObjectForKey:@"count"];
        [arrayOfPruchases addObject:purchase];
    }
    
    [[GameThrive defaultClient] performSelector:@selector(sendPurchases:) withObject:arrayOfPruchases];
}


@end