(*
  OCaml HTTP - do it yourself (fully OCaml) HTTP daemon

  Copyright (C) <2002-2005> Stefano Zacchiroli <zack@cs.unibo.it>
  Copyright (C) <2009-2011> Anil Madhavapeddy <anil@recoil.org>
  Copyright (C) <2009> David Sheets <sheets@alum.mit.edu>

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU Library General Public License as
  published by the Free Software Foundation, version 2.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU Library General Public License for more details.

  You should have received a copy of the GNU Library General Public
  License along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307
  USA
*)
open Common
open Constants
open Types
open Printf
open Lwt

exception Not_supported of string

(* remove all bindings of 'name' from hashtbl 'tbl' *)
let rec hashtbl_remove_all tbl name =
  if not (Hashtbl.mem tbl name) then
    raise (Header_not_found name);
  Hashtbl.remove tbl name;
  if Hashtbl.mem tbl name then hashtbl_remove_all tbl name

type contents = [
| `String of string
| `Inchan of (int64 * OS.Io_page.t Lwt_stream.t) (* size * stream *)
]

type message = {
  mutable m_contents : contents list;
  m_headers : (string, string) Hashtbl.t;
  m_version : version;
} 

let body msg =
  List.rev msg.m_contents

let body_size cl =
  List.fold_left (fun a -> 
    function
    |`String s -> Int64.(add a (of_int (String.length s)))
    |`Inchan (sz,_) -> sz
  ) Int64.zero cl

let set_body msg contents =
  msg.m_contents <- [contents]

let add_body msg contents =
  msg.m_contents <- (contents :: msg.m_contents)

let add_header msg ~name ~value =
  let name = String.lowercase name in
  Hashtbl.add msg.m_headers name value

let add_headers msg =
  List.iter (fun (name, value) -> add_header msg ~name ~value)

let replace_header msg ~name ~value =
  let name = String.lowercase name in
  Hashtbl.replace msg.m_headers name value

let replace_headers msg =
  List.iter (fun (name, value) -> replace_header msg ~name ~value)

let remove_header msg ~name =
  let name = String.lowercase name in
  hashtbl_remove_all msg.m_headers name

let has_header msg ~name =
  Hashtbl.mem msg.m_headers name

let header msg ~name =
  let name = String.lowercase name in
  let compact = String.concat ", " in
  (* TODO: Just these old headers or all of HTTP 1.0? *)
  let no_compact = ["set-cookie"] in
  if has_header msg ~name then
    let hl = List.rev (Hashtbl.find_all msg.m_headers name) in
    if List.mem name no_compact then hl
    else [compact hl]
  else []

let headers msg =
  let hset = Hashtbl.create 11 in
  Hashtbl.iter (fun name _ -> Hashtbl.replace hset name ()) msg.m_headers;
  Hashtbl.fold (fun name _ headers -> 
    List.rev_append (List.map (fun h -> (name, h)) (header msg ~name)) headers
  ) hset []
    
let version msg = msg.m_version

let init ~body ~headers ~version =
  let msg = { m_contents=body; m_headers = Hashtbl.create 11; 
              m_version = version } in
  add_headers msg headers;
  msg

let serialize_to_channel msg ~fstLineToString chan =
  let body = (body msg : contents list) in
  let bodylen = body_size body in
  Net.Channel.write_line chan fstLineToString;
  List.iter (fun (h,v) ->
    Net.Channel.write_line chan (sprintf "%s: %s" h v)
  ) (headers msg);
  let clen = sprintf "Content-Length: %Ld\r\n\r\n" bodylen in
  Net.Channel.write_string chan clen 0 (String.length clen);
  lwt () = Lwt_list.iter_s (function
  |`String s -> return (Net.Channel.write_string chan s 0 (String.length s))
  |`Inchan (_,t) -> Lwt_stream.iter_s (fun c -> return (Net.Channel.write_buffer chan c)) t
  ) body in
Net.Channel.flush chan
