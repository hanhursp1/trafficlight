import tasks

type
  AwaitedTaskObj[T] = object of Task
    returnVal*: ptr T
  AwaitedTask*[T] = ref AwaitedTaskObj[T]