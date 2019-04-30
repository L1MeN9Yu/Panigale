//
// Created by Mengyu Li on 2017/2/16.
// Copyright © 2019 L1MeN9Yu. All rights reserved.
//

#import "PanigaleDB.h"
#import "PanigaleDBSnapshot.h"
#import "PanigaleDBWriteBatch.h"
#import "PanigaleMacros.h"
#include <leveldb/options.h>
#include <leveldb/filter_policy.h>
#include <leveldb/write_batch.h>
#include <leveldb/db.h>
#include <leveldb/cache.h>

namespace {
    class BatchIterator : public leveldb::WriteBatch::Handler {
    public:
        void (^putCallback)(const leveldb::Slice &key, const leveldb::Slice &value);

        void (^deleteCallback)(const leveldb::Slice &key);

        virtual void Put(const leveldb::Slice &key, const leveldb::Slice &value) {
            putCallback(key, value);
        }

        virtual void Delete(const leveldb::Slice &key) {
            deleteCallback(key);
        }
    };
}

NSString *NSStringFromLevelDBKey(LevelDBKey *key) {
    return [[NSString alloc] initWithBytes:key->data
                                    length:key->length
                                  encoding:NSUTF8StringEncoding];
}

NSData *NSDataFromLevelDBKey(LevelDBKey *key) {
    return [NSData dataWithBytes:key->data length:key->length];
}

NSString *GetLibraryPath() {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    return paths.firstObject;
}

NSString *const kLevelDBChangeType = @"changeType";
NSString *const kLevelDBChangeTypePut = @"put";
NSString *const kLevelDBChangeTypeDelete = @"del";
NSString *const kLevelDBChangeValue = @"value";
NSString *const kLevelDBChangeKey = @"key";

LevelDBOptions MakeLevelDBOptions() {
    return (LevelDBOptions) {true, true, false, false, true, 0, 0};
}

@interface PanigaleDBSnapshot ()
+ (id)snapshotFromDB:(PanigaleDB *)database;

- (const leveldb::Snapshot *)getSnapshot;
@end

@interface PanigaleDBWriteBatch ()
+ (instancetype)writeBatchFromDB:(id)db;

- (leveldb::WriteBatch)writeBatch;
@end

@interface PanigaleDB () {
    leveldb::ReadOptions readOptions;
    leveldb::WriteOptions writeOptions;
    const leveldb::Cache *cache;
    const leveldb::FilterPolicy *filterPolicy;
}

@property (nonatomic) leveldb::DB *db;

@end

@implementation PanigaleDB

+ (LevelDBOptions)makeOptions {
    return MakeLevelDBOptions();
}

- (instancetype)initWithPath:(NSString *)path name:(NSString *)name {
    LevelDBOptions opts = MakeLevelDBOptions();
    return [self initWithPath:path name:name options:opts];
}

- (instancetype)initWithPath:(NSString *)path name:(NSString *)name options:(LevelDBOptions)options {
    if (self = [super init]) {
        _name = [name copy];
        _path = [path copy];

        leveldb::Options leveldb_options;

        leveldb_options.create_if_missing = options.createIfMissing;
        leveldb_options.paranoid_checks = options.paranoidCheck;
        leveldb_options.error_if_exists = options.errorIfExists;

        if (!leveldb_options.compression)
            leveldb_options.compression = leveldb::kNoCompression;

        if (options.cacheSize > 0) {
            leveldb_options.block_cache = leveldb::NewLRUCache(options.cacheSize);
            cache = leveldb_options.block_cache;
        } else
            readOptions.fill_cache = false;

        if (options.createIntermediateDirectories) {
            NSString *dirPath = [path stringByDeletingLastPathComponent];
            NSFileManager *fm = [NSFileManager defaultManager];
            NSError *crError;

            BOOL success = [fm createDirectoryAtPath:dirPath
                         withIntermediateDirectories:true
                                          attributes:nil
                                               error:&crError];
            if (!success) {
                NSLog(@"Problem creating parent directory: %@", crError);
                return nil;
            }
        }

        if (options.filterPolicy > 0) {
            filterPolicy = leveldb::NewBloomFilterPolicy(options.filterPolicy);;
            leveldb_options.filter_policy = filterPolicy;
        }
        leveldb::Status status = leveldb::DB::Open(leveldb_options, [_path UTF8String], &_db);

        readOptions.fill_cache = true;
        writeOptions.sync = false;

        if (!status.ok()) {
            NSLog(@"Problem creating LevelDB database: %s", status.ToString().c_str());
            return nil;
        }

        self.encoder = ^NSData *(LevelDBKey *key, id object) {
#ifdef DEBUG
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                NSLog(@"No encoder block was set for this database [%@]", name);
                NSLog(@"Using a convenience encoder/decoder pair using NSKeyedArchiver.");
            });
#endif
            return [NSKeyedArchiver archivedDataWithRootObject:object];
        };
        self.decoder = ^id(LevelDBKey *key, NSData *data) {
            return [NSKeyedUnarchiver unarchiveObjectWithData:data];
        };
    }

    return self;
}

