import 
  picostdlib/[time, stdio],
  std/[strformat],
  async/[fibers],
  csrc/[meminfo],
  io/[lcd, input],
  sevenseg, light, lcdmenu

#### Main module
## A bit of an overview of this project:
## 
## The goal is to create a complex traffic light on the raspberry pi pico, with
## in-depth comments explaining features of the Nim programming language to anyone
## not very well acquainted with it.
## 
## A bit of terminology:
## - The terms "frame" and "tick" are used fairly interchangeably here. Both just
## refer to a single fiber cycle. My main experience with this type of asyncronous
## programming comes from game development, so the use of the term "frame" is just
## how I think of this.
## - A fiber is a method of parallel processing that uses cooperative multitasking.
## Though these are called fibers, they share more in common with coroutines.
## (There is some difference between the two, though I'm not entirely sure what.)

proc createNewDebugInfo(): FiberIterator =
  ## Shows the debug info
  iterator(): FiberYield =
    # Yield a frame to flush out the input.
    yield next()
    while true:
      LCD.clear()
      let totalHeap = float(getTotalHeap()) / 1024.0
      let usedHeap = float(getTotalHeap() - getFreeHeap()) / 1024.0
      LCD[0] = "Heap Used:"
      LCD[1] = fmt"{usedHeap:>4.2}K/{totalHeap:>4.2}K"
      # Wait until either 200ms has passed, or the ENTER pin has been pressed
      yield waitMS(200) or untilPressed(ENTER)
      # If ENTER was pressed, unsuspend and return
      if isPressed(ENTER):
        suspendMenu(false)
        return

let debugMenu = callback "Debug Info":
  suspendMenu(true)
  addFiber(createNewDebugInfo())

addMainMenu(debugMenu)

proc main() =
  ## Main entry point. Not actually necessary in Nim, since much like python
  ## it just executes starting from the top of the file. In fact we've already
  ## executed quite a few functions before even calling main().
  ## 
  ## Still, having a main function can help remove ambiguity
  addFiber(sevenSegDaemon())
  addFiber(newTrafficLight())
  addFiber(newMenuHandler())

  while true:
    checkInputs()
    runFibers()

#### Main entry point
## `when isMainModule` only compiles the following section when this is the
## main module. the `when` statement is equivalent to C/C++ `#if`/`#ifdef`, but
## is much more flexible.
## 
## `when isMainModule` is the Nim equivalent of python's `if __name__ == "__main__"`,
## meaining all the code after this point will only be called if this is the
## main module.
when isMainModule:
  # Initialize stdio to output over serial
  stdioInitAll()
  # Sleep for 1000ms to give components time to warm up
  sleep(1000)
  try:
    main()
  except Exception as e:
    # An exception has occurred? Then output it over serial!
    # (re-init serial just in case)
    stdioInitAll()
    echo "An exception occurred: "
    echo e[]