(*
 * Copyright (c) 2005-2011 Anil Madhavapeddy <anil@recoil.org>
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

module DL = Dnsloader
module DQ = Dnsquery
module DR = Dnsrr
module DP = Dnspacket

let dnstrie = DL.(state.db.trie)

let get_answer qname qtype id =
  let qname = List.map String.lowercase qname in  
  let ans = DQ.answer_query qname qtype dnstrie in
  let detail = 
    DP.(build_detail { qr=`Answer; opcode=`Query; 
                       aa=ans.DQ.aa; tc=false; rd=false; ra=false; 
                       rcode=ans.DQ.rcode;  
                     })      
  in
  let questions = [ DP.({ q_name=qname; q_type=qtype; q_class=`IN }) ] in
  let dp = DP.({ id; detail; questions;
                 answers=ans.DQ.answer; 
                 authorities=ans.DQ.authority; 
                 additionals=ans.DQ.additional; 
               })
  in
  DP.marshal dp

(* Space leaking hash table cache, always grows *)
module Leaking_cache = Hashtbl.Make (struct
  type t = string list * Dnspacket.q_type
  let equal (a:t) (b:t) = a = b
  let hash = Hashtbl.hash
end)

let cache = Leaking_cache.create 1
let get_answer_memo qname qtype id =
  let qargs = qname, qtype in
  let rbuf,roff,rlen =
    try
      Leaking_cache.find cache qargs
    with Not_found -> begin
      let r = get_answer qname qtype id in
      Leaking_cache.add cache qargs r;
      r
    end
  in
  String.set rbuf 0 (char_of_int ((id lsr 8) land 255));
  String.set rbuf 1 (char_of_int (id land 255));
  rbuf, roff, rlen

let no_memo mgr src dst bits =
  let names = Hashtbl.create 8 in
  DP.(
    let d = parse_dns names bits in
    let q = List.hd d.questions in
    let r = get_answer q.q_name q.q_type d.id in
    Net.Datagram.UDPv4.send mgr ~src dst r
  )

let leaky mgr src dst bits =
  let names = Hashtbl.create 8 in
  let open DP in
  let d = parse_dns names bits in
  let q = List.hd d.questions in
  let r = get_answer_memo q.q_name q.q_type d.id in
  Net.Datagram.UDPv4.send mgr ~src dst r
    
let listen ?(mode=`none) ~zonebuf mgr src =
  Dnsserver.load_zone [] zonebuf;
  Net.Datagram.UDPv4.(recv mgr src
                        (match mode with
                        |`none -> no_memo mgr src
                        |`leaky -> leaky mgr src
                        )
  )
