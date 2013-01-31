open Core.Std
open Qtest_lib.Std
open Async.Std

exception Unexpected_sexps of Sexp.t list with sexp

let read_fail_and_continue () =
  let file = "reader_test.sexp" in
  Reader.file_contents file
  >>= fun expected_contents ->
  Reader.with_file file ~f:(fun reader ->
    try_with (fun () ->
      Reader.read_until reader (`Pred (fun _ -> assert false)) ~keep_delim:false)
    >>= function
    | Ok _ -> assert false
    | Error _ ->
      Reader.contents reader
      >>| fun got_contents ->
      assert (got_contents = expected_contents);
  (* Async_core.Debug.log "contents" s <:sexp_of< string >> *)
  )
;;

let test_sexps reader =
  let sexps = Reader.read_sexps reader in
  Pipe.to_list sexps
  >>| fun sexps ->
  let last = List.hd_exn (List.rev sexps) in
  let last = Sexp.to_string last in
  assert_string_equal "(last sexp)" last
;;

let read_sexps_file () =
  Reader.with_file "reader_test.sexp" ~f:(fun reader ->
    test_sexps reader)
;;

let read_sexps_pipe () =
  Reader.with_file "reader_test.sexp" ~f:(fun reader ->
    let sexps = Reader.read_sexps reader in
    Unix.pipe (Info.of_string "reader_test")
    >>= function (`Reader reader_fd, `Writer writer_fd) ->
      let writer = Writer.create writer_fd in
      Pipe.iter sexps ~f:(fun sexp -> Writer.write_sexp writer sexp; Writer.flushed writer)
      >>= fun () ->
      Writer.close writer
      >>= fun () ->
      let reader = Reader.create reader_fd in
      test_sexps reader)
;;

let load_sexps_fail () =
  Reader.load_sexps "reader_test.sexp" (fun _ -> assert false)
  >>| function
  | Error _ -> ()
  | Ok _ -> assert false
;;

let reader_of_string ?buf_len str =
  Unix.pipe (Info.of_string "reader test")
  >>= fun (`Reader reader_fd, `Writer writer_fd) ->
  let reader = Reader.create reader_fd ?buf_len in
  let writer = Writer.create writer_fd in
  Writer.write writer str;
  don't_wait_for (Writer.close writer);
  return reader
;;

let read_one_chunk_at_a_time_until_eof_errors () =
  let is_error = Result.is_error in
  let is_ok = Result.is_ok in
  let check (result_is_correct, handle_chunk) =
    reader_of_string (String.create 10)
    >>= fun reader ->
    try_with (fun () ->
      Reader.read_one_chunk_at_a_time_until_eof reader ~handle_chunk:(fun _ ~pos:_ ~len ->
        return (`Consumed (handle_chunk len))))
    >>= fun result ->
    Reader.close reader
    >>| fun () ->
    assert (result_is_correct result)
  in
  Deferred.List.iter ~f:check
    [
      is_error, (fun _   -> (-1,      `Need_unknown));
      is_ok,    (fun _   -> (0,       `Need_unknown));
      is_ok,    (fun len -> (len,     `Need_unknown));
      is_error, (fun len -> (len + 1, `Need_unknown));
      is_error, (fun _   -> (-1,      `Need_unknown));

      is_error, (fun _   -> (0, `Need (-1))     );
      is_error, (fun _   -> (0, `Need 0)        );
      is_error, (fun len -> (0, `Need len)      );
      is_ok,    (fun len -> (0, `Need (len + 1)));

      is_error, (fun len -> (len, `Need (-1)) );
      is_error, (fun len -> (len, `Need 0)    );
      is_ok,    (fun len -> (len, `Need 1)    );
    ]
;;

let read_partial_chunks () =
  (* Read chunk by chunk without consuming everything available each time. *)
  reader_of_string "0123456789" ~buf_len:5
  >>= fun reader ->
  let step = ref 0 in
  Reader.read_one_chunk_at_a_time_until_eof reader
    ~handle_chunk:(fun buf ~pos ~len ->
      incr step;
      match !step with
      | 1 ->
        assert_int_equal 0 pos;
        assert_int_equal 5 len;
        assert_string_equal "01234" (Bigstring.to_string buf ~pos ~len);
        return (`Consumed (4, `Need_unknown))
      | 2 ->
        assert_int_equal 0 pos;
        assert_int_equal 5 len;
        assert_string_equal "45678" (Bigstring.to_string buf ~pos ~len);
        return (`Consumed (3, `Need_unknown))
      | 3 ->
        assert_int_equal 0 pos;
        assert_int_equal 3 len;
        assert_string_equal "789" (Bigstring.to_string buf ~pos ~len);
        return (`Stop ())
      | n ->
        raise (Test.Test_failure (Sexp.List [
                Sexp.Atom "Step greater than 3";
                sexp_of_int n;
              ])))
  >>= fun result ->
  assert_equal (`Stopped ()) result
    ~sexp_of_t:<:sexp_of< unit Reader.read_one_chunk_at_a_time_until_eof_result >>;
  Reader.close reader
