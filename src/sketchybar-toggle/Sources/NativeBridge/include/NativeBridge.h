#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stddef.h>
// Caller owns the returned response. Arguments are NUL-separated, double-NUL terminated.
char *sb_request(const char *bytes, size_t length);
typedef void (*sb_event_callback)(const char *, size_t);
bool sb_listen(const char *name, sb_event_callback callback);
CFArrayRef sb_copy_spaces(void) CF_RETURNS_RETAINED;
