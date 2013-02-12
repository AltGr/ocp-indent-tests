open Core.Std
open Async.Std

module Fd = Unix.Fd
module Inet_addr = Unix.Inet_addr
module Socket = Unix.Socket

let stdout_writer = Lazy.force Writer.stdout
let message s = Writer.write stdout_writer s

let finished () = shutdown 0

let port = 61111

let server =
  Tcp.Server.create (Tcp.on_port port)
    (fun _ reader writer ->
      Deferred.create (fun finished ->
        let rec loop () =
          upon (Reader.read_line reader) (function
            | `Ok query ->
              message (sprintf "Server got query: %s\n" query);
              Writer.write writer (sprintf "Response to %s\n" query);
              loop ()
            | `Eof ->
              Ivar.fill finished ();
              message "Server got EOF\n")
        in
        loop ()))
;;

let () =
  Core.Std.eprintf "TOP\n%!";
;;

let () =
  let queries = ["Hello"; "Goodbye"] in
  upon server (fun _ ->
    Core.Std.eprintf "IN SERVER\n%!";
    upon (Tcp.connect (Tcp.to_host_and_port "localhost" port)) (fun (reader, writer) ->
      let rec loop queries =
        match queries with
        | [] -> upon (Writer.close writer) (fun _ -> finished ())
        | query :: queries ->
          Writer.write writer query;
          Writer.write_char writer '\n';
          upon (Reader.read_line reader) (function
            | `Eof ->
              message "reader got unexpected Eof"
            | `Ok response ->
              message (sprintf "Client got response: %s\n" response);
              loop queries)
      in
      loop queries))
;;

let () = never_returns (Scheduler.go ())
