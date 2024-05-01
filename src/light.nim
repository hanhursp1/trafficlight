import
  std/[options],
  picostdlib/[gpio],
  async/[fibers],
  io/[register],
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
  urbanFSM = [
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
  ruralFSM = [
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
      yield yieldTimeMS(1000)

var cross = false


proc newUrbanTrafficLightTest*(): FiberIterator =
  let crosswalkButton = Gpio(13)

  # Initialize crosswalk button irq
  crosswalkButton.init()
  crosswalkButton.setDir(In)
  crosswalkButton.pullUp()
  crosswalkButton.enableIrqWithCallback({IrqLevel.fall}, true) do(gpio: Gpio, evt: set[IrqLevel]) {.cdecl.}:
    cross = true


  var sr = ShiftRegister(input: Gpio(2), serial_clk: Gpio(3), out_buffer_clk: Gpio(4))
  sr.init()

  var state = 0'u

  iterator(): FiberYield =
    while true:
      sr.output = cast[byte](urbanFSM[state].lights)
      yield yieldTimeMS(urbanFSM[state].delay)
      if urbanFSM[state].crosswalkEnabled and cross:
        sr.output = cast[byte]({nsRed, ewRed})
        yield yieldFiber(addFiber(newCrosswalk(15)))
        cross = false
      state = urbanFSM[state].next