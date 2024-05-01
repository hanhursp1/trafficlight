import 
  picostdlib/[gpio, time, stdio],
  std/[strformat],
  async/[fibers],
  io/[register, lcd, input],
  sevenseg, light

var count: uint = 0
proc sevenSegInc(): FiberIterator =
  iterator(): FiberYield =
    while true:
      yield yieldTimeMS(1000)
      count.inc
      setSevenSegValue(count)

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
      lcd[1] = "Hello!"
      yield result
      result = yieldTimeMS(1000)
      lcd.clear()
      lcd[1] = "World!"
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