import picostdlib/[time]
import std/[lists]

#### Fibers! (technically not actually, they're really coroutines)
##
## A simple means of implementing cooperative multitasking.
## Fibers can yield and return based on a number of conditions,
## such as after a set delay, or after the conclusion of another Fiber


#### Fiber Base
type
  FiberIterator* = iterator(): FiberYield   ## An iterator which yields a `FiberYield`

  ## The base `FiberYield` type. It is considered standard practice
  ## to separate `ref` objects into a separate ref and non-ref version.
  ## 
  ## A `ref` is a reference-counted heap-allocated variable.
  ## `object of RootObj` allows that object to be inherited from.
  FiberYieldObj = object of RootObj
  FiberYield* = ref FiberYieldObj

  ## Fiber object, containing both the current process and the last yield.
  FiberObj = object of RootObj
    currentFiber*: FiberIterator
    lastYield*: FiberYield
  Fiber* = ref FiberObj

## FiberYield base methods. the `method` keyword in Nim denotes a
## dynamic-dispatch function, as opposed to `proc` or `func`, which
## are static-dispatch.
method ready*(this: FiberYield): bool {.base.} =
  ## Check if the fiber `this` belongs to is ready to be run
  ## this frame.
  true

proc next*(): FiberYield =
  ## Yield until the next frame.
  result.new()

## Fiber base functions
proc finished*(this: var Fiber): bool =
  ## Check if a fiber is finished.
  ## If it is, then free the iterator inside it.
  if this.currentFiber == nil:
    true
  elif this.currentFiber.finished():
    this.currentFiber = nil
    true
  else: false

proc ready*(this: var Fiber): bool =
  ## Check if the fiber should be run this frame.
  if this.finished(): false
  else: this.lastYield.ready()

proc run*(this: var Fiber) =
  ## Run the fiber.
  if this.ready() and not this.finished():
    this.lastYield = this.currentFiber()

proc delete*(this: var Fiber) =
  ## Delete the fiber.
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
  ## Yield for `delay` microseconds
  result.new()
  result.endTime = timeUs64() + delay

proc waitMS*(delay: uint64): FiberYieldTime =
  ## Yield for `delay` milliseconds
  waitUS(delay * 1000)

## FiberYieldFiber, yields until another Fiber is finished
type
  FiberYieldFiberObj {.acyclic.} = object of FiberYield
    fiber*: Fiber
  FiberYieldFiber* = ref FiberYieldFiberObj

method ready*(this: FiberYieldFiber): bool =
  this.fiber.finished()

proc waitFiber*(Fiber: Fiber): FiberYieldFiber =
  ## Yield until another fiber completes.
  result.new()
  result.fiber = Fiber

## FiberYieldCondition, yields when a callback function returns true
type
  FiberYieldConditionObj = object of FiberYield
    callback*: proc(): bool
  FiberYieldCondition* = ref FiberYieldConditionObj

method ready*(this: FiberYieldCondition): bool =
  this.callback()

proc waitCallback*(callback: proc(): bool): FiberYieldCondition =
  ## Yield until `callback` evaluates to `true`
  result.new()
  result.callback = callback

## FiberYieldOr, yields until one of two conditions is ready.
type
  FiberYieldOrObj = object of FiberYield
    yieldA, yieldB: FiberYield
  FiberYieldOr* = ref FiberYieldOrObj

method ready*(this: FiberYieldOr): bool =
  this.yieldA.ready() or this.yieldB.ready()

proc `or`*(l, r: FiberYield): FiberYieldOr =
  ## Yield until either condition is ready
  result.new()
  result.yieldA = l
  result.yieldB = r

## FiberYieldAnd, yields until both fibers are ready.
type
  FiberYieldAndObj = object of FiberYield
    yieldA, yieldB: FiberYield
  FiberYieldAnd* = ref FiberYieldAndObj

method ready*(this: FiberYieldAnd): bool =
  this.yieldA.ready() and this.yieldB.ready()

proc `and`*(l, r: FiberYield): FiberYieldAnd =
  ## Yield until both conditions are ready
  result.new()
  result.yieldA = l
  result.yieldB = r

#### Fiber Scheduler
## Really simple, just iterate over all Fibers and check if they're ready or finished

type
  FiberPool* = object
    ## Uses the `DoublyLinkedList` type from Nim's std lib to store all currently running fibers.
    ## We use a doubly linked list to allow us to delete a fiber in the middle of the queue in O(n) time.
    fibers*: DoublyLinkedList[Fiber]

proc run*(this: var FiberPool) =
  ## Run through a fiber pool once.
  for node in this.fibers.nodes():
    if node.value.finished():
      this.fibers.remove(node)
    if node.value.ready():
      node.value.run()

proc add*(this: var FiberPool, fiber: Fiber) =
  ## Add `Fiber` to the pool
  this.fibers.add(fiber)

## Global fiber pool
var globalFiberPool: FiberPool

proc addFiber*(fiber: FiberIterator): Fiber {.discardable.} =
  ## Add a fiber iterator to the global pool
  result.new()
  result.currentFiber = fiber
  result.lastYield = next()
  globalFiberPool.add(result)

proc addFiber*(fiber: Fiber) =
  ## Add an already running fiber to the global pool.
  globalFiberPool.add(fiber)

proc runFibers*() =
  ## Run through the global fiber pool once
  globalFiberPool.run()