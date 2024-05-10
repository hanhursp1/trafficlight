import
  picostdlib/[gpio, time],
  register

const
  LCD_WIDTH = 16    ## Width of the LCD
  CUSTOM_CHARS = [1, 2, 3, 4]     ## Custom character codes
  CUSTOM_CHAR_DATA = block:       ## Data of custom characters
    # Reads all character files defined by `CUSTOM_CHARS` from "res" at
    # compile time and embeds them into the file.
    var res: array[CUSTOM_CHARS.len(), array[8, byte]]  # Result array
    for i, c in CUSTOM_CHARS:
      var str = readFile("res/" & $c & ".char")         # Read the whole file
      for j in 0..<8:
        res[i][j] = str[j].byte         # Store each byte in the data array
    res                                 # Return the result

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
template CDS*(S_C, R_L: bool): Command =
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
    isInitialized*: bool
    register*: ShiftRegister
    enablePin*: Gpio
    settings*: LCDSettings
  LCDSettings* = object
    cursor*, blinking*: bool
  LCDLine* {.pure.} = enum
    LineOne, LineTwo

proc nibbleWrite*(this: var LCDisplay, data: byte, control: byte) =
  ## Writes the lower nibble of `data` to `this`, along with `control`.
  let cmd = (data and 0x0f) or (control.shl 4)
  this.register.output = cmd
  sleepMicroseconds(2)
  this.enablePin.put(High)
  sleepMicroseconds(2)
  this.enablePin.put(Low)

proc commandWrite*(this: var LCDisplay, command: Command) =
  ## Writes both nibbles of a command to `this`
  let control = command.getControl()
  let instr = command.getInstructionNibbles()
  this.nibbleWrite(instr[0], control)
  this.nibbleWrite(instr[1], control)

  if command.uint16 < 0x04:
    sleepMicroseconds(1600)
  else:
    sleepMicroseconds(50)

proc run*(this: var LCDisplay, commands: openArray[Command]) =
  ## Runs an array of commands
  for c in commands:
    this.commandWrite(c)

proc initDefaultCustomCharacters*(this: var LCDisplay) =
  ## Initialize the default custom characters
  for i in 0..<CUSTOM_CHARS.len():
    let address = byte(CUSTOM_CHARS[i].shl 3)
    this.commandWrite(SETCG(address))
    for b in CUSTOM_CHAR_DATA[i]:
      this.commandWrite(WRITE(b))

proc initCustomCharacters*(this: var LCDisplay, data: openArray[tuple[idx: int, data: array[8, byte]]]) =
  ## Overwrite existing custom character data
  for (adr, dat) in data:
    let address = byte(adr.shl 3)
    this.commandWrite(SETCG(address))
    for b in dat:
      this.commandWrite(WRITE(b))

proc init*(this: var LCDisplay) =
  ## Initializes the LCD
  echo "Initializing LCD..."
  this.register.init()
  this.enablePin.init()
  this.enablePin.setDir(Out)

  # Wake up the LCD
  sleep(50)
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
    EMSET(true, false),
    CLR,
    DISMODE(true, this.settings.cursor, this.settings.blinking)
  ])
  
  # Write custom character data
  this.initDefaultCustomCharacters()
  # LCD has finished initializing
  this.isInitialized = true

proc clear*(this: var LCDisplay) {.inline.} =
  ## Clear the display
  this.commandWrite(CLR)

proc write*(this: var LCDisplay, output: string) =
  ## Write the string `output` to the display, starting from the
  ## current memory location.
  if not this.isInitialized:
    this.init()
    this.isInitialized = true
  for c in output:
    this.commandWrite(WRITE(c))

proc writeLine*(this: var LCDisplay, output: string, line = LCDLine.LineOne) =
  ## Write the string `output` to the display, starting from the
  ## beginning of one of the lines.
  if not this.isInitialized:
    this.init()
    this.isInitialized = true
  case line
  of LCDLine.LineOne:
    this.commandWrite(SETDDR(0x00))
  of LCDLine.LineTwo:
    this.commandWrite(SETDDR(0x40))
  
  this.write(
    # Cap the output at 16 characters
    output[0..min(output.high, LCD_WIDTH - 1)]
  )

proc `[]=`*(this: var LCDisplay, idx: range[0..1], val: string) =
  ## More convenient form of `writeLine` using the array access operator.
  runnableExamples:
    # Write a string to the first line of `LCD`
    LCD[0] = "Hello world!"
    # Format and write a string to the second line of `LCD`
    LCD[1] = fmt"a + b = {a + b}"

  this.writeLine(val, LCDLine(idx))