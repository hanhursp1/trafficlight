import picostdlib/[gpio, time]
import scheduler/tasks

proc newCrossing(seconds: int): TaskIterator =
  iterator(): TaskYield =
    for _ in 0..<seconds:
      for _ in 0..<4:
        DefaultLedPin.put(on)
        yield yieldTimeMS(100)
        DefaultLedPin.put(off)
        yield yieldTimeMS(100)
      yield yieldTimeMS(200)


proc newUrbanTrafficLight(): TaskIterator =
  DefaultLedPin.init()
  DefaultLedPin.setDir(Out)
  iterator(): TaskYield =
    while true:
      for _ in 0..<8:
        DefaultLedPin.put(on)
        yield yieldTimeMS(500)
        DefaultLedPin.put(off)
        yield yieldTimeMS(500)
      let crossing = addTask(newCrossing(4))
      yield yieldTask(crossing)

proc main() =
  discard addTask(newUrbanTrafficLight())
  while true:
    runTasks()

when isMainModule:
  main()