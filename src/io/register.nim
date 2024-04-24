import picostdlib/[gpio, time]

type
  ShiftRegister* = object
    buffer*: byte
    input*: Gpio
    serial_clk*: Gpio
    out_buffer_clk*: Gpio

proc init*(this: ShiftRegister) =
  # Get all fields in the `ShiftRegister` object
  for pin in this.fields():
    # Only run when the field is a Gpio
    when pin is Gpio:
      pin.init()
      pin.setDir(Out)

proc flush*(this: ShiftRegister) =
  ## Flush the contents of `this.buffer` to the selected pins.
  ## This is a blocking function
  var buf = this.buffer
  for _ in 0..<8:
    this.input.put(bool(buf and 1))
    this.serial_clk.put(on)
    # Though the SN74HC595 has a frequency in the MHz, and a pulse duration in the ns,
    # it's good to be safe.
    sleepMicroseconds(1)
    this.serial_clk.put(off)
    this.input.put(off)
    sleepMicroseconds(1)
    buf = buf.shr 1   # Shift the buffer right by 1 bit
  sleepMicroseconds(1)
  this.out_buffer_clk.put(on)
  sleepMicroseconds(1)
  this.out_buffer_clk.put(off)

proc `output=`*(this: var ShiftRegister, val: byte) =
  ## Writes to the `buffer` of `this` and flushes it
  this.buffer = val
  this.flush()