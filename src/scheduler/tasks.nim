import picostdlib/[time]
import std/[lists]

#### Tasks!
##
## A simple means of implementing cooperative multitasking
## Tasks can yield and return based on a number of conditions,
## such as after a set delay, or after the conclusion of another task


#### Task Base
type
  TaskIterator* = iterator(): TaskYield

  TaskYieldObj = object of RootObj
  TaskYield* = ref TaskYieldObj

  TaskObj = object
    currentTask*: TaskIterator
    lastYield*: TaskYield
  Task = ref TaskObj

## TaskYield base methods
method ready*(this: TaskYield): bool {.base.} =
  true

proc yieldNext*(): TaskYield =
  result.new()

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

proc delete*(this: var Task) =
  this.currentTask = nil
  this.lastYield = nil

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
  this.task.finished()

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

proc add*(this: var TaskPool, task: Task) =
  this.tasks.add(task)

var defaultTaskPool: TaskPool

proc addTask*(task: TaskIterator): Task =
  result.new()
  result.currentTask = task
  result.lastYield = yieldNext()
  defaultTaskPool.add(result)

proc addTask*(task: Task) =
  defaultTaskPool.add(task)

proc runTasks*() =
  defaultTaskPool.run()