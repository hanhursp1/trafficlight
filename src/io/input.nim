import
  std/[sequtils],
  picostdlib/[gpio],
  ../async/fibers

#### Special input handling API for specific pins
## Makes heavy use of bitsets
## I implemented this just for 3 buttons lmao.
## But it's modular, and it's here in case I need it

var
  watch: set[Gpio]
  activeLow: set[Gpio]
  pressed, held, released: set[Gpio]

proc listenForInput*(pin: Gpio, isActiveLow = true) =
  ## Set a pin to be watched for input
  pin.init()
  pin.setDir(In)
  if isActiveLow: pin.pullUp() else: pin.pullDown()
  watch = watch + {pin}
  if isActiveLow:
    activeLow = activeLow + {pin}

proc checkInputs*() =
  ## Check and update all inputs. Has 3 separate states:
  ## 
  ## pressed: when a pin was just pressed,
  ## held: when a pin is being held,
  ## released: when a pin was just released
  for pin in watch:
    var pinStatus = pin.get()
    # Invert the pin if it's active low
    if pin in activeLow:
      pinStatus = if pinStatus == High: Low else: High
    if pinStatus == High:
      # If the pin is already pressed, move it to the held state
      if pin in pressed and pin notin held:
        pressed = pressed - {pin}
        held = held + {pin}
      # Otherwise, it was just pressed
      elif pin notin pressed and pin notin held:
        pressed = pressed + {pin}
    else:
      # If the pin is being pressed and was just released, move it to the released state
      if pin in pressed or pin in held:
        pressed = pressed - {pin}
        held = held - {pin}
        released = released + {pin}
      # Otherwise, if it's in the released state already, remove it
      elif pin in released:
        released = released - {pin}

proc getPressed*(): set[Gpio]   = pressed
proc getHeld*(): set[Gpio]      = held
proc getReleased*(): set[Gpio]  = released

proc isPressed*(pin: Gpio): bool  = pin in pressed
proc isHeld*(pin: Gpio): bool     = pin in held
proc isReleased*(pin: Gpio): bool = pin in released

#### Fiber types for awaiting input
type
  FiberYieldUntilPressedObj = object of FiberYield
    pin*: Gpio
  FiberYieldUntilPressed* = ref FiberYieldUntilPressedObj
  FiberYieldUntilHoldObj = object of FiberYield
    pin*: Gpio
  FiberYieldUntilHold* = ref FiberYieldUntilHoldObj
  ## these types are starting to suffer from Java syndrome
  ## `FiberYieldUntilPressedAnyObjFactoryTemplateIterator`
  FiberYieldUntilPressedAnyObj = object of FiberYield
    pins*: set[Gpio]
  FiberYieldUntilPressedAny* = ref FiberYieldUntilPressedAnyObj

method ready*(this: FiberYieldUntilPressed): bool =
  this.pin.isPressed()

method ready*(this: FiberYieldUntilHold): bool =
  this.pin.isHeld()

method ready*(this: FiberYieldUntilPressedAny): bool =
  (this.pins * pressed) != {}

proc untilPressed*(pin: Gpio): FiberYieldUntilPressed =
  result.new()
  result.pin = pin

proc untilHeld*(pin: Gpio): FiberYieldUntilHold =
  result.new()
  result.pin = pin

proc untilAnyPressed*(pins: set[Gpio]): FiberYieldUntilPressedAny =
  result.new()
  result.pins = pins