+ (instancetype)databaseInLibraryWithName:(NSString *)name {
    LevelDBOptions options = MakeLevelDBOptions();
    return [self databaseInLibraryWithName:name options:options];
}

+ (instancetype)databaseInLibraryWithName:(NSString *)name options:(LevelDBOptions)options {
    NSString *path = [GetLibraryPath() stringByAppendingPathComponent:name];
    PanigaleDB *levelDBWrapper = [[self alloc] initWithPath:path name:name options:options];
    return levelDBWrapper;
}

- (void)setSafe:(BOOL)safe {
    writeOptions.sync = safe;
}

- (BOOL)useCache {
    return readOptions.fill_cache;
}

- (void)setUseCache:(BOOL)useCache {
    readOptions.fill_cache = useCache;
}

#pragma mark - Setters

- (BOOL)setObject:(id)value forKey:(id)key {
    AssertDBExists(self.db);
    AssertKeyType(key);
    NSParameterAssert(value != nil);

    leveldb::Slice k = KeyFromStringOrData(key);
    LevelDBKey levelDBKey = GenericKeyFromSlice(k);

    NSData *data = _encoder(&levelDBKey, value);
    leveldb::Slice v = SliceFromData(data);

    leveldb::Status status = _db->Put(writeOptions, k, v);

    if (!status.ok()) {
        NSLog(@"Problem storing key/value pair in database: %s", status.ToString().c_str());
        return NO;
    } else {
        return YES;
    }
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

#pragma mark - Write batches

- (PanigaleDBWriteBatch *)newWriteBatch {
    return [PanigaleDBWriteBatch writeBatchFromDB:self];
}

- (void)applyWriteBatch:(PanigaleDBWriteBatch *)writeBatch {
    leveldb::WriteBatch wb = [writeBatch writeBatch];
    leveldb::Status status = _db->Write(writeOptions, &wb);
    if (!status.ok()) {
        NSLog(@"Problem applying the write batch in database: %s", status.ToString().c_str());
    }
}

- (void)performWriteBatch:(void (^)(PanigaleDBWriteBatch *wb))block {
    PanigaleDBWriteBatch *writeBatch = [self newWriteBatch];
    block(writeBatch);
    [writeBatch apply];
}

#pragma mark - Getters

- (id)objectForKey:(id)key {
    return [self objectForKey:key withSnapshot:nil];
}

- (id)objectForKey:(id)key
      withSnapshot:(PanigaleDBSnapshot *)snapshot {
    AssertDBExists(self.db);
    AssertKeyType(key);
    std::string v_string;
    MaybeAddSnapshotToOptions(readOptions, readOptionsPtr, snapshot);
    leveldb::Slice k = KeyFromStringOrData(key);
    leveldb::Status status = _db->Get(*readOptionsPtr, k, &v_string);

    if (!status.ok()) {
        if (!status.IsNotFound())
            NSLog(@"Problem retrieving value for key '%@' from database: %s", key, status.ToString().c_str());
        return nil;
    }

    LevelDBKey lkey = GenericKeyFromSlice(k);
    return DecodeFromSlice(v_string, &lkey, _decoder);
}

- (id)objectsForKeys:(NSArray *)keys notFoundMarker:(id)marker {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:keys.count];
    [keys enumerateObjectsUsingBlock:^(id objId, NSUInteger idx, BOOL *stop) {
        id object = [self objectForKey:objId];
        if (object == nil) object = marker;
        result[idx] = object;
    }];
    return [NSArray arrayWithArray:result];
}

