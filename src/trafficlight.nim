import 
  picostdlib/[gpio, time, stdio],
  std/[strformat],
  async/[fibers],
  csrc/[meminfo],
  io/[register, lcd, input, irq],
  sevenseg, light, lcdmenu



proc main() =
  addFiber(sevenSegDaemon())
  addFiber(newTrafficLight())
  addFiber(addMenuHandler())

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