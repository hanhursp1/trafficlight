import
  picostdlib/[gpio],
  io/[lcd, register, input],
  async/[fibers]

type
  MenuEntryType* = enum
    Submenu, FunctionCall, Toggle, IncDecInt, IncDecFloat
  MenuEntryObj = object
    label*: string
    case kind*: MenuEntryType
    of Submenu:
      submenus*: seq[MenuEntry]
    of FunctionCall:
      callback*: proc()
    of Toggle:
      getBool*: proc(): bool
      toggleBool*: proc(): bool
    of IncDecInt:
      getInt*: proc(): int
      incInt*: proc(): int
      decInt*: proc(): int
    of IncDecFloat:
      getFloat*: proc(): float
      incFloat*: proc(): float
      decFloat*: proc(): float
  MenuEntry* = ref MenuEntryObj

var
  rootMenu: MenuEntry = MenuEntry(
    kind: Submenu,
    submenus: @[]
  )
  currentMenu: MenuEntry
  currentSelection: int
  history*: seq[MenuEntry]

proc addMainMenu*(menu: MenuEntry) =
  rootMenu.submenus.add(menu)

# proc drawMenu*()