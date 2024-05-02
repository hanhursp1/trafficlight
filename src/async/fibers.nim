import picostdlib/[time]
import std/[lists]

#### Fibers! (technically not actually, they're really coroutines)
##
## A simple means of implementing cooperative multitasking.
## Fibers can yield and return based on a number of conditions,
## such as after a set delay, or after the conclusion of another Fiber


#### Fiber Base
type
  FiberIterator* = iterator(): FiberYield

  FiberYieldObj = object of RootObj
  FiberYield* = ref FiberYieldObj

  FiberObj = object of RootObj
    currentFiber*: FiberIterator
    lastYield*: FiberYield
  Fiber* = ref FiberObj

## FiberYield base methods
method ready*(this: FiberYield): bool {.base.} =
  true

proc next*(): FiberYield =
  result.new()

## Fiber base functions
proc finished*(this: var Fiber): bool =
  if this.currentFiber == nil:
    true
  elif this.currentFiber.finished():
    this.currentFiber = nil
    true
  else: false

proc ready*(this: var Fiber): bool =
  if this.finished(): false
  else: this.lastYield.ready()

proc run*(this: var Fiber) =
  if this.ready() and not this.finished():
    this.lastYield = this.currentFiber()

proc delete*(this: var Fiber) =
  this.currentFiber = nil
  this.lastYield = nil

#### Types of yields

## FiberYieldTime, yields for at least `delay` microseconds
type
  FiberYieldTimeObj = object of FiberYield
    endTime*:   uint64
    delay*:       uint64
  FiberYieldTime* = ref FiberYieldTimeObj

method ready*(this: FiberYieldTime): bool =
  this.endTime <= timeUs64()

proc waitUS*(delay: uint64): FiberYieldTime =
  result.new()
  result.endTime = timeUs64() + delay

proc waitMS*(delay: uint64): FiberYieldTime =
  waitUS(delay * 1000)

## FiberYieldFiber, yields until another Fiber is finished
type
  FiberYieldFiberObj {.acyclic.} = object of FiberYield
    Fiber*: Fiber
  FiberYieldFiber* = ref FiberYieldFiberObj

method ready*(this: FiberYieldFiber): bool =
  this.Fiber.finished()

proc waitFiber*(Fiber: Fiber): FiberYieldFiber =
  result.new()
  result.Fiber = Fiber

## FiberYieldCondition, yields when a callback function returns true
type
  FiberYieldConditionObj = object of FiberYield
    callback*: proc(): bool
  FiberYieldCondition* = ref FiberYieldConditionObj

method ready*(this: FiberYieldCondition): bool =
  this.callback()

proc waitCallback*(callback: proc(): bool): FiberYieldCondition =
  result.new()
  result.callback = callback

type
  FiberYieldOrObj = object of FiberYield
    yieldA, yieldB: FiberYield
  FiberYieldOr* = ref FiberYieldOrObj

method ready*(this: FiberYieldOr): bool =
  this.yieldA.ready() or this.yieldB.ready()

proc `or`*(l, r: FiberYield): FiberYieldOr =
  result.new()
  result.yieldA = l
  result.yieldB = r

#### Fiber Scheduler
## Really simple, just iterate over all Fibers and check if they're ready or finished

type
  FiberPool* = object
    Fibers*: DoublyLinkedList[Fiber]

proc run*(this: var FiberPool) =
  for node in this.Fibers.nodes():
    if node.value.finished():
      this.Fibers.remove(node)
    if node.value.ready():
      node.value.run()

proc add*(this: var FiberPool, Fiber: Fiber) =
  this.Fibers.add(Fiber)

var defaultFiberPool: FiberPool

proc addFiber*(Fiber: FiberIterator): Fiber {.discardable.} =
  result.new()
  result.currentFiber = Fiber
  result.lastYield = next()
  defaultFiberPool.add(result)

proc addFiber*(Fiber: Fiber) =
  defaultFiberPool.add(Fiber)

proc runFibers*() =
  defaultFiberPool.run()