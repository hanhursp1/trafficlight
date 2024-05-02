# {.compile: "meminfoc.c".}
{.emit: """
#include <inttypes.h>
#include <malloc.h>

uint32_t getTotalHeap() {
  extern char __StackLimit, __bss_end__;
  return &__StackLimit - &__bss_end__;
}

uint32_t getFreeHeap() {
  struct mallinfo m = mallinfo();
  return getTotalHeap() - m.uordblks;
}
""".}

proc getFreeHeap*(): uint32 {.importc, nodecl.}
proc getTotalHeap*(): uint32 {.importc, nodecl.}