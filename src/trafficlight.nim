import 
  picostdlib/[gpio, time, stdio],
  std/[strformat],
  async/[fibers],
  csrc/[meminfo],
  io/[register, lcd, input, irq],
  sevenseg, light, lcdmenu

proc lcdtest(): FiberIterator =
  LCD.init()
  listenForInput(Gpio(12))
  iterator(): FiberYield =
    while true:
      for c in '\x00'..'\xFF':
        LCD.clear()
        let b = c.byte
        LCD[0] = fmt"{b:#02X} : {c}"
        yield untilPressed(Gpio(12))

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

proc blinkTest(): FiberIterator =
  DefaultLedPin.init()
  DefaultLedPin.setDir(Out)
  iterator(): FiberYield =
    for i in 0..4:
      DefaultLedPin.put(High)
      yield waitMS(200)
      DefaultLedPin.put(Low)
      yield waitMS(200)

proc main() =
  ## Main function
  addFiber(sevenSegDaemon())
  addFiber(newTrafficLight())
  # addFiber(addMenuHandler())
  # addFiber(inputtest())
  # addFiber(termTest())
  addFiber(lcdtest())
  addFiber(memstats())

  addMainMenu(MenuEntry(
    label: "Blink LED",
    kind: FunctionCall,
    callback: proc() =
      addFiber(blinkTest())
  ))

  while true:
    checkInputs()
    runFibers()

when isMainModule:
  stdioInitAll()
  stderr = stdout
  sleep(1000)
  try:
    main()
  except Exception as e:
    stdioInitAll()
    echo "An exception occurred: "
    echo e[]