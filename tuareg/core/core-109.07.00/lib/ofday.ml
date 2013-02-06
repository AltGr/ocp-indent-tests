open Std_internal
open Time_internal.Helpers

(* Create an abstract type for Ofday to prevent us from confusing it with
   other floats.
*)
module Stable = struct
  module V1 = struct
    module T : sig
      type t = private float with bin_io
      include Comparable.S_common with type t := t
      include Hashable_binable    with type t := t
      include Robustly_comparable with type t := t
      include Stringable          with type t := t
      include Floatable           with type t := t
      val add : t -> Span.t -> t option
      val sub : t -> Span.t -> t option
      val diff : t -> t -> Span.t
      val of_span_since_start_of_day : Span.t -> t
      val to_span_since_start_of_day : t -> Span.t
      val start_of_day : t
      val end_of_day : t
    end = struct
      (* Number of seconds since midnight. *)
      include Float
      (* IF THIS REPRESENTATION EVER CHANGES, ENSURE THAT EITHER
         (1) all values serialize the same way in both representations, or
         (2) you add a new Time.Ofday version to stable.ml *)

      (* due to precision limitations in float we can't expect better than microsecond
         precision *)
      include Float_robust_compare.Make (struct let epsilon = 1E-6 end)

      let to_span_since_start_of_day t = Span.of_sec t

      (* ofday must be >= 0 and <= 24h *)
      let is_valid (t:t) =
        let t = to_span_since_start_of_day t in
        Span.(<=) Span.zero t && Span.(<=) t Span.day

      let of_span_since_start_of_day span =
        let module C = Float.Class in
        let s = Span.to_sec span in
        match Float.classify s with
        | C.Infinite -> invalid_arg "Ofday.of_span_since_start_of_day: infinite value"
        | C.Nan      -> invalid_arg "Ofday.of_span_since_start_of_day: NaN value"
        | C.Normal | C.Subnormal | C.Zero ->
          if not (is_valid s) then
            invalid_argf "Ofday out of range: %f" s ()
          else
            s
      ;;

      let start_of_day = 0.
      let end_of_day = of_span_since_start_of_day Span.day

      let add (t:t) (span:Span.t) =
        let t = t +. (Span.to_sec span) in
        if is_valid t then Some t else None

      let sub (t:t) (span:Span.t) =
        let t = t -. (Span.to_sec span) in
        if is_valid t then Some t else None

      let diff t1 t2 =
        Span.(-) (to_span_since_start_of_day t1) (to_span_since_start_of_day t2)
    end

    let create ?hr ?min ?sec ?ms ?us () =
      T.of_span_since_start_of_day (Span.create ?hr ?min ?sec ?ms ?us ())

    let to_parts t = Span.to_parts (T.to_span_since_start_of_day t)

    let to_string_gen ~drop_ms ~drop_us ~trim x =
      assert (if drop_ms then drop_us else true);
      let module P = Span.Parts in
      let parts = to_parts x in
      let dont_print_us = drop_us || (trim && parts.P.us = 0) in
      let dont_print_ms = drop_ms || (trim && parts.P.ms = 0 && dont_print_us) in
      let dont_print_s  = trim && parts.P.sec = 0 && dont_print_ms in
      let len =
        if dont_print_s then 5
        else if dont_print_ms then 8
        else if dont_print_us then 12
        else 15
      in
      let buf = String.create len in
      blit_string_of_int_2_digits buf ~pos:0 parts.P.hr;
      buf.[2] <- ':';
      blit_string_of_int_2_digits buf ~pos:3 parts.P.min;
      if dont_print_s then ()
      else begin
        buf.[5] <- ':';
        blit_string_of_int_2_digits buf ~pos:6 parts.P.sec;
        if dont_print_ms then ()
        else begin
          buf.[8] <- '.';
          blit_string_of_int_3_digits buf ~pos:9 parts.P.ms;
          if dont_print_us then ()
          else
            blit_string_of_int_3_digits buf ~pos:12 parts.P.us
        end
      end;
      buf
    ;;

    let to_string_trimmed t = to_string_gen ~drop_ms:false ~drop_us:false ~trim:true t

    let to_sec_string t = to_string_gen ~drop_ms:true ~drop_us:true ~trim:false t

    let to_millisec_string t = to_string_gen ~drop_ms:false ~drop_us:true ~trim:false t

    let of_string_iso8601_extended ?pos ?len str =
      let (pos, len) =
        match
          (Ordered_collection_common.get_pos_len ?pos ?len ~length:(String.length str))
        with
        | Result.Ok z    -> z
        | Result.Error s -> failwithf "Ofday.of_string_iso8601_extended: %s" s ()
      in
      try
        if len < 2 then failwith "len < 2"
        else begin
          let span =
            let hour = parse_two_digits str pos in
            if hour > 24 then failwith "hour > 24";
            let span = Span.of_hr (float hour) in
            if len = 2 then span
            else if len < 5 then failwith "2 < len < 5"
            else if str.[pos + 2] <> ':' then failwith "first colon missing"
            else
              let minute = parse_two_digits str (pos + 3) in
              if minute >= 60 then failwith "minute > 60";
              let span = Span.(+) span (Span.of_min (float minute)) in
              if hour = 24 && minute <> 0 then
                failwith "24 hours and non-zero minute";
              if len = 5 then span
              else if len < 8 then failwith "5 < len < 8"
              else if str.[pos + 5] <> ':' then failwith "second colon missing"
              else
                let second = parse_two_digits str (pos + 6) in
                if second >= 60 then failwith "second > 60";
                let span = Span.(+) span (Span.of_sec (float second)) in
                if hour = 24 && second <> 0 then
                  failwith "24 hours and non-zero seconds";
                if len = 8 then span
                else if len = 9 then failwith "length = 9"
                else
                  match str.[pos + 8] with
                  | '.' | ',' ->
                    let last = pos + len - 1 in
                    let rec loop pos subs =
                      let subs = subs * 10 + Char.get_digit_exn str.[pos] in
                      if pos = last then subs else loop (pos + 1) subs
                    in
                    let subs = loop (pos + 9) 0 in
                    if hour = 24 && subs <> 0 then
                      failwith "24 hours and non-zero subseconds"
                    else
                      Span.(+) span
                        (Span.of_sec (float subs /. (10. ** float (len - 9))))
                  | _ -> failwith "missing subsecond separator"
          in
          T.of_span_since_start_of_day span
        end
      with exn ->
        invalid_argf "Ofday.of_string_iso8601_extended(%s): %s"
          (String.sub str ~pos ~len) (Exn.to_string exn) ()
    ;;

    let small_diff =
      let hour = 3600. in
      (fun ofday1 ofday2 ->
        let ofday1 = Span.to_sec (T.to_span_since_start_of_day ofday1) in
        let ofday2 = Span.to_sec (T.to_span_since_start_of_day ofday2) in
        let diff   = ofday1 -. ofday2 in
        (*  d1 is in (-hour; hour) *)
        let d1 = Float.mod_float diff hour in
        (*  d2 is in (0;hour) *)
        let d2 = Float.mod_float (d1 +. hour) hour in
        let d = if d2 > hour /. 2. then d2 -. hour else d2 in
        Span.of_sec d)
    ;;

    (* There are a number of things that would be shadowed by this include because of the
       scope of Constrained_float.  These need to be defined below.  It's a an unfortunate
       situation because we would like to say include T, without shadowing. *)
    include T

    let to_string t = to_string_gen ~drop_ms:false ~drop_us:false ~trim:false t

    let pp ppf t = Format.pp_print_string ppf (to_string t)
    let () = Pretty_printer.register "Core.Ofday.pp"

    let of_string s =
      try
        let h,m,s =
          match String.split s ~on:':' with
          | [h; m; s] -> (h, m, Float.of_string s)
          | [h; m]    -> (h, m, 0.)
          | [hm]      ->
            if Int.(=) (String.length hm) 4 then
              ((String.sub hm ~pos:0 ~len:2), (String.sub hm ~pos:2 ~len:2), 0.)
            else failwith "No colon, expected string of length four"
          | _ -> failwith "More than two colons"
        in
        let h = Int.of_string h in
        let m = Int.of_string m in
        let is_end_of_day = Int.(h = 24 && m = 0) && Float.(s = 0.) in
        if not (Int.(h <= 23 && h >= 0) || is_end_of_day) then
          failwithf "hour out of valid range: %i" h ();
        if not Int.(m <= 59 && m >= 0) then
          failwithf "minutes out of valid range: %i" m ();
        if not Float.(s < 60. && s >= 0.) then
          failwithf "seconds out of valid range: %g" s ();
        Option.value_exn (add (create ~hr:h ~min:m ()) (Span.of_sec s))
      with exn ->
        invalid_argf "Ofday.of_string (%s): %s" s (Exn.to_string exn) ()
    ;;

    let t_of_sexp sexp =
      match sexp with
      | Sexp.Atom s ->
        begin try
                of_string s
          with
          | Invalid_argument s -> of_sexp_error ("Ofday.t_of_sexp: " ^ s) sexp
        end
      | _ -> of_sexp_error "Ofday.t_of_sexp" sexp
    ;;

    let sexp_of_t span = Sexp.Atom (to_string span)

    let of_float f = T.of_span_since_start_of_day (Span.of_sec f)
  end
