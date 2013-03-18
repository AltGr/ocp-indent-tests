open Std_internal
open Time_internal.Helpers
module Time  = Time_internal.T
module Int63 = Core_int63

(* Create a local private date type to ensure that all dates are created via
   Date.create_exn.
*)
module Stable = struct
  module V1 = struct
    module T : sig
      type t = private { y: int; m: Month.Stable.V1.t; d: int; }
      with bin_io

      val create_exn : y:int -> m:Month.Stable.V1.t -> d:int -> t
    end = struct
      type t = { y: int; m: Month.Stable.V1.t; d: int; } with bin_io

      let is_leap_year year =
        (year mod 4 = 0 && not (year mod 100 = 0))
        || year mod 400 = 0

      let create_exn ~y:year ~m:month ~d:day =
        let invalid msg =
          invalid_argf "Date.create_exn ~y:%d ~m:%s ~d:%d error: %s"
            year (Month.to_string month) day msg ()
        in
        if year < 0 || year > 9999 then invalid "year outside of [0..9999]";
        if day <= 0 then invalid "day <= 0";
        begin match month with
        | Month.Apr | Month.Jun | Month.Sep | Month.Nov ->
          if day > 30 then invalid "30 day month violation"
        | Month.Feb ->
          if is_leap_year year then begin
            if day > 29 then invalid "29 day month violation" else ()
          end else if day > 28 then begin
            invalid "28 day month violation"
          end else ()
        | Month.Jan | Month.Mar | Month.May | Month.Jul | Month.Aug | Month.Oct
        | Month.Dec ->
          if day > 31 then invalid "31 day month violation"
        end;
        { y = year; m = month; d = day; }
    end

    include T

    (** YYYY-MM-DD *)
    let to_string_iso8601_extended t =
      let buf = String.create 10 in
      blit_string_of_int_4_digits buf ~pos:0 t.y;
      buf.[4] <- '-';
      blit_string_of_int_2_digits buf ~pos:5 (Month.to_int t.m);
      buf.[7] <- '-';
      blit_string_of_int_2_digits buf ~pos:8 t.d;
      buf
    ;;

    let to_string = to_string_iso8601_extended

    (** YYYYMMDD *)
    let to_string_iso8601_basic t =
      let buf = String.create 8 in
      blit_string_of_int_4_digits buf ~pos:0 t.y;
      blit_string_of_int_2_digits buf ~pos:4 (Month.to_int t.m);
      blit_string_of_int_2_digits buf ~pos:6 t.d;
      buf
    ;;

    (** MM/DD/YYYY *)
    let to_string_american t =
      let buf = String.create 10 in
      blit_string_of_int_2_digits buf ~pos:0 (Month.to_int t.m);
      buf.[2] <- '/';
      blit_string_of_int_2_digits buf ~pos:3 t.d;
      buf.[5] <- '/';
      blit_string_of_int_4_digits buf ~pos:6 t.y;
      buf
    ;;

    let parse_year4 str pos = parse_four_digits str pos

    let parse_month str pos = Month.of_int_exn (parse_two_digits str pos)

    let parse_day str pos = parse_two_digits str pos

    (** YYYYMMDD *)
    let of_string_iso8601_basic str ~pos =
      if pos + 8 > String.length str then
        invalid_arg "Date.of_string_iso8601_basic: pos + 8 > string length";
      create_exn
        ~y:(parse_year4 str pos)
        ~m:(parse_month str (pos + 4))
        ~d:(parse_day str (pos + 6))
    ;;

    (* WARNING: if you are going to change this function in a material way, be sure you
       understand the implications of working in Stable *)
    let of_string s =
      let invalid () = failwith ("invalid date: " ^ s) in
      let ensure b = if not b then invalid () in
      let month_num ~year ~month ~day =
        create_exn
          ~y:(parse_year4 s year)
          ~m:(parse_month s month)
          ~d:(parse_day s day)
      in
      let month_abrv ~year ~month ~day =
        create_exn
          ~y:(parse_year4 s year)
          ~m:(Month.of_string (String.sub s ~pos:month ~len:3))
          ~d:(parse_day s day)
      in
      if String.contains s '/' then begin
        let y,m,d =
          match String.split s ~on:'/' with
          | [a; b; c] ->
            if String.length a = 4 then a,b,c (* y/m/d *)
            else c,a,b (* m/d/y *)
          | _ -> invalid ()
        in
        let year = Int.of_string y in
        let year =
          if year >= 100 then year
          else if year < 75 then 2000 + year
          else 1900 + year
        in
        let month = Month.of_int_exn (Int.of_string m) in
        let day = Int.of_string d in
        create_exn ~y:year ~m:month ~d:day
      end else if String.contains s '-' then begin
        (* yyyy-mm-dd *)
        ensure (String.length s = 10 && s.[4] = '-' && s.[7] = '-');
        month_num ~year:0 ~month:5 ~day:8;
      end else if String.contains s ' ' then begin
        if (String.length s = 11 && s.[2] = ' ' && s.[6] = ' ') then
          (* DD MMM YYYY *)
          month_abrv ~day:0 ~month:3 ~year:7
        else begin
          (* YYYY MMM DD *)
          ensure (String.length s = 11 && s.[4] = ' ' && s.[8] = ' ');
          month_abrv ~day:9 ~month:5 ~year:0;
        end
      end else if String.length s = 9 then begin
        (* DDMMMYYYY *)
        month_abrv ~day:0 ~month:2 ~year:5;
      end else if String.length s = 8 then begin
        (* assume YYYYMMDD *)
        month_num ~year:0 ~month:4 ~day:6
      end else invalid ()
    ;;

    let of_string s =
      try of_string s with
      | exn -> invalid_argf "Date.of_string (%s): %s" s (Exn.to_string exn) ()
    ;;

    module Sexpable = struct

      module Old_date = struct
        type t = { y: int; m: int; d: int; } with sexp

        let to_date t = T.create_exn ~y:t.y ~m:(Month.of_int_exn t.m) ~d:t.d
      end

      let t_of_sexp = function
        | Sexp.Atom s -> of_string s
        | Sexp.List _ as sexp -> Old_date.to_date (Old_date.t_of_sexp sexp)
      ;;

      let t_of_sexp s =
        try
          t_of_sexp s
        with
        | (Sexplib.Conv.Of_sexp_error _) as exn -> raise exn
        | Invalid_argument a -> Sexplib.Conv.of_sexp_error a s
      ;;

      let sexp_of_t t = Sexp.Atom (to_string t)
    end
    include Sexpable

    include Comparable.Make_binable (struct
              include T
              include Sexpable
              include Binable

              let compare t1 t2 =
                let n = Int.compare t1.y t2.y in
                if n <> 0 then n
                else
                  let n = Month.compare t1.m t2.m in
                  if n <> 0 then n
                  else Int.compare t1.d t2.d
              ;;
            end)
  end

  TEST_MODULE "Date.V1" = Stable_unit_test.Make (struct
                            include V1

                            let equal = (=)

                            let tests =
                              let date y m d = create_exn ~y ~m ~d in
                              [ date 1066 Month.Oct 16, "1066-10-16", "\254\042\004\009\016";
                                date 1955 Month.Nov  5, "1955-11-05", "\254\163\007\010\005";
                                date 2012 Month.Apr 19, "2012-04-19", "\254\220\007\003\019";
                              ]
                          end)
