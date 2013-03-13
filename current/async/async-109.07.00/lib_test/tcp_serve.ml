open Core.Std ;;
open Async.Std ;;

let server_read_test = Ivar.create () ;;
let server_write_test = Ivar.create () ;;
let server_close_test = Ivar.create () ;;
let client_read_test = Ivar.create () ;;
let client_write_test = Ivar.create () ;;
let client_close_test = Ivar.create () ;;
let client_eof_test = Ivar.create () ;;

let all_tests_success = Ivar.create () ;;

let tcp_serve_test () =
  begin
    Ivar.read server_read_test >>> fun () ->
    Ivar.read server_write_test >>> fun () ->
    Ivar.read server_close_test >>> fun () ->
    Ivar.read client_read_test >>> fun () ->
    Ivar.read client_write_test >>> fun () ->
    Ivar.read client_eof_test >>> fun () ->
    Ivar.read client_close_test >>> fun () ->

    Ivar.fill all_tests_success ()
  end;
  upon (after (sec 35.)) (fun () ->
    let check ivar s = if Ivar.is_empty ivar then failwithf "tcp_serve_test: %s" s () in
    check client_write_test "client_write_test";
    check server_read_test "server_read_test";
    check server_write_test "server_write_test";
    check client_read_test "client_read_test";
    check client_eof_test "server_eof_test";
    check server_close_test "server_close_test";
    check client_close_test "client_close_test";

    check all_tests_success "all_tests_success!?!"
  );
  Tcp.Server.create Tcp.on_port_chosen_by_os
    ~buffer_age_limit:(`At_most (sec 1.))
    ~on_handler_error:(`Call (fun _a e ->
                         failwithf "Tcp.Server.create: handler error: %s" (Exn.to_string e) ()
                       ))
    (fun inet reader writer ->
      Writer.close_finished writer >>> (fun () -> Ivar.fill server_close_test ());

      let echo line =
        Writer.write
          writer
          (sprintf "%s: %s\n"
             (Unix.Inet_addr.to_string (Socket.Address.Inet.addr inet))
             line);
      in
      Reader.read_line reader
      >>= function
      | `Eof -> failwith "server: read test1: premature EOF"
      | `Ok line ->
        Ivar.fill server_read_test ();
        echo line;
        Reader.read_line reader
        >>| function
        | `Eof -> failwith "server: read test2: premature EOF"
        | `Ok line ->
          Ivar.fill server_write_test ();
          echo line
    )
  >>= fun server ->
  Tcp.with_connection (Tcp.to_host_and_port "localhost" (Tcp.Server.listening_on server))
    (fun reader writer ->
      Writer.close_finished writer >>> (fun () -> Ivar.fill client_close_test ());

      Writer.write writer "foo\n";
      Ivar.fill client_write_test ();

      Reader.read_line reader
      >>= function
      | `Eof -> failwith "client: read test: premature EOF"
      | `Ok s ->
        ignore s;
        Ivar.fill client_read_test ();
        Writer.write writer "bar\n";
        Reader.read_line reader
        >>= function
        | `Eof -> failwith "client: read test: premature EOF"
        | `Ok s ->
          ignore s;
          Reader.read_line reader
          >>| function
          | `Ok s -> failwithf "client: expected EOF, instead got: %s" s ()
          | `Eof -> Ivar.fill client_eof_test ()
    )
  >>= fun () ->
  Ivar.read all_tests_success
  >>= fun () ->
  Tcp.Server.close server
;;

let tests =
  [ "Tcp_serve_read_write_close", tcp_serve_test;
  ]
;;