end

include Stable.V1

module C = struct
  type t = T.t with bin_io

  let compare = compare

  type comparator = T.comparator

  let comparator = T.comparator

  (* In 108.06a and earlier, ofdays in sexps of Maps and Sets were floats.  Here we define
     [sexp_of_t] to produce the float form.  We also override [t_of_sexp] to accept either
     the float or the human-readable form.  Someday, once we think most programs are at or
     beyond 108.06a, and hence accept either form, we will change [sexp_of_t] here so that
     ofdays in Maps and Sets are represented by the human-readable form.  Then, someday
     after that, once we believe most programs are beyond that point, we will change
     [t_of_sexp] to only accept the human-readable form. *)
  let sexp_of_t t = Float.sexp_of_t (T.to_float t)

  let t_of_sexp sexp =
    match Option.try_with (fun () -> T.of_float (Float.t_of_sexp sexp)) with
    | Some t -> t
    | None -> t_of_sexp sexp
  ;;
end

module Map = Core_map.Make_binable_using_comparator (C)
module Set = Core_set.Make_binable_using_comparator (C)

  TEST =
  Pervasives.(=) (Set.sexp_of_t (Set.of_list [start_of_day]))
    (Sexp.List [Float.sexp_of_t (to_float start_of_day)])
;;

TEST =
  Set.equal (Set.of_list [start_of_day])
    (Set.t_of_sexp (Sexp.List [Float.sexp_of_t (to_float start_of_day)]))
;;

TEST =
  Set.equal (Set.of_list [start_of_day])
    (Set.t_of_sexp (Sexp.List [sexp_of_t start_of_day]))
;;
