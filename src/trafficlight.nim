import picostdlib/[gpio, time]
import std/[strformat]
import async/[fibers]
import io/[register, sevenseg]


type
  TrafficLights = enum
    nsGreen, nsYellow, nsRed,
    ewGreen, ewYellow, ewRed
  TrafficState = set[TrafficLights]
  SevenSegState = object
    register: ShiftRegister
    currentValue: uint

proc newCrossing(seconds: int): FiberIterator =
  iterator(): FiberYield =
    for x in 0..<seconds:
      for y in 0..<4:
        DefaultLedPin.put(on)
        yield yieldTimeMS(100)
        DefaultLedPin.put(off)
        yield yieldTimeMS(100)
      yield yieldTimeMS(200)
      DefaultLedPin.put(off)

proc newUrbanTrafficLightTest(): FiberIterator =
  var sr = ShiftRegister(input: Gpio(2), serial_clk: Gpio(3), out_buffer_clk: Gpio(4))
  sr.init()

  iterator(): FiberYield =
    while true:
      sr.output = cast[byte]({nsGreen, ewRed})
      yield yieldTimeMS(5000)
      sr.output = cast[byte]({nsYellow, ewRed})
      yield yieldTimeMS(2000)
      sr.output = cast[byte]({nsRed, ewGreen})
      yield yieldTimeMS(5000)
      sr.output = cast[byte]({nsRed, ewYellow})
      yield yieldTimeMS(2000)

proc ledtest(): FiberIterator =
  var sr = ShiftRegister(input: Gpio(2), serial_clk: Gpio(3), out_buffer_clk: Gpio(5))
  sr.init()

  iterator(): FiberYield =
    while true:
      for i in 0..9:
        sr.output = byte(SEGMENT_LOOKUP[i])
        yield yieldTimeMS(1000)

var segState = SevenSegState(
  register: ShiftRegister(input: Gpio(2), serial_clk: Gpio(3), out_buffer_clk: Gpio(5)),
  currentValue: 0
)
proc sevenSegDaemon(): FiberIterator =
  iterator(): FiberYield =
    while true:
      let vals = getSegments(segState.currentValue, 2)
      segState.register.output = vals[0]
      yield yieldTimeUS(200)
      segState.register.output = vals[1] or 0b10000000    # Second display
      yield yieldTimeUS(200)

proc sevenSegInc(): FiberIterator =
  iterator(): FiberYield =
    while true:
      segState.currentValue.inc
      yield yieldTimeMS(1000)

proc main() =
  ## Initialize pins
  segState.register.init()
  addFiber(sevenSegDaemon())
  addFiber(newUrbanTrafficLightTest())
  addFiber(sevenSegInc())
  # addFiber(newMemInfo())
  while true:
    runFibers()

when isMainModule:
  main()