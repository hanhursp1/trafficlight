import 
  picostdlib/[gpio, time, stdio],
  std/[strformat],
  async/[fibers],
  csrc/[meminfo],
  io/[register, lcd, input, irq],
  sevenseg, light

# var count: uint = 0
# proc sevenSegInc(): FiberIterator =
#   iterator(): FiberYield =
#     while true:
#       yield waitMS(1000)
#       count.inc
#       setSevenSegValue(count)

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
      result = waitMS(1000)
      lcd.clear()
      lcd[0] = "Hello!"
      yield result
      result = waitMS(1000)
      lcd.clear()
      lcd[1] = "World!"
      yield result

proc inputtest(): FiberIterator =
  DefaultLedPin.init()
  DefaultLedPin.setDir(Out)
  addInput(Gpio(12))
  iterator(): FiberYield =
    while true:
      yield untilPressed(Gpio(12))
      DefaultLedPin.put(High)
      yield waitMS(500) or untilPressed(Gpio(12))
      DefaultLedPin.put(Low)
      

proc memstats(): FiberIterator =
  iterator(): FiberYield =
    while true:
      let total = getTotalHeap()
      let occ = total - getFreeHeap()
      echo fmt"{occ} / {total}"
      yield waitMS(1000)

proc termTest(): FiberIterator =
  iterator(): FiberYield =
    while true:
      for i in IrqLevel:
        echo fmt"{i}: {i.ord}"
      yield waitMS(1000)

proc main() =
  ## Main function
  addFiber(sevenSegDaemon())
  addFiber(newTrafficLight())
  addFiber(lcdtest())
  addFiber(inputtest())
  # addFiber(termTest())
  addFiber(memstats())
  while true:
    checkInputs()
    runFibers()

when isMainModule:
  stdioInitAll()
  sleep(1000)
  try:
    main()
  except Exception as e:
    echo "An exception occurred: "
    echo e[]