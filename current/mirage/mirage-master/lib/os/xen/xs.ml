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

type perms = Xsraw.perms
type con = Xsraw.con
type domid = int

type xsh =
  {
    con: con;
    debug: string list -> string Lwt.t;
    directory: string -> string list Lwt.t;
    read: string -> string Lwt.t;
    readv: string -> string list -> string list Lwt.t;
    write: string -> string -> unit Lwt.t;
    writev: string -> (string * string) list -> unit Lwt.t;
    mkdir: string -> unit Lwt.t;
    rm: string -> unit Lwt.t;
    getperms: string -> perms Lwt.t;
    setperms: string -> perms -> unit Lwt.t;
    setpermsv: string -> string list -> perms -> unit Lwt.t;
    introduce: domid -> nativeint -> int -> unit Lwt.t;
    release: domid -> unit Lwt.t;
    resume: domid -> unit Lwt.t;
    getdomainpath: domid -> string Lwt.t;
    watch: string -> Queueop.token -> unit Lwt.t;
    unwatch: string -> Queueop.token -> unit Lwt.t;
  }

let get_operations con = {
  con = con;
  debug = (fun commands -> Xsraw.debug commands con);
  directory = (fun path -> Xsraw.directory 0 path con);
  read = (fun path -> Xsraw.read 0 path con);
  readv = (fun dir vec -> Xsraw.readv 0 dir vec con);
  write = (fun path value -> Xsraw.write 0 path value con);
  writev = (fun dir vec -> Xsraw.writev 0 dir vec con);
  mkdir = (fun path -> Xsraw.mkdir 0 path con);
  rm = (fun path -> Xsraw.rm 0 path con);
  getperms = (fun path -> Xsraw.getperms 0 path con);
  setperms = (fun path perms -> Xsraw.setperms 0 path perms con);
  setpermsv = (fun dir vec perms -> Xsraw.setpermsv 0 dir vec perms con);
  introduce = (fun id mfn port -> Xsraw.introduce id mfn port con);
  release = (fun id -> Xsraw.release id con);
  resume = (fun id -> Xsraw.resume id con);
  getdomainpath = (fun id -> Xsraw.getdomainpath id con);
  watch = (fun path data -> Xsraw.watch path data con);
  unwatch = (fun path data -> Xsraw.unwatch path data con);
}

let transaction xsh = Xst.transaction xsh.con

let has_watchevents xsh = Xsraw.has_watchevents xsh.con
let get_watchevent xsh = Xsraw.get_watchevent xsh.con

let read_watchevent xsh = Xsraw.read_watchevent xsh.con

let t =
  let xsraw = Xsraw.create () in
  get_operations xsraw

exception Timeout

(* Should never be thrown, indicates a bug in the read_watchevent_timetout function *)
exception Timeout_with_nonempty_queue

let read_watchevent_timeout xsh token timeout callback =
  let start_time = Clock.time () in
  let end_time = start_time +. timeout in

  let left = ref timeout in

  (* Returns true if a watch event in the queue satisfied us *)
  let process_queued_events () : bool Lwt.t = 
    let success = ref false in
    let rec loop () : bool Lwt.t =
      if Xsraw.has_watchevents xsh.con token && not(!success) then (
        lwt r = callback (Xsraw.get_watchevent xsh.con token) in
        success := r;
        loop ()
      ) else
        return (!success)
    in loop ()
  in
  (* Returns true if a watch event read from the socket satisfied us *)
  let process_incoming_event () = 
    lwt wev = Xsraw.read_watchevent xsh.con token in
    callback wev
  in

  let success = ref false in
  let rec loop () =
    if !left > 0. && not(!success) then begin
      (* NB the 'callback' might call back into Xs functions
         and as a side-effect, watches might be queued. Hence
         we must process the queue on every loop iteration *)

      (* First process all queued watch events *)
      lwt () = 
        if not(!success) then (
          lwt queued = process_queued_events () in
          success := queued;
          return ()
        ) else
          return () in
      (* Then block for one more watch event *)
      lwt () = 
        if not(!success) then (
          lwt s =
            try_lwt
              Time.with_timeout timeout process_incoming_event
            with Time.Timeout ->
                return false
          in
          success := s;
          return ()
        ) else
          return ()
      in
      (* Just in case our callback caused events to be queued
         and this is our last time round the loop: this prevents
         us throwing the Timeout_with_nonempty_queue spuriously *)
      lwt () =
        if not(!success) then (
          lwt queued = process_queued_events () in
          success := queued;
          return ()
        ) else
          return () in

      (* Update the time left *)
      let current_time = Clock.time () in
      left := end_time -. current_time;
      if !left > 0. then 
        loop ()
      else
        return ()
    end else 
      return () in
  lwt () = loop () in 
  if not(!success) then begin
    (* Sanity check: it should be impossible for any
       events to be queued here *)
    if Xsraw.has_watchevents xsh.con token then 
      fail Timeout_with_nonempty_queue
    else 
      fail Timeout
  end else
    return ()


let monitor_path xsh (w, v) time callback =
  let token = Queueop.create_token v in
  let unwatch () =
    try_lwt xsh.unwatch w token with _ -> return () in
  lwt () = xsh.watch w token in
  try_lwt
    read_watchevent_timeout xsh token time callback >>
    unwatch ()
  with exn -> begin
      unwatch () >>
      fail exn
    end
