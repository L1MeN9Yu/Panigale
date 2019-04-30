//
// Created by Mengyu Li on 2019-04-30.
// Copyright (c) 2019 L1MeN9Yu. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface DBManager : NSObject
+ (instancetype)sharedInstance;

- (void)setString:(NSString *)string forKey:(NSString *)key;

- (NSString *)stringForKey:(NSString *)key;
@end