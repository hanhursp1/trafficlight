import
  io/[register]

type
  CrossingMode = enum
    Rural, Urban
  CrossingConfig = object
    mode: CrossingMode
    greenLightDelay: uint
    yellowLightDelay: uint