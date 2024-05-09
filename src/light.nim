import
  std/[options],
  picostdlib/[gpio],
  async/[fibers],
  io/[register, input, irq],
  sevenseg

type
  CrossingMode = enum
    Rural, Urban
  TrafficLights = enum
    nsGreen, nsYellow, nsRed,
    ewGreen, ewYellow, ewRed
  CrossingConfig = object
    mode: CrossingMode
    greenLightDelay: uint
    yellowLightDelay: uint

type
  LightNode = object
    lights: set[TrafficLights]
    delay: uint
    crosswalkEnabled: bool
    holdUntil: Option[Gpio]
    next: uint

let
  urbanFSM = @[
    LightNode(
      lights: {nsGreen, ewRed},
      delay: 5000,
      next: 1
    ),
    LightNode(
      lights: {nsYellow, ewRed},
      delay: 2000,
      crosswalkEnabled: true,
      next: 2
    ),
    LightNode(
      lights: {nsRed, ewGreen},
      delay: 5000,
      next: 3
    ),
    LightNode(
      lights: {nsRed, ewYellow},
      delay: 2000,
      crosswalkEnabled: true,
      next: 0
    )
  ]
  ruralFSM = @[
    LightNode(
      lights: {nsGreen, ewRed},
      delay: 5000,
      holdUntil: some(Gpio(14)),
      next: 1
    ),
    LightNode(
      lights: {nsYellow, ewRed},
      delay: 2000,
      next: 2
    ),
    LightNode(
      lights: {nsRed, ewGreen},
      delay: 5000,
      holdUntil: some(Gpio(15)),
      next: 3
    ),
    LightNode(
      lights: {nsRed, ewYellow},
      delay: 2000,
      next: 0
    )
  ]

proc newCrosswalk*(count: SomeUnsignedInt): FiberIterator =
  iterator(): FiberYield =
    for i in countdown(count, 0):
      setSevenSegValue(i.uint)
      yield waitMS(1000)

var cross = false
var fsm = addr urbanFSM

proc newTrafficLight*(): FiberIterator =
  listenForInput(Gpio(14))
  listenForInput(Gpio(15))

  let crosswalkButton = Gpio(13)
  let modeToggle = Gpio(10)

  # Initialize crosswalk and mode toggle button irq
  crosswalkButton.init()
  crosswalkButton.setDir(In)
  crosswalkButton.pullUp()
  crosswalkButton.registerIrq({IrqLevel.fall}) do():
    cross = true

  modeToggle.init()
  modeToggle.setDir(In)
  modeToggle.pullUp()
  modeToggle.registerIrq({IrqLevel.fall}) do():
    echo "Switching mode!"
    if fsm == (addr urbanFSM):
      fsm = addr ruralFSM
    else:
      fsm = addr urbanFSM

  var sr = ShiftRegister(input: Gpio(2), serial_clk: Gpio(3), out_buffer_clk: Gpio(4))
  sr.init()

  var state = 0'u

  iterator(): FiberYield =
    while true:
      # A bitset is just a number, so this works
      sr.output = cast[byte](fsm[][state].lights)
      # Wait a bit
      yield waitMS(fsm[][state].delay)

      # If the crosswalk is enabled and we need to cross,
      # then wait until the cross is finished
      if fsm[][state].crosswalkEnabled and cross:
        sr.output = cast[byte]({nsRed, ewRed})
        yield waitFiber(addFiber(newCrosswalk(15)))
        cross = false
      # If we need to hold for some road triggers, then wait
      if fsm[][state].holdUntil.isSome():
        let pin = fsm[][state].holdUntil.unsafeGet()
        yield untilHeld(pin) or waitCallback(proc(): bool = fsm == addr urbanFSM)
      # Next state
      state = fsm[][state].next