#include <mach/mach.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>

static int cpu(host_cpu_load_info_data_t *value) {
  mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
  return host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO,
                         (host_info_t)value, &count) == KERN_SUCCESS;
}

// Driver-provided utilization; unavailable statistics must not appear as zero.
static double gpu(void) {
  io_iterator_t iterator;
  if (IOServiceGetMatchingServices(kIOMainPortDefault,
      IOServiceMatching("IOAccelerator"), &iterator) != KERN_SUCCESS) return -1;
  double usage = -1;
  io_object_t service;
  while ((service = IOIteratorNext(iterator))) {
    CFTypeRef stats = IORegistryEntryCreateCFProperty(service,
      CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
    if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
      CFTypeRef value = CFDictionaryGetValue((CFDictionaryRef)stats,
        CFSTR("Device Utilization %"));
      double sample;
      if (value && CFGetTypeID(value) == CFNumberGetTypeID() &&
          CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &sample) &&
          sample >= 0 && sample <= 100 && sample > usage) usage = sample;
    }
    if (stats) CFRelease(stats);
    IOObjectRelease(service);
  }
  IOObjectRelease(iterator);
  return usage;
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
  if (!total) return 1;
  printf("%.0f ", 100.0 * (total - idle) / total);
  double graphics = gpu();
  if (graphics < 0) puts("-");
  else printf("%.0f\n", graphics);
  return 0;
}
