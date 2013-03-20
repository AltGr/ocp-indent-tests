(*
 * Copyright (C) 2006-2009 Citrix Systems Inc.
 * Copyright (C) 2010 Anil Madhavapeddy <anil@recoil.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

open Lwt

module Op = struct include Xb_op end
module Packet = struct include Xs_packet end
module State = struct include Xb_state end

exception End_of_file
exception Eagain
exception Noent
exception Invalid

type backend =
  {
    ring: Ring.Xenstore.t;
    waiters: unit Lwt.u Lwt_sequence.t;
    notify: unit -> unit; (* function to notify through eventchn *)
  }

(** Called by a Xenstore thread that wishes to sleep (or be cancelled) *)
let wait backend =
  Activations.wait (Evtchn.xenstore_port ())

type partial_buf = HaveHdr of Xb_partial.pkt | NoHdr of int * string

type t =
  {
    backend: backend;
    pkt_in: Packet.t Queue.t;
    pkt_out: Packet.t Queue.t;
    mutable partial_in: partial_buf;
    mutable partial_out: string;
  }

let init_partial_in () = NoHdr
    (Xb_partial.header_size (), String.make (Xb_partial.header_size()) '\000')

let queue con pkt = Queue.push pkt con.pkt_out

let rec read t s len =
  let rd = Ring.Xenstore.unsafe_read t.backend.ring s len in
  match rd with 
  | 0 ->
      wait t.backend >>
      read t s len
  | rd ->
      t.backend.notify ();
      return rd

let rec write t s len =
  let ws = Ring.Xenstore.unsafe_write t.backend.ring s len in
  match ws with
  | 0 ->
      wait t.backend >>
      write t s len
  | ws ->
      t.backend.notify ();
      return ws

let output con =
  (* get the output string from a string_of(packet) or partial_out *)
  let s = if String.length con.partial_out > 0 then
      con.partial_out
    else if Queue.length con.pkt_out > 0 then
      Packet.to_string (Queue.pop con.pkt_out)
    else
      "" in
  (* send data from s, and save the unsent data to partial_out *)
  lwt () = if s <> "" then (
      let len = String.length s in
      lwt sz = write con s len in
      let left = String.sub s sz (len - sz) in
      con.partial_out <- left;
      return ()
    ) else
      return ()
  in
  (* after sending one packet, partial is empty *)
  return (con.partial_out = "")

let input con =
  let newpacket = ref false in
  let to_read =
    match con.partial_in with
    | HaveHdr partial_pkt -> Xb_partial.to_complete partial_pkt
    | NoHdr   (i, buf)    -> i in

  (* try to get more data from input stream *)
  let s = String.make to_read '\000' in
  lwt sz = read con s to_read in

  (
    match con.partial_in with
    | HaveHdr partial_pkt ->
        (* we complete the data *)
        if sz > 0 then
          Xb_partial.append partial_pkt s sz;
        if Xb_partial.to_complete partial_pkt = 0 then (
          let pkt = Packet.of_partialpkt partial_pkt in
          con.partial_in <- init_partial_in ();
          Queue.push pkt con.pkt_in;
          newpacket := true
        )
    | NoHdr (i, buf)      ->
        (* we complete the partial header *)
        if sz > 0 then
          String.blit s 0 buf (Xb_partial.header_size () - i) sz;
        con.partial_in <- if sz = i then
            HaveHdr (Xb_partial.of_string buf) else NoHdr (i - sz, buf)
  );
  return (!newpacket)

let init () =
  let gnt,ring = Ring.Xenstore.alloc_initial () in
  let evtchn = Evtchn.xenstore_port () in
  let notify () = Evtchn.notify evtchn in
  let waiters = Lwt_sequence.create () in
  let backend = { ring=ring; notify=notify; waiters=waiters } in
  let con = { backend=backend; pkt_in=Queue.create ();
              pkt_out=Queue.create (); partial_in = init_partial_in ();
              partial_out = "" } in
  Evtchn.unmask evtchn;
  con

let output_len con = Queue.length con.pkt_out
let has_new_output con = Queue.length con.pkt_out > 0
let has_old_output con = String.length con.partial_out > 0

let has_output con = has_new_output con || has_old_output con

let peek_output con = Queue.peek con.pkt_out

let input_len con = Queue.length con.pkt_in
let has_in_packet con = Queue.length con.pkt_in > 0
let get_in_packet con = Queue.pop con.pkt_in