end

include Stable.V1

include (Hashable.Make_binable (struct
           include T
           include Sexpable
           include Binable
           let compare = compare
           let hash (t : t) = Hashtbl.hash t
         end) : Hashable.S_binable with type t := t)

let pp ppf date = Format.pp_print_string ppf (to_string date)
let () = Pretty_printer.register "Core.Date.pp"

let day t = t.d
let month t = t.m
let year t = t.y

let of_tm tm =
  create_exn
    ~y:(tm.Unix.tm_year + 1900)
    ~m:(Month.of_int_exn (tm.Unix.tm_mon + 1))
    ~d:tm.Unix.tm_mday
;;

(* The Days module is used for calculations that involve adding or removing a known number
   of days from a date.  Internally the date is translated to a day number, the days are
   added, and the new date is returned.  Those interested in the math can read:

   http://alcor.concordia.ca/~gpkatch/gdate-method.html

   note: unit tests are in lib_test/time_test.ml
*)
module Days : sig
  val add_days : t -> int -> t
  val diff : t -> t -> int
end = struct
  open Int

  let of_year y =
    365 * y + y / 4 - y / 100 + y / 400

  let of_date date =
    let m = (Month.to_int date.m + 9) % 12 in
    let y = date.y - m / 10 in
    of_year y + (m * 306 + 5) / 10 + (date.d - 1)
  ;;

  let c_10_000    = Int63.of_int 10_000
  let c_14_780    = Int63.of_int 14_780
  let c_3_652_425 = Int63.of_int 3_652_425
  let to_date days =
    let y =
      let open Int63 in
      to_int_exn ((c_10_000 * of_int days + c_14_780) / c_3_652_425)
    in
    let ddd = days - of_year y in
    let y, ddd =
      if (ddd < 0)
      then
        let y = y - 1 in
        (y, days - of_year y)
      else (y, ddd)
    in
    let mi = (100 * ddd + 52) / 3_060 in
    let y = y + (mi + 2) / 12 in
    let m = (mi + 2) % 12 + 1 in
    let d = ddd - (mi * 306 + 5) / 10 + 1 in
    create_exn ~y ~m:(Month.of_int_exn m) ~d
  ;;

  let add_days t days = to_date (of_date t + days)

  let diff t1 t2 = of_date t1 - of_date t2
