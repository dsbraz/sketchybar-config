#include "NativeBridge.h"
#include <mach/mach.h>
#include <servers/bootstrap.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

// SketchyBar's public helper protocol: one out-of-line Mach descriptor.
struct Packet { mach_msg_header_t header; mach_msg_body_t body; mach_msg_ool_descriptor_t data; };
struct Receive { struct Packet packet; mach_msg_max_trailer_t trailer; };
static bool valid(struct Packet *p) {
    return (p->header.msgh_bits & MACH_MSGH_BITS_COMPLEX) &&
        p->body.msgh_descriptor_count == 1 && p->data.type == MACH_MSG_OOL_DESCRIPTOR &&
        p->data.address && p->data.size > 0 && p->data.size <= 4 * 1024 * 1024;
}
char *sb_request(const char *bytes, size_t length) {
    if (!bytes || !length || length > 4 * 1024 * 1024) return NULL;
    mach_port_t destination = MACH_PORT_NULL, reply = MACH_PORT_NULL;
    // Resolve every time: stale ports must not survive a bar restart.
    if (bootstrap_look_up(bootstrap_port, "git.felix.sketchybar", &destination) != KERN_SUCCESS) return NULL;
    if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &reply) != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), destination); return NULL;
    }
    struct Packet request = {0};
    request.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND) | MACH_MSGH_BITS_COMPLEX;
    request.header.msgh_remote_port = destination;
    request.header.msgh_local_port = reply;
    request.header.msgh_id = reply;
    request.header.msgh_size = sizeof(request);
    request.body.msgh_descriptor_count = 1;
    request.data.address = (void *)bytes;
    request.data.size = (mach_msg_size_t)length;
    request.data.copy = MACH_MSG_VIRTUAL_COPY;
    request.data.type = MACH_MSG_OOL_DESCRIPTOR;
    char *result = NULL;
    if (mach_msg(&request.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof(request), 0,
                 MACH_PORT_NULL, 100, MACH_PORT_NULL) == MACH_MSG_SUCCESS) {
        struct Receive response = {0};
        if (mach_msg(&response.packet.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof(response),
                     reply, 200, MACH_PORT_NULL) == MACH_MSG_SUCCESS) {
            if (valid(&response.packet)) {
                size_t n = strnlen(response.packet.data.address, response.packet.data.size);
                result = malloc(n + 1);
                if (result) { memcpy(result, response.packet.data.address, n); result[n] = 0; }
            }
            mach_msg_destroy(&response.packet.header);
        }
    }
    mach_port_mod_refs(mach_task_self(), reply, MACH_PORT_RIGHT_RECEIVE, -1);
    mach_port_deallocate(mach_task_self(), destination);
    return result;
}
static sb_event_callback event_callback;
static CFMachPortRef event_port;
static void receive_event(CFMachPortRef port, void *message, CFIndex size, void *context) {
    struct Packet *p = message;
    if (size >= sizeof(*p) && valid(p) && event_callback) event_callback(p->data.address, p->data.size);
    mach_msg_destroy(&p->header);
}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
bool sb_listen(const char *name, sb_event_callback callback) {
    mach_port_t port;
    if (event_port || mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port) != KERN_SUCCESS) return false;
    if (mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS ||
        bootstrap_register(bootstrap_port, (char *)name, port) != KERN_SUCCESS) {
        mach_port_destroy(mach_task_self(), port); return false;
    }
    event_callback = callback;
    CFMachPortContext context = {0};
    event_port = CFMachPortCreateWithPort(NULL, port, receive_event, &context, NULL);
    if (!event_port) { mach_port_destroy(mach_task_self(), port); return false; }
    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, event_port, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);
    return true;
}
#pragma clang diagnostic pop
CFArrayRef sb_copy_spaces(void) {
    static void *library;
    if (!library) library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
    if (!library) return NULL;
    int (*connection)(void) = dlsym(library, "SLSMainConnectionID");
    CFArrayRef (*copy)(int) = dlsym(library, "SLSCopyManagedDisplaySpaces");
    if (!connection || !copy) return NULL;
    return copy(connection());
}
