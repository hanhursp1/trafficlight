import picostdlib/[gpio, time]

#### Shift register helper structs and functions
## I was originally going to use the pico's programmable i/o for this,
## but this ended up working fine. Any performance loss was in the order
## of microseconds, so it's negligible.

type
  ShiftRegister* = object
    ## Shift register struct
    buffer*: byte         ## Buffer holding register data
    input*: Gpio          ## serial input pin
    serial_clk*: Gpio     ## serial clock pin
    out_buffer_clk*: Gpio ## output buffer clock pin

proc init*(this: ShiftRegister) =
  ## Initialize the shift register
  
  # Get all fields in the `ShiftRegister` object using the handy `fields()` iterator
  # `fields()` is just a macro that gets every single member variable of a struct.
  # It's just a neat bit of syntactic sugar.
  for pin in this.fields():
    # Only run when the field is a Gpio
    when pin is Gpio:
      pin.init()
      pin.setDir(Out)

proc flush*(this: ShiftRegister) =
  ## Flush the contents of `this.buffer` to the selected pins.
  ## This is a blocking function, however it's only about 18 microseconds,
  ## so it's negligible as long as it's not being called a thousand times
  ## each frame.
  
  var buf = this.buffer
  # Loop for each bit in a byte
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