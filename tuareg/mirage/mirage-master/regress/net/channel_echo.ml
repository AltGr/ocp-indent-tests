(*
 * Copyright (c) 2011 Richard Mortier <mort@cantab.net>
 * Derived from code by Anil Madhavapeddy <anil@recoil.org>
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

open Lwt 
open Printf
open Net

let port = 55555
let use_dhcp = false
let ip = Net.Nettypes.(
  (ipv4_addr_of_tuple (10l,0l,0l,2l),
   ipv4_addr_of_tuple (255l,255l,255l,0l),
   [ ipv4_addr_of_tuple (10l,0l,0l,1l) ]
  ))


let rec echo dst chan = 
  Log.info "Channel_echo" "callback!";
  try_lwt
    lwt bufs = Channel.read_line chan in
List.iter (Channel.write_buffer chan) bufs;
Log.info "Echo" "buf:%s" "";
Channel.write_char chan '\n';
lwt () = Channel.flush chan in
echo dst chan
 with Nettypes.Closed -> return (Log.info "Echo" "closed!")

let main () =
  Log.info "Echo" "starting server";
  Net.Manager.create (fun mgr interface id ->
    lwt () = (match use_dhcp with
    | false -> Manager.configure interface (`IPv4 ip)
    | true -> Manager.configure interface (`DHCP)
    )
                      in
                     lwt () = Net.Channel.listen mgr (`TCPv4 ((None, port), echo)) in
return (Log.info "Channel_echo" "done!")
)