;;

let read_blocks_ending_with_incomplete_one () =
  (* Read blocks of length 4, ending with an incomplete one. *)
  reader_of_string "aaaabbbbcc" ~buf_len:3
  >>= fun reader ->
  Reader.read_one_chunk_at_a_time_until_eof reader
    ~handle_chunk:(fun buf ~pos ~len ->
      ignore (buf, pos);
      return (`Consumed (len - len mod 4, `Need 4)))
  >>= fun result ->
  assert_equal (`Eof_with_unconsumed_data "cc") result
    ~sexp_of_t:<:sexp_of< unit Reader.read_one_chunk_at_a_time_until_eof_result >>;
  Reader.close reader
;;

let read_messages () =
  (* Read nessages composed of a size (on 1 byte) followed by a body of this size. *)
  let data = ["xyz"; "abcdefgh"] in
  reader_of_string
    (String.concat
       (List.map data
          ~f:(fun s ->
            String.make 1 (Char.of_int_exn (String.length s)) ^ s)))
    ~buf_len:6
  >>= fun reader ->
  let state = ref `Size (* [`Size] or [`Body body_size] *) in
  let messages = ref [] in
  Reader.read_one_chunk_at_a_time_until_eof reader
    ~handle_chunk:(fun buf ~pos ~len ->
      let orig_len = len in
      let rec loop ~pos ~len =
        match !state with
        | `Size ->
          if len < 1 then
            return (`Consumed (orig_len - len, `Need 1))
          else begin
            let size = Char.to_int buf.{pos} in
            state := `Body size;
            loop ~pos:(pos + 1) ~len:(len - 1)
          end
        | `Body size ->
          if len < size then
            return (`Consumed (orig_len - len, `Need size))
          else begin
            let msg = Bigstring.to_string buf ~pos ~len:size in
            messages := msg :: !messages;
            state := `Size;
            loop ~pos:(pos + size) ~len:(len - size)
          end
      in
      loop ~pos ~len)
  >>= fun result ->
  assert_equal `Eof result
    ~sexp_of_t:<:sexp_of< unit Reader.read_one_chunk_at_a_time_until_eof_result >>;
  assert_equal (List.rev data) !messages
    ~sexp_of_t:<:sexp_of< string list >>;
  Reader.close reader
;;

let rec find_zero buf ~pos ~max =
  if pos = max then
    None
  else if buf.{pos} = '\000' then
    Some pos
  else
    find_zero buf ~pos:(pos + 1) ~max

let read_zero_terminated_strings () =
  (* Read a sequence of zero-terminated strings. The size of each string is not known in
     advance. *)
  let data = ["foo"; "bar"; "a long string"; "ocaml"; "core"; "async"] in
  reader_of_string
    (String.concat
       (List.map data ~f:(fun s -> s ^ "\000")))
    ~buf_len:2
  >>= fun reader ->
  let strings = ref [] in
  let start = ref 0 in
  Reader.read_one_chunk_at_a_time_until_eof reader
    ~handle_chunk:(fun buf ~pos ~len ->
      let orig_len = len in
      let rec loop ~pos ~len =
        match find_zero buf ~pos:(pos + !start) ~max:(pos + len) with
        | None ->
          start := len; (* restart the search after current data. *)
          return (`Consumed (orig_len - len, `Need_unknown))
        | Some pos' ->
          let str_len = pos' - pos in
          let str = Bigstring.to_string buf ~pos ~len:str_len in
          start := 0;
          strings := str :: !strings;
          loop ~pos:(pos' + 1) ~len:(len - str_len - 1)
      in
      loop ~pos ~len)
  >>= fun result ->
  assert_equal `Eof result
    ~sexp_of_t:<:sexp_of< unit Reader.read_one_chunk_at_a_time_until_eof_result >>;
  assert_equal (List.rev data) !strings
    ~sexp_of_t:<:sexp_of< string list >>;
  Reader.close reader
;;

let tests = [
  "Reader_test.load_sexps_fail", load_sexps_fail;
  "Reader_test.read_blocks_ending_with_incomplete_one",
  read_blocks_ending_with_incomplete_one;
  "Reader_test.read_fail_and_continue", read_fail_and_continue;
  "Reader_test.read_messages", read_messages;
  "Reader_test.read_partial_chunks", read_partial_chunks;
  "Reader_test.read_one_chunk_at_a_time_until_eof_errors",
  read_one_chunk_at_a_time_until_eof_errors;
  "Reader_test.read_sexps_file", read_sexps_file;
  "Reader_test.read_sexps_pipe", read_sexps_pipe;
  "Reader_test.read_zero_terminated_strings", read_zero_terminated_strings;
]