end
let add_days = Days.add_days
let diff = Days.diff

let add_months t n =
  let total_months = (Month.to_int t.m) + n in
  let y = t.y + (total_months /% 12) in
  let m = total_months % 12 in
  (** correct for december **)
  let (y, m) =
    if Int.(=) m 0 then
      (y - 1, m + 12)
    else
      (y, m)
  in
  let m = Month.of_int_exn m in
  (** handle invalid dates for months with fewer number of days **)
  let rec try_create d =
    try create_exn ~y ~m ~d
    with _exn ->
      assert (Int.(>=) d 1);
      try_create (d - 1)
  in
  try_create t.d
;;

(* http://en.wikipedia.org/wiki/Determination_of_the_day_of_the_week#Purely_mathematical_methods

   note: unit tests in lib_test/time_test.ml
*)
let day_of_week  =
  let table = [| 0; 3; 2; 5; 0; 3; 5; 1; 4; 6; 2; 4 |] in
  (fun t ->
    let m = Month.to_int t.m in
    let y = if Int.(<) m 3 then t.y - 1 else t.y in
    Weekday.of_int_exn ((y + y / 4 - y / 100 + y / 400 + table.(m - 1) + t.d) % 7))
;;

let is_weekend t =
  Weekday.is_sun_or_sat (day_of_week t)
;;

let is_weekday t = not (is_weekend t)

let is_business_day t ~is_holiday =
  is_weekday t
  && not (is_holiday t)
;;

let add_days_skipping t ~skip n =
  let step = if Int.(>=) n 0 then 1 else -1 in
  let rec loop t k =
    let t_next = add_days t step in
    if skip t then loop t_next k
    else if Int.(=) k 0 then t
    else loop t_next (k - 1)
  in
  loop t (abs n)

let add_weekdays t n = add_days_skipping t ~skip:is_weekend n

let add_business_days t ~is_holiday n =
  add_days_skipping t n ~skip:(fun d -> is_weekend d || is_holiday d)
;;

let dates_between ~min:t1 ~max:t2 =
  let rec loop t l =
    if t < t1 then l
    else loop (add_days t (-1)) (t::l)
  in
  loop t2 []
;;

let weekdays_between ~min ~max =
  let all_dates = dates_between ~min ~max in
  Option.value_map
    (List.hd all_dates)
    ~default:[]
    ~f:(fun first_date ->
      (* to avoid a system call on every date, we just get the weekday for the first
         date and use it to get all the other weekdays *)
      let first_weekday = day_of_week first_date in
      let date_and_weekdays =
        List.mapi all_dates
          ~f:(fun i date -> date,Weekday.shift first_weekday i) in
      List.filter_map date_and_weekdays
        ~f:(fun (date,weekday) ->
          if Weekday.is_sun_or_sat weekday
          then None
          else Some date)
    )
;;

let business_dates_between ~min ~max ~is_holiday =
  weekdays_between ~min ~max
  |! List.filter ~f:(fun d -> not (is_holiday d))
;;

let rec previous_weekday t =
  let previous_day = add_days t (-1) in
  if is_weekday previous_day then
    previous_day
  else
    previous_weekday previous_day
;;

let rec following_weekday t =
  let following_day = add_days t 1 in
  if is_weekday following_day then
    following_day
  else
    following_weekday following_day
;;

module Export = struct
  type _date = t = private { y: int; m: Month.t; d: int; }
end
