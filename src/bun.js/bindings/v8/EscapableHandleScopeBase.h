#pragma once

#include "v8.h"
#include "v8/HandleScope.h"
#include "v8/Isolate.h"

namespace v8 {

class EscapableHandleScopeBase : public HandleScope {
public:
    BUN_EXPORT EscapableHandleScopeBase(Isolate* isolate);

protected:
    BUN_EXPORT uintptr_t* EscapeSlot(uintptr_t* escape_value);

private:
    Handle* escape_slot;
};

}
