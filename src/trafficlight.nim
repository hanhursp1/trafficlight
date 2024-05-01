import 
  picostdlib/[gpio, time, stdio],
  std/[strformat],
  async/[fibers],
  io/[register, sevenseg, lcd, input]


type
  TrafficLights = enum
    nsGreen, nsYellow, nsRed,
    ewGreen, ewYellow, ewRed
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

var segState = SevenSegState(
  register: ShiftRegister(input: Gpio(2), serial_clk: Gpio(3), out_buffer_clk: Gpio(5)),
  currentValue: 0
)
proc sevenSegDaemon(): FiberIterator =
  segState.register.init()
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
      yield yieldTimeMS(1000)
      segState.currentValue.inc

proc lcdtest(): FiberIterator =
  var lcd = LCDisplay(
    register: ShiftRegister(
      input: Gpio(2), serial_clk: Gpio(3), out_buffer_clk: Gpio(6)
    ),
    enablePin: Gpio(7),
    settings: LCDSettings(
      cursor: false,
      blinking: false
    )
  )
  lcd.init()
  iterator(): FiberYield =
    while true:
      result = yieldTimeMS(1000)
      lcd.clear()
      lcd.writeLine("Hello!", LCDLine.LineOne)
      yield result
      result = yieldTimeMS(1000)
      lcd.clear()
      lcd.writeLine("World!", LCDLine.LineTwo)
      yield result
      


proc main() =
  ## Main function
  addFiber(sevenSegDaemon())
  addFiber(newUrbanTrafficLightTest())
  addFiber(sevenSegInc())
  addFiber(lcdtest())
  # addFiber(newMemInfo())
  while true:
    checkInputs()
    runFibers()

when isMainModule:
  stdioInitAll()
  sleep(100)
  try:
    main()
  except Exception as e:
    echo "An exception occurred: "
    echo e[]