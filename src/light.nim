import
  picostdlib/[gpio],
  async/[fibers],
  io/[register]

type
  CrossingMode = enum
    Rural, Urban
  TrafficLights = enum
    nsGreen, nsYellow, nsRed,
    ewGreen, ewYellow, ewRed
  CrossingConfig = object
    mode: CrossingMode
    greenLightDelay: uint
    yellowLightDelay: uint

proc newUrbanTrafficLightTest*(): FiberIterator =
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