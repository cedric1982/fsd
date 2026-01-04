#pragma once

#include <cstddef>
#include <cstring>

// Copies src into dst with guaranteed NUL-termination.
// If src is nullptr, dst becomes an empty string.
inline void safe_strcpy(char* dst, size_t dst_size, const char* src)
{
    if (!dst || dst_size == 0) return;
    if (!src) {
        dst[0] = '\0';
        return;
    }
    std::strncpy(dst, src, dst_size - 1);
    dst[dst_size - 1] = '\0';
}
