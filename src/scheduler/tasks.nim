import picostdlib/[time]
import std/[lists, macros]

#### Task Base
type
  TaskYieldObj = object of RootObj
  TaskYield* = ref TaskYieldObj

  TaskObj = object
    currentTask*: iterator(): TaskYield
    lastYield*: TaskYield
  Task = ref TaskObj

## TaskYield base methods
method ready*(this: TaskYield): bool {.base.} =
  true

## Task base functions
proc finished*(this: var Task): bool =
  if this.currentTask == nil:
    true
  elif this.currentTask.finished():
    this.currentTask = nil
    true
  else: false

proc ready*(this: var Task): bool =
  if this.finished(): false
  else: this.lastYield.ready()

proc run*(this: var Task) =
  if this.ready() and not this.finished():
    this.lastYield = this.currentTask()

#### Types of yields

## TaskYieldTime, yields for at least `delay` microseconds
type
  TaskYieldTimeObj = object of TaskYield
    timeStart*:   uint64
    delay*:       uint64
  TaskYieldTime* = ref TaskYieldTimeObj

method ready*(this: TaskYieldTime): bool =
  (timeUs64() - this.timeStart) > this.delay

proc yieldTimeUS*(delay: uint64): TaskYieldTime =
  result.new()
  result.timeStart = timeUs64()
  result.delay = delay

proc yieldTimeMS*(delay: uint64): TaskYieldTime =
  result.new()
  result.timeStart = timeUs64()
  result.delay = delay * 1000

## TaskYieldTask, yields until another task is finished
type
  TaskYieldTaskObj {.acyclic.} = object of TaskYield
    task*: Task
  TaskYieldTask* = ref TaskYieldTaskObj

method ready*(this: TaskYieldTask): bool =
  this.task.ready()

proc yieldTask*(task: Task): TaskYieldTask =
  result.new()
  result.task = task

#### Task Scheduler
## Really simple, just iterate over all tasks and check if they're ready or finished

type
  TaskPool* = object
    tasks*: DoublyLinkedList[Task]

proc run*(this: var TaskPool) =
  for node in this.tasks.nodes():
    if node.value.finished():
      this.tasks.remove(node)
    if node.value.ready():
      node.value.run()

macro task*(def: untyped, body: untyped): untyped =
  echo treeRepr(def)