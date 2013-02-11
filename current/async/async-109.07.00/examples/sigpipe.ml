open Core.Std
open Async.Std

let (in_fd, out_fd) = Unix.socketpair ()

let () =
  upon (Unix.close in_fd) (fun () ->
    let w = Writer.create out_fd in
    Writer.write w "hello\n")

let () = never_returns (Scheduler.go ())
