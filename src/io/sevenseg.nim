import picostdlib/[gpio, time]

const SEGMENT_LOOKUP* = [
  0b00111111,       # 0
  0b00000110,       # 1
  0b01011011,       # 2
  0b01001111,       # 3
  0b01100110,       # 4
  0b01101101,       # 5
  0b01111101,       # 6
  0b00000111,       # 7
  0b01111111,       # 8
  0b01101111        # 9
]

proc getSegments*(num: SomeUnsignedInt, L: static[int]): array[L, byte] =
  ## Splits up `i` into an `L` length array of segments
  var num = num   # Shadow the input to make it mutable
  for i in 0..<L:
    result[i] = byte(SEGMENT_LOOKUP[num mod 10])
    num = num div 10