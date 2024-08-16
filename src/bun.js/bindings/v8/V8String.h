#pragma once

#include "v8.h"
#include "V8Primitive.h"
#include "V8MaybeLocal.h"
#include "V8Isolate.h"

namespace v8 {

enum class NewStringType {
    kNormal,
    kInternalized,
};

class String : Primitive {
public:
    enum WriteOptions {
        NO_OPTIONS = 0,
        HINT_MANY_WRITES_EXPECTED = 1,
        NO_NULL_TERMINATION = 2,
        PRESERVE_ONE_BYTE_NULL = 4,
        REPLACE_INVALID_UTF8 = 8,
    };

    BUN_EXPORT static MaybeLocal<String> NewFromUtf8(Isolate* isolate, char const* data, NewStringType type, int length = -1);
    BUN_EXPORT static MaybeLocal<String> NewFromOneByte(Isolate* isolate, const uint8_t* data, NewStringType type, int length);
    BUN_EXPORT int WriteUtf8(Isolate* isolate, char* buffer, int length = -1, int* nchars_ref = nullptr, int options = NO_OPTIONS) const;
    BUN_EXPORT int Length() const;

    JSC::JSString* localToJSString()
    {
        return localToObjectPointer<JSC::JSString>();
    }
};

}
