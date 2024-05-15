import
  std/[options, sequtils, strformat, macros, strutils],
  picostdlib/[gpio],
  io/[lcd, register, input],
  async/[fibers]

const
  UP* = Gpio(11)
  DOWN* = Gpio(10)
  ENTER* = Gpio(12)

type
  MenuEntryType* = enum
    Submenu, FunctionCall, Toggle, IncDec, Return
  
  ## This is an example of an Algabraic Data Type (ADT), also known as a tagged union.
  ## All the branches under the `case` statement exist as a C union.
  ## Nim will enforce these tags at runtime unter the debug and release modes, though
  ## checks can be disabled altogether under the danger mode.
  
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

## Global return button to save heap. This is a `let` because it needs to
## be initialized at runtime.
let RETURN_BUTTON* = MenuEntry(label: "Back", kind: Return)
## Increment the reference count so this button always has at least one ref,
## just in case the global variable somehow goes out of scope.
RETURN_BUTTON.GC_ref()

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
  currentSelection: int
  historyStack*: seq[tuple[entry: MenuEntry, idx: int]]

  menuSuspended = false   # Don't process the menu if it's suspended

proc suspendMenu*(val: bool) =
  if val:
    echo "Suspending menu..."
  else:
    echo "Unsuspending menu..."
  menuSuspended = val

proc isMenuSuspended*(): bool = menuSuspended


proc `[]`*(this: MenuEntry, idx: SomeInteger): Option[MenuEntry] =
  if this.kind != Submenu: none(MenuEntry)
  # Cast to the same type as idx
  elif idx < typeof(idx)(this.submenus.len()): some(this.submenus[idx])
  else: none(MenuEntry)

proc addMainMenu*(menu: MenuEntry) =
  rootMenu.submenus.add(menu)

proc getSubmenuSlice(menu: MenuEntry, index: int): array[2, Option[(int, MenuEntry)]] =
  assert menu.kind == Submenu, "`menu` must be a submenu in order to get a slice."
  # This was kinda hacked together from an earlier function
  var tempResultMenus: array[2, Option[MenuEntry]]
  var tempResultIndex: array[2, int]
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
  
  for i, (idx, menu) in zip(tempResultIndex, tempResultMenus):
    if menu.isNone():
      result[i] = none (int, MenuEntry)
    else:
      result[i] = some (idx, menu.unsafeGet())

proc newMenuHandler*(): FiberIterator =
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
      block kinds: 
        case currentMenu.kind
        of Return:
          if historyStack.len() == 0:
            currentMenu = rootMenu
            currentSelection = 0
          else:
            (currentMenu, currentSelection) = historyStack.pop()
          yield next()
          break kinds
        of Submenu:
          # Draw a submenu
          # This is probably the most complicated menu type

          if isPressed(UP): currentSelection.inc
          if isPressed(DOWN): currentSelection.dec

          # Clamp selection to within range of submenus
          if currentSelection > currentMenu.submenus.high:
            currentSelection = currentMenu.submenus.low
          elif currentSelection < currentMenu.submenus.low:
            currentSelection = currentMenu.submenus.high

          if isPressed(ENTER):
            let next = currentMenu[currentSelection]
            # If the next index is out of bounds, then return to the previous menu.
            # It's a hack, but it should guard some edge cases as well.
            if next.isNone():
              echo "Something went wrong"
              currentMenu = nil
              break kinds
            if next.unsafeGet().kind != Return:
              # Push the current menu and current selection onto the history stack
              historyStack.add((currentMenu, currentSelection))
            currentMenu = next.unsafeGet()
            currentSelection = 0
            yield next()
            break kinds
          
          # Get which menus to display
          let display = getSubmenuSlice(currentMenu, currentSelection)


          LCD.clear()

          # For both menu entries, check if it exists. If so, draw it.
          for i, d in display:
            if d.isSome():
              # We know `d` exists, otherwise we wouldn't be doing this. 
              # So it's faster to do an `unsafeGet()`
              let (idx, menu) = d.unsafeGet()
              # Cursor is character 0x7E on the LCD
              let cursor = if idx == currentSelection: "\x7E" else: " "
              # Construct the string
              var finalString = (fmt"""{cursor}{(idx+1)}:{menu.label}""").alignLeft(16)
              # If the menu is a toggle, then get the value of it and add a checkbox
              if menu.kind == Toggle:
                let checkbox = if menu.getBool(): '\x02' else: '\x01'
                finalString[15] = checkbox
              # Output on the desired row.
              LCD[i] = finalString
        of Toggle:
          # Toggle the button then return
          currentMenu.toggleBool()
          currentMenu = RETURN_BUTTON
          break kinds
        of FunctionCall:
          # Call the callback then return
          currentMenu.callback()
          currentMenu = RETURN_BUTTON
          break kinds
        of IncDec:
          # Either increment, decrement, or return
          if isPressed(UP):
            currentMenu.increment()
          if isPressed(DOWN):
            currentMenu.decrement()
          if isPressed(ENTER):
            currentMenu = RETURN_BUTTON
            break kinds
          
          # Draw our info to the LCD
          LCD.clear()
          LCD[0] = "\x03\x04:" & currentMenu.label
          LCD[1] = currentMenu.display()
        yield untilAnyPressed({UP, DOWN, ENTER}) and waitCallback(proc(): bool = not menuSuspended)


#### MACROS
## Nim's macro system allows for near-complete control of the AST.
## In this section, I have implemented a domain-specific language (DSL)
## for adding menu entries.
## 
## `runnableExamples` blocks are not actual code, but are specific
## comments that only show up when creating doccumentation

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

proc retImpl(): NimNode =
  ## Return a return entry
  result = quote do:
    RETURN_BUTTON

proc submenuImpl(name: NimNode, body: NimNode): NimNode =
  var subnodes: seq[NimNode]    # Submenu nodes
  var hasReturn = false

  # iterate over every node in the body.
  # if it's a command, and it matches one of the
  for i in body:
    if i.kind != nnkCommand:
      if i.kind == nnkIdent:
        subnodes.add(i)   # `i` is likely a variable
      elif i.kind == nnkReturnStmt:
        subnodes.add(retImpl())   # `i` is a return statement.
        hasReturn = true
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
  
  if not hasReturn:
    warning "A `return` entry is recommended", body

macro submenu*(name: string, body: untyped): MenuEntry =
  ## Create a submenu consisting of other menu entries
  runnableExamples:
    let sub = submenu "Options":
      incdec "Brightness":
        increment:
          brightness += 1
        decrement:
          brightness -= 1
        display:
          $brightness
      callback "Show log":
        showLog()

  submenuImpl(name, body)

macro incdec*(name: string, body: untyped): MenuEntry =
  ## Create an increment-decrement menu entry
  runnableExamples:
    # Create an increment-decrement entry that controls
    # a `brightness` variable
    let lightBrightness = incdec "Brightness":
      increment:
        brightness += 1
      decrement:
        brightness -= 1
      display:
        $brightness

  incdecImpl(name, body)

macro callback*(name: string, body: untyped): MenuEntry =
  ## Create a callback menu entry
  runnableExamples:
    # Create a logging menu entry that outputs
    # the log to serial.
    let showLog = callback "Show log":
      echo "Some important data..."
      doLogStuff()
    
  callbackImpl(name, body)

macro toggle*(name: string, body: untyped): MenuEntry =
  ## Create a toggle menu entry
  runnableExamples:
    var lightIsOn = false

    let lightToggle = toggle "Toggle light":
      toggle:
        lightIsOn = not lightIsOn
        outputValue(lightIsOn)
      get:
        return lightIsOn

  toggleImpl(name, body)