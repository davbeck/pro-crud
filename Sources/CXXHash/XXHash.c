#define XXH_INLINE_ALL
#include "xxhash.h"
#include "include/CXXHash.h"

uint64_t pro_crud_xxh3_64(const void *data, size_t length) {
    return XXH3_64bits(data, length);
}
