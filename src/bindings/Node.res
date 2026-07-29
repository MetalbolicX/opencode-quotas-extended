@val external processExit: int => unit = "process.exit"

type settlement<'a> = {
  status: [ #fulfilled | #rejected ],
  value: 'a,
  reason: 'a,
}

@val
external promiseAllSettled: array<promise<'a>> => promise<array<settlement<'a>>> = "Promise.allSettled"
