//
//  PanigaleMacros.h
//  Panigale
//
//  Created by Mengyu Li on 2019/4/25.
//  Copyright © 2019 L1MeN9Yu. All rights reserved.
//

#define AssertDBExists(_db_) \
    NSAssert(_db_ != NULL, @"Database reference is not existent (it has probably been closed)");

#define AssertKeyType(_key_)\
    NSParameterAssert([_key_ isKindOfClass:[NSString class]] || [_key_ isKindOfClass:[NSData class]])

#define KeyFromStringOrData(_key_)\
          ([_key_ isKindOfClass:[NSString class]]) ? SliceFromString(_key_) : SliceFromData(_key_)

#define SliceFromString(_string_)\
           leveldb::Slice((char *)[_string_ UTF8String], [_string_ lengthOfBytesUsingEncoding:NSUTF8StringEncoding])

#define StringFromSlice(_slice_)\
            [[NSString alloc] initWithBytes:_slice_.data() length:_slice_.size() encoding:NSUTF8StringEncoding]

#define SliceFromData(_data_)\
               leveldb::Slice((char *)[_data_ bytes], [_data_ length])

#define DataFromSlice(_slice_)\
              [NSData dataWithBytes:_slice_.data() length:_slice_.size()]

#define DecodeFromSlice(_slice_, _key_, _d) _d(_key_, DataFromSlice(_slice_))

#define EncodeToSlice(_object_, _key_, _e)  SliceFromData(_e(_key_, _object_))

#define GenericKeyFromSlice(_slice_)\
        (LevelDBKey) { .data = _slice_.data(), .length = _slice_.size() }

#define GenericKeyFromNSDataOrString(_obj_) ([_obj_ isKindOfClass:[NSString class]]) ? \
                                                (LevelDBKey) { \
                                                    .data   = [_obj_ cStringUsingEncoding:NSUTF8StringEncoding], \
                                                    .length = [_obj_ lengthOfBytesUsingEncoding:NSUTF8StringEncoding] \
                                                } \
                                            :   (LevelDBKey) { \
                                                    .data = [_obj_ bytes], \
                                                    .length = [_obj_ length] \
                                                }

#define MaybeAddSnapshotToOptions(_from_, _to_, _snap_) \
    leveldb::ReadOptions __to_;\
    leveldb::ReadOptions * _to_ = &__to_;\
    if (_snap_ != nil) { \
        _to_->fill_cache = _from_.fill_cache; \
        _to_->snapshot = [_snap_ getSnapshot]; \
    } else \
        _to_ = &_from_;

#define SeekToFirstOrKey(iter, key, _backward_) \
    (key != nil) ? iter->Seek(KeyFromStringOrData(key)) : \
    _backward_ ? iter->SeekToLast() : iter->SeekToFirst()

#define MoveCursor(_iter_, _backward_) \
    _backward_ ? iter->Prev() : iter->Next()

#define EnsureNSData(_obj_) \
    ([_obj_ isKindOfClass:[NSData class]]) ? _obj_ : \
    ([_obj_ isKindOfClass:[NSString class]]) ? [NSData dataWithBytes:[_obj_ cStringUsingEncoding:NSUTF8StringEncoding] \
                                                              length:[_obj_ lengthOfBytesUsingEncoding:NSUTF8StringEncoding]] : nil