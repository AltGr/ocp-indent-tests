(*
 * Copyright (c) 2010 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

let time () = Js.to_float (Js.date##now ()) /. 1000.

type tm = {
  tm_sec : int;
  tm_min : int;
  tm_hour : int;
  tm_mday : int;
  tm_mon : int;
  tm_year : int;
  tm_wday : int;
  tm_yday : int;
  tm_isdst : bool;
}

let gmtime x =
  let f = jsnew Js.date_fromTimeValue (x) in {
    tm_sec   = f##getSeconds ();
    tm_min   = f##getMinutes ();
    tm_hour  = f##getHours ();
    tm_mday  = f##getDate ();
    tm_mon   = f##getMonth ();
    tm_year  = f##getFullYear () - 1900;
    tm_wday  = f##getDay ();
    tm_yday  = 0;     (* XXX: no day of year in JS *)
    tm_isdst = false; (* XXX: no DST in JS *)
  }
                                          
let () =
  Log.set_date (fun () ->
    let tm = gmtime (time ()) in
    Printf.sprintf "%.4d/%.2d/%.2dT%.2d:%.2d:%.2dZ"
      (1900+tm.tm_year)
      tm.tm_mon
      tm.tm_mday
      tm.tm_hour
      tm.tm_min
      tm.tm_sec)