- (id)valueForKey:(NSString *)key {
    if ([key characterAtIndex:0] == '@') {
        return [super valueForKey:[key stringByReplacingCharactersInRange:(NSRange) {0, 1}
                                                               withString:@""]];
    } else
        return [self objectForKey:key];
}

- (id)objectForKeyedSubscript:(id)key {
    return [self objectForKey:key withSnapshot:nil];
}

- (BOOL)objectExistsForKey:(id)key {
    return [self objectExistsForKey:key withSnapshot:nil];
}

- (BOOL)objectExistsForKey:(id)key
              withSnapshot:(PanigaleDBSnapshot *)snapshot {
    AssertDBExists(self.db);
    AssertKeyType(key);
    std::string v_string;
    MaybeAddSnapshotToOptions(readOptions, readOptionsPtr, snapshot);
    leveldb::Slice k = KeyFromStringOrData(key);
    leveldb::Status status = _db->Get(*readOptionsPtr, k, &v_string);

    if (!status.ok()) {
        if (status.IsNotFound())
            return false;
        else {
            NSLog(@"Problem retrieving value for key '%@' from database: %s", key, status.ToString().c_str());
            return NULL;
        }
    } else {
        return true;
    }
}

#pragma mark - Removers

- (BOOL)removeObjectForKey:(id)key {
    AssertDBExists(self.db);
    AssertKeyType(key);

    leveldb::Slice k = KeyFromStringOrData(key);
    leveldb::Status status = _db->Delete(writeOptions, k);

    if (!status.ok()) {
        NSLog(@"Problem deleting key/value pair in database: %s", status.ToString().c_str());
        return NO;
    } else {
        return YES;
    }
}

- (void)removeObjectsForKeys:(NSArray *)keyArray {
    [keyArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [self removeObjectForKey:obj];
    }];
}

- (void)removeAllObjects {
    [self removeAllObjectsWithPrefix:nil];
}

- (void)removeAllObjectsWithPrefix:(id)prefix {
    AssertDBExists(self.db);

    leveldb::Iterator *iter = _db->NewIterator(readOptions);
    leveldb::Slice lkey;

    const void *prefixPtr;
    size_t prefixLen = 0;
    prefix = EnsureNSData(prefix);
    if (prefix) {
        prefixPtr = [(NSData *) prefix bytes];
        prefixLen = (size_t) [(NSData *) prefix length];
    }

    for (SeekToFirstOrKey(iter, (id) prefix, NO); iter->Valid(); MoveCursor(iter, NO)) {

        lkey = iter->key();
        if (prefix && memcmp(lkey.data(), prefixPtr, MIN(prefixLen, lkey.size())) != 0)
            break;

        _db->Delete(writeOptions, lkey);
    }
    delete iter;
}

#pragma mark - Selection

- (NSArray *)allKeys {
    NSMutableArray *keys = [[NSMutableArray alloc] init];
    [self enumerateKeysUsingBlock:^(LevelDBKey *key, BOOL *stop) {
        [keys addObject:NSDataFromLevelDBKey(key)];
    }];
    return [NSArray arrayWithArray:keys];
}

- (NSArray *)keysByFilteringWithPredicate:(NSPredicate *)predicate {
    NSMutableArray *keys = [[NSMutableArray alloc] init];
    [self enumerateKeysAndObjectsBackward:NO lazily:NO
                            startingAtKey:nil
                      filteredByPredicate:predicate
                                andPrefix:nil
                             withSnapshot:nil
                               usingBlock:^(LevelDBKey *key, id obj, BOOL *stop) {
                                   [keys addObject:NSDataFromLevelDBKey(key)];
                               }];
    return [NSArray arrayWithArray:keys];
}

- (NSDictionary *)dictionaryByFilteringWithPredicate:(NSPredicate *)predicate {
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    [self enumerateKeysAndObjectsBackward:NO
                                   lazily:NO
                            startingAtKey:nil
                      filteredByPredicate:predicate
                                andPrefix:nil
                             withSnapshot:nil
                               usingBlock:^(LevelDBKey *key, id obj, BOOL *stop) {
                                   results[NSDataFromLevelDBKey(key)] = obj;
                               }];

    return [NSDictionary dictionaryWithDictionary:results];
}

