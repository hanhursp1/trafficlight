import
  picostdlib/[gpio]

type
  InterruptCallback = proc()

var
  initialized = false
  callbacks: array[
    Gpio, array[IrqLevel, InterruptCallback]]
  setEvents: set[IrqLevel]

proc handleIrq(pin: Gpio, events: set[IrqLevel]) {.cdecl.} =
  for e in events:
    callbacks[pin][e]()

proc registerIrq*(pin: Gpio, events: set[IrqLevel], callback: InterruptCallback) =
  if not initialized:
    pin.enableIrqWithCallback(events, true, handleIrq)

  setEvents = setEvents + events
  pin.enableIrq(setEvents, true)
  for e in events:
    callbacks[pin][e] = callback