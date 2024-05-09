import 
  picostdlib/[gpio, time, stdio],
  std/[strformat],
  async/[fibers],
  csrc/[meminfo],
  io/[register, lcd, input, irq],
  sevenseg, light, lcdmenu

proc createNewDebugInfo(): FiberIterator =
  iterator(): FiberYield =
    yield next()
    while true:
      LCD.clear()
      let totalHeap = float(getTotalHeap()) / 1024.0
      let usedHeap = float(getTotalHeap() - getFreeHeap()) / 1024.0
      LCD[0] = "Heap Used:"
      LCD[1] = fmt"{usedHeap:>4.2}K/{totalHeap:>4.2}K"
      yield waitMS(200) or untilPressed(ENTER)
      if isPressed(ENTER):
        echo "Unsuspending..."
        menuSuspended = false
        return

let debugMenu = callback "Debug Info":
  menuSuspended = true
  echo "Suspending debug menu..."
  addFiber(createNewDebugInfo())

addMainMenu(debugMenu)

proc main() =
  addFiber(sevenSegDaemon())
  addFiber(newTrafficLight())
  addFiber(newMenuHandler())

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