- (PanigaleDBSnapshot *)newSnapshot {
    return [PanigaleDBSnapshot snapshotFromDB:self];
}

#pragma mark - Enumeration

- (void)_startIterator:(leveldb::Iterator *)iter
              backward:(BOOL)backward
                prefix:(id)prefix
                 start:(id)key {

    const void *prefixPtr;
    size_t prefixLen;
    leveldb::Slice lkey, startingKey;

    prefix = EnsureNSData(prefix);
    if (prefix) {
        prefixPtr = [(NSData *) prefix bytes];
        prefixLen = (size_t) [(NSData *) prefix length];
        startingKey = leveldb::Slice((char *) prefixPtr, prefixLen);

        if (key) {
            leveldb::Slice skey = KeyFromStringOrData(key);
            if (skey.size() > prefixLen && memcmp(skey.data(), prefixPtr, prefixLen) == 0) {
                startingKey = skey;
            }
        }

        /*
         * If a prefix is provided and the iteration is backwards
         * we need to start on the next key (maybe discarding the first iteration)
         */
        if (backward) {
            signed long long i = startingKey.size() - 1;
            void *startingKeyPtr = malloc(startingKey.size());
            unsigned char *keyChar;
            memcpy(startingKeyPtr, startingKey.data(), startingKey.size());
            while (1) {
                if (i < 0) {
                    iter->SeekToLast();
                    break;
                }
                keyChar = (unsigned char *) startingKeyPtr + i;
                if (*keyChar < 255) {
                    *keyChar = *keyChar + 1;
                    iter->Seek(leveldb::Slice((char *) startingKeyPtr, startingKey.size()));
                    if (!iter->Valid()) {
                        iter->SeekToLast();
                    }
                    break;
                }
                i--;
            };
            free(startingKeyPtr);
            if (!iter->Valid())
                return;

            lkey = iter->key();
            if (startingKey.size()) {
                signed int cmp = memcmp(lkey.data(), startingKey.data(), startingKey.size());
                if (cmp > 0) {
                    iter->Prev();
                }
            }
        } else {
            // Otherwise, we start at the provided prefix
            iter->Seek(startingKey);
        }
    } else if (key) {
        iter->Seek(KeyFromStringOrData(key));
    } else if (backward) {
        iter->SeekToLast();
    } else {
        iter->SeekToFirst();
    }
}

- (void)enumerateKeysUsingBlock:(LevelDBKeyBlock)block {

    [self enumerateKeysBackward:FALSE
                  startingAtKey:nil
            filteredByPredicate:nil
                      andPrefix:nil
                   withSnapshot:nil
                     usingBlock:block];
}

- (void)enumerateKeysBackward:(BOOL)backward
                startingAtKey:(id)key
          filteredByPredicate:(NSPredicate *)predicate
                    andPrefix:(id)prefix
                   usingBlock:(LevelDBKeyBlock)block {

    [self enumerateKeysBackward:backward
                  startingAtKey:key
            filteredByPredicate:predicate
                      andPrefix:prefix
                   withSnapshot:nil
                     usingBlock:block];
}

- (void)enumerateKeysBackward:(BOOL)backward
                startingAtKey:(id)key
          filteredByPredicate:(NSPredicate *)predicate
                    andPrefix:(id)prefix
                 withSnapshot:(PanigaleDBSnapshot *)snapshot
                   usingBlock:(LevelDBKeyBlock)block {

    AssertDBExists(self.db);
    MaybeAddSnapshotToOptions(readOptions, readOptionsPtr, snapshot);
    leveldb::Iterator *iter = _db->NewIterator(*readOptionsPtr);
    leveldb::Slice lkey;
    BOOL stop = false;

    NSData *prefixData = EnsureNSData(prefix);

    LevelDBKeyValueBlock iterate = (predicate != nil)
            ? ^(LevelDBKey *lk, id value, BOOL *stop) {
                if ([predicate evaluateWithObject:value])
                    block(lk, stop);
            }
            : ^(LevelDBKey *lk, id value, BOOL *stop) {
                block(lk, stop);
            };

    for ([self _startIterator:iter backward:backward prefix:prefix start:key]; iter->Valid(); MoveCursor(iter, backward)) {

        lkey = iter->key();
        if (prefix && memcmp(lkey.data(), [prefixData bytes], MIN((size_t) [prefixData length], lkey.size())) != 0)
            break;

        LevelDBKey lk = GenericKeyFromSlice(lkey);
        id v = (predicate == nil) ? nil : DecodeFromSlice(iter->value(), &lk, _decoder);
        iterate(&lk, v, &stop);
        if (stop) break;
    }

    delete iter;
}

