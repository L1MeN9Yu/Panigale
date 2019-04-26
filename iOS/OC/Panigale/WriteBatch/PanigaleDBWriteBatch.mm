//
// Created by Mengyu Li on 2017/2/24.
// Copyright © 2019 L1MeN9Yu. All rights reserved.
//

#import <leveldb/write_batch.h>
#import "PanigaleDBWriteBatch.h"
#import "PanigaleMacros.h"
#import "PanigaleDB.h"

@interface PanigaleDBWriteBatch () {
    leveldb::WriteBatch _writeBatch;
    __weak id _db;
}

@property(readonly) leveldb::WriteBatch writeBatch;
@property(nonatomic) dispatch_queue_t levelDBWriteBatchQueue;

@end

@implementation PanigaleDBWriteBatch

+ (instancetype)writeBatchFromDB:(id)db {
    id wb = [[self alloc] init];
    ((PanigaleDBWriteBatch *) wb)->_db = db;
    return wb;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.levelDBWriteBatchQueue = dispatch_queue_create("", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    if (self.levelDBWriteBatchQueue) {
        self.levelDBWriteBatchQueue = nil;
    }
    if (_db) {
        _db = nil;
    }
}

- (void)removeObjectForKey:(id)key {
    AssertKeyType(key);
    leveldb::Slice k = KeyFromStringOrData(key);
    dispatch_sync(self.levelDBWriteBatchQueue, ^{
        self.writeBatch.Delete(k);
    });
}

- (void)removeObjectsForKeys:(NSArray *)keyArray {
    [keyArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [self removeObjectForKey:obj];
    }];
}

- (void)removeAllObjects {
    [_db enumerateKeysUsingBlock:^(LevelDBKey *key, BOOL *stop) {
        [self removeObjectForKey:NSDataFromLevelDBKey(key)];
    }];
}

- (void)setData:(NSData *)data forKey:(id)key {
    AssertKeyType(key);
    dispatch_sync(self.levelDBWriteBatchQueue, ^
    {
        leveldb::Slice lkey = KeyFromStringOrData(key);
        self.writeBatch.Put(lkey, SliceFromData(data));
    });
}

- (void)setObject:(id)value forKey:(id)key {
    AssertKeyType(key);
    dispatch_sync(self.levelDBWriteBatchQueue, ^
    {
        leveldb::Slice k = KeyFromStringOrData(key);
        LevelDBKey lkey = GenericKeyFromSlice(k);

        NSData *data = ((PanigaleDB *) self.db).encoder(&lkey, value);
        leveldb::Slice v = SliceFromData(data);

        self.writeBatch.Put(k, v);
    });
}

- (void)setValue:(id)value forKey:(NSString *)key {
    [self setObject:value forKey:key];
}

- (void)setObject:(id)value forKeyedSubscript:(id)key {
    [self setObject:value forKey:key];
}

- (void)addEntriesFromDictionary:(NSDictionary *)dictionary {
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [self setObject:obj forKey:key];
    }];
}

- (void)apply {
    [_db applyWriteBatch:self];
}
@end
