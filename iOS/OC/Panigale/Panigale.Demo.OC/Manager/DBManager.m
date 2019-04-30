//
// Created by Mengyu Li on 2019-04-30.
// Copyright (c) 2019 L1MeN9Yu. All rights reserved.
//

#import "DBManager.h"
#import <Panigale/Panigale.h>


@interface DBManager ()

@property (nonatomic, strong) PanigaleDB *db;
@end

@implementation DBManager
+ (instancetype)sharedInstance {
    static DBManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });

    return sharedInstance;
}

- (void)setString:(NSString *)string forKey:(NSString *)key {
    [self.db setObject:string forKey:key];
}

- (NSString *)stringForKey:(NSString *)key {
    id value = [self.db objectForKey:key];
    if ([value isKindOfClass:[NSString class]]) {
        return (NSString *) value;
    }
    return nil;
}


- (PanigaleDB *)db {
    if (!_db) {
        _db = [[PanigaleDB alloc] initWithPath:NSSearchPathForDirectoriesInDomains(NSDocumentationDirectory, NSUserDomainMask, YES).firstObject andName:@"panigale"];
    }
    return _db;
}

@end