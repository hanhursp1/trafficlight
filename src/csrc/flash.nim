const
  FLASH_PAGE_SIZE*    = (1.shl 8)
  FLASH_SECTOR_SIZE*  = (1.shl 12)
  FLASH_BLOCK_SIZE*   = (1.shl 16)

  XIP_BASE* = 0x10000000

{.push header:"\"hardware/flash.h\"".}
proc flash_range_erase*(flash_offs: uint32, count: csize_t) {.importc.}
proc flash_range_program*(flash_offs: uint32, data: openArray[byte]) {.importc.}
proc flash_range_program*(flash_offs: uint32, data: ptr byte, count: csize_t) {.importc.}
proc flash_get_unique_id*(id_out: ptr byte) {.importc.}
proc flash_do_cmd*(txbuf: ptr byte; rxbuf: ptr byte; count: csize_t) {.importc.}
{.pop.}