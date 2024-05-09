import
  std/[options, sequtils, strformat],
  picostdlib/[gpio],
  io/[lcd, register, input],
  async/[fibers]

const
  UP = Gpio(11)
  DOWN = Gpio(10)
  ENTER = Gpio(12)

type
  MenuEntryType* = enum
    Submenu, FunctionCall, Toggle, IncDec, Return
  MenuEntryObj = object
    ## Base object for menu entries
    label*: string    # Text to display when the menu entry is shown
    case kind*: MenuEntryType   # What kind of menu entry it is
    of Submenu:                 # Submenus store a vector of other menu entries
      submenus*: seq[MenuEntry]
    of FunctionCall:            # Function callbacks store a function to call when the entry is selected
      callback*: proc()
    of Toggle:                  # Toggles toggle a boolean on and off
      getBool*: proc(): bool
      toggleBool*: proc(): bool
    of IncDec:                  # Increment/decrement is designed to change a value
      increment*: proc()
      decrement*: proc()
      display*: proc(): string
    of Return:                  # Return is just a special menu that pops the `history` stack
      discard
  MenuEntry* = ref MenuEntryObj

## Global return button to save some memory allocation every time we draw the menu
let returnButton = MenuEntry(label: "Back", kind: Return)

var LCD* = LCDisplay(
  register: ShiftRegister(
    input: Gpio(2), serial_clk: Gpio(3), out_buffer_clk: Gpio(6)
  ),
  enablePin: Gpio(7),
  settings: LCDSettings(
    cursor: false,
    blinking: false
  )
)

var
  rootMenu: MenuEntry = MenuEntry(
    kind: Submenu,
    submenus: @[]
  )
  currentMenu: MenuEntry
  currentSelection: uint
  historyStack*: seq[tuple[entry: MenuEntry, idx: uint]]

proc `[]`*(this: MenuEntry, idx: SomeInteger): Option[MenuEntry] =
  if this.kind != Submenu: none(MenuEntry)
  # Cast to the same type as idx
  elif idx < typeof(idx)(this.submenus.len()): some(this.submenus[idx])
  else: none(MenuEntry)

proc addMainMenu*(menu: MenuEntry) =
  rootMenu.submenus.add(menu)

proc getSubmenuSlice(menu: MenuEntry, index: uint, isMainMenu = false): array[2, Option[(uint, MenuEntry)]] =
  assert menu.kind == Submenu, "`menu` must be a submenu in order to get a slice."
  # This was kinda hacked together from an earlier function
  var tempResultMenus: array[2, Option[MenuEntry]]
  var tempResultIndex: array[2, uint]
  if (index and 1) == 0:
    tempResultMenus[0] = menu[index]
    tempResultMenus[1] = menu[index + 1]
    tempResultIndex[0] = index
    tempResultIndex[1] = index + 1
  else:
    tempResultMenus[0] = menu[index - 1]
    tempResultMenus[1] = menu[index]
    tempResultIndex[0] = index - 1
    tempResultIndex[1] = index
  if not isMainMenu:
    # If the menu is not the main menu, we can add a return button at the bottom
    if tempResultMenus[0].isNone():
      tempResultMenus[0] = some returnButton
    elif tempResultMenus[0].isSome() and result[1].isNone():
      tempResultMenus[1] = some returnButton
  
  for i, (idx, menu) in zip(tempResultIndex, tempResultMenus):
    if menu.isNone():
      result[i] = none (uint, MenuEntry)
    else:
      result[i] = some (idx, menu.unsafeGet())

proc addMenuHandler*(): FiberIterator =
  ## Initializes the LCD and returns a new iterator for menu handling.
  
  # initialize the LCD
  if not LCD.isInitialized:
    LCD.init()
  
  # Set the current menu to root
  currentMenu = rootMenu

  listenForInput(UP)
  listenForInput(DOWN)
  listenForInput(ENTER)

  iterator(): FiberYield =
    while true:
      case currentMenu.kind
      of Submenu:
        if isPressed(UP): currentSelection.inc
        if isPressed(DOWN): currentSelection.dec

        if currentSelection >= currentMenu.submenus.len().uint:
          currentSelection =
            if currentMenu == rootMenu:
              currentMenu.submenus.len().uint - 1
            else:
              currentMenu.submenus.len().uint

        if isPressed(ENTER):
          # Push the current menu and current selection onto the history stack
          historyStack.add((currentMenu, currentSelection))
          var next = currentMenu[currentSelection]
          # If the next index is out of bounds, then return to the previous menu.
          # It's a hack, but it should guard some edge cases as well.
          if next.isNone():
            next = some returnButton
          currentMenu = next.unsafeGet()
          currentSelection = 0
          continue

        let display = getSubmenuSlice(currentMenu, currentSelection, currentMenu == rootMenu)
        LCD.clear()
        for i, d in display:
          if d.isSome():
            let (idx, menu) = d.unsafeGet()
            let cursor = if idx == currentSelection: '\xF6' else: ' '
            if menu.kind == Toggle:
              let checkbox = if menu.getBool(): '\x02' else: '\x01'
              LCD[i] = fmt"""{cursor}{(idx+1):>02}:{checkbox}{menu.label}"""
            else:
              LCD[i] = fmt"""{cursor}{(idx+1):>02}: {menu.label}"""
        
      else:
        discard
      yield untilAnyPressed({UP, DOWN, ENTER})