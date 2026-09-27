#include <mach/mach.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>

static int cpu(host_cpu_load_info_data_t *value) {
  mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
  return host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO,
                         (host_info_t)value, &count) == KERN_SUCCESS;
}

int main(void) {
  host_cpu_load_info_data_t before, after;
  if (!cpu(&before)) return 1;
  usleep(250000);
  if (!cpu(&after)) return 1;
  uint64_t total = 0, idle = 0;
  for (int i = 0; i < CPU_STATE_MAX; i++) {
    uint32_t delta = after.cpu_ticks[i] - before.cpu_ticks[i];
    total += delta;
    if (i == CPU_STATE_IDLE) idle = delta;
  }
  vm_statistics64_data_t vm;
  mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
  uint64_t memory = 0;
  size_t length = sizeof(memory);
  if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
                        (host_info64_t)&vm, &count) != KERN_SUCCESS ||
      sysctlbyname("hw.memsize", &memory, &length, NULL, 0) || !memory || !total)
    return 1;
  // App memory (excluding purgeable pages), wired memory and compressed memory.
  uint64_t app = vm.internal_page_count > vm.purgeable_count
    ? vm.internal_page_count - vm.purgeable_count : 0;
  uint64_t used = (app + vm.wire_count + vm.compressor_page_count) * vm_kernel_page_size;
  printf("%.0f %.0f\n", 100.0 * (total - idle) / total, 100.0 * used / memory);
  return 0;
}
