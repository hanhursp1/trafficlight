
import
  picostdlib/[gpio],
  io/[register],
  async/[fibers]

const SEGMENT_LOOKUP = [
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


# A `static[int]` type indicates an integer variable whose value is only known at
# compile time. This is essentially a generic.
# This could be rewritten as
# `proc getSegments[L: static[int]](num: SomeUnsignedInt): array[L, byte]`
# However, sometimes having a static/typedesc as an explicit argument is useful.
proc getSegments(num: SomeUnsignedInt, L: static[int]): array[L, byte] =
  ## Splits up `i` into an `L` length array of segments
  var num = num   # Shadow the input to make it mutable
  for i in 0..<L:
    result[i] = byte(SEGMENT_LOOKUP[num mod 10])
    num = num div 10

var reg = ShiftRegister(input: Gpio(2), serial_clk: Gpio(3), out_buffer_clk: Gpio(5))
var currentValue: uint = 0

proc setSevenSegValue*(val: uint) =
  ## Set the value of the seven-segment display
  currentValue = val

proc sevenSegDaemon*(): FiberIterator =
  ## Coroutine to display the seven-segment display.
  ## Runs as its own process to allow for multiple digits to
  ## be output.
  ## 
  ## Which segment is displayed is controlled by bit 8
  reg.init()
  iterator(): FiberYield =
    while true:
      let vals = getSegments(currentValue, 2)
      reg.output = vals[0]                  # First display (bit8 = 0)
      yield waitUS(200)
      reg.output = vals[1] or 0b10000000    # Second display (bit8 = 1)
      yield waitUS(200)