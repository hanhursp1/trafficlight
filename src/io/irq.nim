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
  ## Callback for the irq.
  for e in events:
    # Get the irq callback from the lookup table.
    # Check to make sure it's not `nil` before calling it.
    let callback = callbacks[pin][e]
    if not callback.isNil():
      callback()

proc registerIrq*(pin: Gpio, events: set[IrqLevel], callback: InterruptCallback) =
  ## Add a callback to be handled when an irq pin is triggered.
  if not initialized:
    pin.enableIrqWithCallback(events, true, handleIrq)

  setEvents = setEvents + events
  pin.enableIrq(setEvents, true)
  for e in events:
    callbacks[pin][e] = callback