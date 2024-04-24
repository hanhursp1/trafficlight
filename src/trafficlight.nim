import picostdlib/[gpio, time]
import std/[strformat]
import scheduler/tasks
import io/[register, sevenseg]


type
  TrafficLights = enum
    nsGreen, nsYellow, nsRed,
    ewGreen, ewYellow, ewRed
  TrafficState = set[TrafficLights]

proc newCrossing(seconds: int): TaskIterator =
  iterator(): TaskYield =
    for x in 0..<seconds:
      for y in 0..<4:
        DefaultLedPin.put(on)
        yield yieldTimeMS(100)
        DefaultLedPin.put(off)
        yield yieldTimeMS(100)
      yield yieldTimeMS(200)
      DefaultLedPin.put(off)

proc newUrbanTrafficLightTest(): TaskIterator =
  var sr = ShiftRegister(input: Gpio(2), serial_clk: Gpio(3), out_buffer_clk: Gpio(4))
  sr.init()

  iterator(): TaskYield =
    while true:
      sr.output = cast[byte]({nsGreen, ewRed})
      yield yieldTimeMS(5000)
      sr.output = cast[byte]({nsYellow, ewRed})
      yield yieldTimeMS(2000)
      sr.output = cast[byte]({nsRed, ewGreen})
      yield yieldTimeMS(5000)
      sr.output = cast[byte]({nsRed, ewYellow})
      yield yieldTimeMS(2000)

proc ledtest(): TaskIterator =
  var sr = ShiftRegister(input: Gpio(2), serial_clk: Gpio(3), out_buffer_clk: Gpio(5))
  sr.init()

  iterator(): TaskYield =
    while true:
      for i in 0..9:
        sr.output = byte(SEGMENT_LOOKUP[i])
        yield yieldTimeMS(1000)

proc main() =
  ## Initialize pins
  
  addTask(ledtest())
  addTask(newUrbanTrafficLightTest())
  # addTask(newMemInfo())
  while true:
    runTasks()

when isMainModule:
  main()