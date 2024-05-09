import
  std/[options, sequtils, strformat, macros],
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
      toggleBool*: proc()
    of IncDec:                  # Increment/decrement is designed to change a value
      increment*: proc()
      decrement*: proc()
      display*: proc(): string
    of Return:                  # Return is just a special menu that pops the `history` stack
      discard
  MenuEntry* = ref MenuEntryObj

## Global return button to save some memory allocation every time we draw the menu
let returnButton = MenuEntry(label: "Back", kind: Return)

## Global LCD
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

## Menu variables
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
    # Loop forever
    while true:
      if currentMenu.isNil():
        # If somehow, the current menu is null, fall back to the root menu!
        currentMenu = rootMenu
        historyStack = @[]
        currentSelection = 0

      # Switch based on the type of the current menu  
      case currentMenu.kind
      of Return:
        if historyStack.len() == 0:
          currentMenu = rootMenu
          currentSelection = 0
        else:
          (currentMenu, currentSelection) = historyStack.pop()
      of Submenu:
        # Draw a submenu
        # This is probably the most complicated menu type

        if isPressed(UP): currentSelection.inc
        if isPressed(DOWN): currentSelection.dec

        # Bind the selection between 0 and the current menus length
        # If we're not in the main menu, there will be a return option that is
        # technically not a menu entry.
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
        
        # Get which menus to display
        let display = getSubmenuSlice(currentMenu, currentSelection, currentMenu == rootMenu)
        LCD.clear()

        for i, d in display:
          if d.isSome():
            let (idx, menu) = d.unsafeGet()
            let cursor = if idx == currentSelection: "\x7E" else: " "
            if menu.kind == Toggle:
              let checkbox = if menu.getBool(): '\x02' else: '\x01'
              LCD[i] = fmt"""{cursor}{(idx+1):>02}:{checkbox}{menu.label}"""
            else:
              LCD[i] = fmt"""{cursor}{(idx+1):>02}:{menu.label}"""
      of Toggle:
        # Toggle the button then return
        currentMenu.toggleBool()
        currentMenu = returnButton
        continue
      of FunctionCall:
        # Call the callback then return
        currentMenu.callback()
        currentMenu = returnButton
        continue
      of IncDec:
        if isPressed(UP):
          currentMenu.increment()
        if isPressed(DOWN):
          currentMenu.decrement()
        if isPressed(ENTER):
          currentMenu = returnButton
          continue

        LCD[0] = "\x03\x04:" & currentMenu.label
        LCD[1] = currentMenu.display()
      yield untilAnyPressed({UP, DOWN, ENTER})


#### MACROS

proc incdecImpl(name: NimNode, body: NimNode): NimNode =
  # Find each of our callbacks
  let increment = body.findChild(
    it.kind == nnkCall and it[0].kind == nnkIdent and it[0].strVal == "increment")[1]
  if increment.isNil(): error "Increment-Decrement menu must have an `increment` callback"
  let decrement = body.findChild(
    it.kind == nnkCall and it[0].kind == nnkIdent and it[0].strVal == "decrement")[1]
  if increment.isNil(): error "Increment-Decrement menu must have a `decrement` callback"
  let display   = body.findChild(
    it.kind == nnkCall and it[0].kind == nnkIdent and it[0].strVal == "display"  )[1]
  if increment.isNil(): error "Increment-Decrement menu must have a `display` callback returning a string"

  # Construct the object from these callbacks
  result = quote do:
    MenuEntry(
      label: `name`,
      kind: IncDec,
      increment: proc() = `increment`,
      decrement: proc() = `decrement`,
      display:   proc(): string = `display`
    )

proc callbackImpl(name: NimNode, body: NimNode): NimNode =
  # This one is really simple. Just make the body a function body
  result = quote do:
    MenuEntry(
      label: `name`,
      kind: FunctionCall,
      callback: proc() = `body`
    )

proc toggleImpl(name: NimNode, body: NimNode): NimNode =
  # Find both of out callbacks
  let get = body.findChild(
    it.kind == nnkCall and it[0].kind == nnkIdent and it[0].strVal == "get")[1]
  if get.isNil(): error "Toggle menu must have a `get` callback which returns a `bool`"
  let toggle = body.findChild(
    it.kind == nnkCall and it[0].kind == nnkIdent and it[0].strVal == "toggle")[1]
  if toggle.isNil(): error "Toggle menu must have a `toggle` callback"
  
  # Construct the object
  result = quote do:
    MenuEntry(
      label: `name`,
      kind: Toggle,
      getBool: proc(): bool = `get`,
      toggleBool: proc() = `toggle`
    )


proc submenuImpl(name: NimNode, body: NimNode): NimNode =
  var subnodes: seq[NimNode]    # Submenu nodes

  # iterate over every node in the body.
  # if it's a command, and it matches one of the
  for i in body:
    if i.kind != nnkCommand:
      if i.kind == nnkIdent:
        subnodes.add(i)   # `i` is likely a variable
      continue
    case i[0].strVal
    of "incdec":
      subnodes.add(incdecImpl(i[1], i[2]))
    of "submenu":
      subnodes.add(submenuImpl(i[1], i[2]))
    of "callback":
      subnodes.add(callbackImpl(i[1], i[2]))
    of "toggle":
      subnodes.add(toggleImpl(i[1], i[2]))

  # Iterate over submenus and put them in the resulting array
  var arr = newNimNode(nnkBracket)
  for i in subnodes:
    arr.add(i)
  
  # Construct the object
  result = quote do:
    MenuEntry(
      label: `name`,
      kind: Submenu,
      submenus: @`arr`
    )

macro submenu*(name: string, body: untyped): MenuEntry =
  submenuImpl(name, body)

macro incdec*(name: string, body: untyped): MenuEntry =
  incdecImpl(name, body)

macro callback*(name: string, body: untyped): MenuEntry =
  callbackImpl(name, body)

macro toggle*(name: string, body: untyped): MenuEntry =
  toggleImpl(name, body)