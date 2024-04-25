import
  picostdlib/[gpio, time],
  register

#### Commands ####

type
  Command* = distinct uint16

const
  CLR* = Command(0x01)      ## Clear the display
  RET* = Command(0x02)      ## Return the cursor to home

template EMSET*(I_D, SH: bool): Command =
  ## Set entry mode
  Command(0x04 or (I_D.ord.shl 1) or SH.ord)
template DISMODE*(D, C, B: bool): Command =
  ## Set the display, cursor, and blinking on/off
  Command(0x08 or (D.ord.shl 2) or (C.ord.shl 1) or B.ord)
template CDS*(S_C, N, F: bool): Command =
  ## Set cursor moving and display shift
  Command(0x10 or (S_C.ord.shl 3) or (R_L.ord.shl 2))
template FSET*(DL, N, F: bool): Command =
  ## Function set
  Command(0x20 or (DL.ord.shl 4) or (N.ord.shl 3) or (F.ord.shl 2))
template SETCG*(AC: byte): Command =
  ## Set CGRAM Address
  Command(0x40 or (AC and 0x3F))
template SETDDR*(AC: byte): Command =
  ## Set DDRAM Address
  Command(0x80 or (AC and 0x7F))
template WRITE*(D: byte|char): Command =
  ## Write D to current address
  ## This is the only instruction that has a control byte
  Command(0x0200'u16 or D.uint16)

#### Command helper functions ####

proc getInstruction*(this: Command): byte {.inline.} =
  byte((this.uint16) and 0xff)

proc getControl*(this: Command): byte {.inline.} =
  byte((this.uint16).shr 8)

proc getInstructionNibbles*(this: Command): array[2, byte] {.inline.} =
  let instr = this.getInstruction()
  result[0] = instr.shr 4
  result[1] = instr and 0x0f

#### LCD ####

type
  LCDisplay* = object
    register*: ShiftRegister
    enablePin*: Gpio
  LCDLine* {.pure.} = enum
    LineOne, LineTwo

proc nibbleWrite*(this: var LCDisplay, data: byte, control: byte) =
  let cmd = (data and 0x0f) or (control.shl 4)
  this.register.output = cmd
  sleepMicroseconds(2)
  this.enablePin.put(High)
  sleepMicroseconds(2)
  this.enablePin.put(Low)

proc commandWrite*(this: var LCDisplay, command: Command) =
  let control = command.getControl()
  let instr = command.getInstructionNibbles()
  this.nibbleWrite(instr[0], control)
  this.nibbleWrite(instr[1], control)

  if command.uint16 < 0x04:
    sleepMicroseconds(1600)
  else:
    sleepMicroseconds(50)

proc run*(this: var LCDisplay, commands: openArray[Command]) =
  for c in commands:
    this.commandWrite(c)

proc init*(this: var LCDisplay) =
  this.register.init()
  this.enablePin.init()
  this.enablePin.setDir(Out)

  # Wake up the LCD
  sleep(20)
  this.nibbleWrite(0x03, 0)
  sleep(5)
  this.nibbleWrite(0x03, 0)
  sleep(1)
  this.nibbleWrite(0x03, 0)
  sleep(1)

  # Initialize 4-bit data mode (Copied from C version)
  this.nibbleWrite(0x02, 0)
  sleep(1)
  this.run([
    FSET(false, true, false),
    EMSET(true, true),
    CLR,
    DISMODE(true, true, true)
  ])

proc clear*(this: var LCDisplay) {.inline.} =
  this.commandWrite(CLR)

proc write*(this: var LCDisplay, output: string) =
  for c in output:
    this.commandWrite(WRITE(c))

proc writeLine*(this: var LCDisplay, output: string, line = LCDLine.LineOne) =
  case line
  of LCDLine.LineOne:
    this.commandWrite(SETDDR(0x00))
  of LCDLine.LineTwo:
    this.commandWrite(SETDDR(0x40))
  this.write(output)