- (void)enumerateKeysAndObjectsUsingBlock:(LevelDBKeyValueBlock)block {
    [self enumerateKeysAndObjectsBackward:FALSE
                                   lazily:FALSE
                            startingAtKey:nil
                      filteredByPredicate:nil
                                andPrefix:nil
                             withSnapshot:nil
                               usingBlock:block];
}

- (void)enumerateKeysAndObjectsBackward:(BOOL)backward
                                 lazily:(BOOL)lazily
                          startingAtKey:(id)key
                    filteredByPredicate:(NSPredicate *)predicate
                              andPrefix:(id)prefix
                             usingBlock:(id)block {

    [self enumerateKeysAndObjectsBackward:backward
                                   lazily:lazily
                            startingAtKey:key
                      filteredByPredicate:predicate
                                andPrefix:prefix
                             withSnapshot:nil
                               usingBlock:block];
}

- (void)enumerateKeysAndObjectsBackward:(BOOL)backward
                                 lazily:(BOOL)lazily
                          startingAtKey:(id)key
                    filteredByPredicate:(NSPredicate *)predicate
                              andPrefix:(id)prefix
                           withSnapshot:(PanigaleDBSnapshot *)snapshot
                             usingBlock:(id)block {

    AssertDBExists(self.db);
    MaybeAddSnapshotToOptions(readOptions, readOptionsPtr, snapshot);
    leveldb::Iterator *iter = _db->NewIterator(*readOptionsPtr);
    leveldb::Slice lkey;
    BOOL stop = false;

    LevelDBLazyKeyValueBlock iterate = (predicate != nil)

            // If there is a predicate:
            ? ^(LevelDBKey *lk, LevelDBValueGetterBlock valueGetter, BOOL *stop) {
                // We need to get the value, whether the `lazily` flag was set or not
                id value = valueGetter();

                // If the predicate yields positive, we call the block
                if ([predicate evaluateWithObject:value]) {
                    if (lazily)
                        ((LevelDBLazyKeyValueBlock) block)(lk, valueGetter, stop);
                    else
                        ((LevelDBKeyValueBlock) block)(lk, value, stop);
                }
            }

            // Otherwise, we call the block
            : ^(LevelDBKey *lk, LevelDBValueGetterBlock valueGetter, BOOL *stop) {
                if (lazily)
                    ((LevelDBLazyKeyValueBlock) block)(lk, valueGetter, stop);
                else
                    ((LevelDBKeyValueBlock) block)(lk, valueGetter(), stop);
            };

    NSData *prefixData = EnsureNSData(prefix);

    LevelDBValueGetterBlock getter;
    for ([self _startIterator:iter backward:backward prefix:prefix start:key]; iter->Valid(); MoveCursor(iter, backward)) {

        lkey = iter->key();
        // If there is prefix provided, and the prefix and key don't match, we break out of iteration
        if (prefix && memcmp(lkey.data(), [prefixData bytes], MIN((size_t) [prefixData length], lkey.size())) != 0)
            break;

        __block LevelDBKey lk = GenericKeyFromSlice(lkey);
        __block id v = nil;

        getter = ^id {
            if (v) return v;
            v = DecodeFromSlice(iter->value(), &lk, self.decoder);
            return v;
        };

        iterate(&lk, getter, &stop);
        if (stop) break;
    }

    delete iter;
}

#pragma mark - Bookkeeping

- (void)deleteDatabaseFromDisk {
    [self close];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    [fileManager removeItemAtPath:_path error:&error];
}

- (void)close {
    @synchronized (self) {
        if (_db) {
            delete _db;

            if (cache)
                delete cache;

            if (filterPolicy)
                delete filterPolicy;

            _db = NULL;
        }
    }
}

- (BOOL)closed {
    return _db == NULL;
}

- (void)dealloc {
    [self close];
}

@end
