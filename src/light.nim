import
  std/[options, strformat],
  picostdlib/[gpio],
  async/[fibers],
  io/[register, input, irq],
  sevenseg, lcdmenu

const
  CROSSWALK_BUTTON = Gpio(13)
  EW_HOLD = Gpio(14)
  NS_HOLD = Gpio(15)

type
  CrossingMode = enum
    Rural, Urban
  DelayKind = enum
    GreenLight, YellowLight
  TrafficLights = enum
    nsGreen, nsYellow, nsRed,
    ewGreen, ewYellow, ewRed
  CrossingConfig = object
    mode: CrossingMode
    greenLightDelay: uint
    yellowLightDelay: uint
    crosswalkTime: uint

type
  LightNode = object
    lights: set[TrafficLights]
    delay: DelayKind
    crosswalkEnabled: bool
    holdUntil: Option[Gpio]
    next: uint

# One state machine to rule them all
let FSM = @[
  LightNode(lights: {nsGreen, ewRed}, delay: GreenLight, holdUntil: some(EW_HOLD), next: 1),
  LightNode(lights: {nsYellow, ewRed}, delay: YellowLight, crosswalkEnabled: true, next: 2),
  LightNode(lights: {nsRed, ewGreen}, delay: GreenLight, holdUntil: some(NS_HOLD), next: 3),
  LightNode(lights: {nsRed, ewYellow}, delay: YellowLight, crosswalkEnabled: true, next: 0)
]

var config = CrossingConfig(
  mode: Urban,
  greenLightDelay: 5000,
  yellowLightDelay: 2000,
  crosswalkTime: 15
)

# Traffic light menu implementation
let ruralMenu =
  toggle "Rural Mode":
    toggle:
      config.mode =
        if config.mode == Urban: Rural
        else: Urban
    get:
      return config.mode == Rural

let delays =
  submenu "Light Delays":
    incdec "Green light":
      increment:
        config.greenLightDelay += 500
      decrement:
        config.greenLightDelay -= 500
        if config.greenLightDelay < 3000:
          config.greenLightDelay = 3000
      display:
        let lightSecs = float(config.greenLightDelay) / 1000.0
        return fmt"{lightSecs:.1f}"
    incdec "Yellow light":
      increment:
        config.yellowLightDelay += 500
      decrement:
        config.yellowLightDelay -= 500
        if config.yellowLightDelay < 500:
          config.yellowLightDelay = 500
      display:
        let lightSecs = float(config.yellowLightDelay) / 1000.0
        return fmt"{lightSecs:.1f}"
    incdec "Crosswalk":
      increment:
        config.crosswalkTime.inc
      decrement:
        config.crosswalkTime.dec
      display: return $config.crosswalkTime
    return
    

addMainMenu(ruralMenu)
addMainMenu(delays)

proc newCrosswalk*(count: SomeUnsignedInt): FiberIterator =
  iterator(): FiberYield =
    for i in countdown(count, 0):
      setSevenSegValue(i.uint)
      yield waitMS(1000)

var walk = false

proc newTrafficLight*(): FiberIterator =
  listenForInput(EW_HOLD)
  listenForInput(NS_HOLD)

  CROSSWALK_BUTTON.init()
  CROSSWALK_BUTTON.setDir(In)
  CROSSWALK_BUTTON.pullUp()
  registerIrq(CROSSWALK_BUTTON, {IrqLevel.rise}) do():
    walk = true

  var sr = ShiftRegister(input: Gpio(2), serial_clk: Gpio(3), out_buffer_clk: Gpio(4))
  sr.init()

  var state = 0'u

  iterator():FiberYield =
    while true:
      sr.output = cast[byte](FSM[state].lights)

      let yieldTime =
        if FSM[state].delay == GreenLight:
          config.greenLightDelay
        else:
          config.yellowLightDelay
      yield waitMS(yieldTime)
      
      if config.mode == Urban:
        if FSM[state].crosswalkEnabled and walk:
          sr.output = cast[byte]({nsRed, ewRed})
          yield waitFiber(addFiber(newCrosswalk(config.crosswalkTime)))
          walk = false
      if config.mode == Rural:
        if FSM[state].holdUntil.isSome():
          yield 
            untilHeld(FSM[state].holdUntil.unsafeGet()) or
            waitCallback(proc(): bool = config.mode != Rural)
      state = FSM[state].next