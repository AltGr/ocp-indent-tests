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

open Printf
open Lwt

open Common
open Types
open Regexp (*makes Re available*)

let auth_sep_RE = Re.compile (Re.string ":")
let remove_basic_auth s =
  let re = Re.from_string "Basic( +)" in
  match Re.match_string re s 0 with
  | None -> s
  | Some e -> String.sub s e (String.length s - e)

type request = {
  r_msg: Message.message;
  r_params: (string, string) Hashtbl.t;
  r_get_params: (string * string) list;
  r_post_params: (string * string) list;
  r_meth: meth;
  r_uri: string;
  r_version: version;
  r_path: string;
}

exception Length_required (* HTTP 411 *)

let init_request finished ic =
  let unopt def = function
    | None -> def
    | Some v -> v
  in
  lwt (meth, uri, version) = Parser.parse_request_fst_line ic in
  let uri_str = Url.to_string uri in
  let path = unopt "/" uri.Url.path_string in
  let query_get_params = unopt [] uri.Url.query in
  lwt headers = Parser.parse_headers ic in
  let headers = List.map (fun (h,v) -> (String.lowercase h, v)) headers in
  lwt body = match meth with
    (* TODO XXX
        |`POST -> begin
          let limit =
            try
              Some (Int64.of_string (List.assoc "content-length" headers))
            with Not_found -> None
          in
          match limit with 
          |None -> fail Length_required (* TODO replace with HTTP 411 response *)
          |Some count ->
            let read_t =
              lwt segs = Net.Channel.TCPv4.read_view ic (Int64.to_int count) in
              Lwt.wakeup finished ();
              return segs in
            return [`Inchan read_t]
        end
    *)

    |_ ->  (* Empty body for methods other than POST *)
      Lwt.wakeup finished ();
      return [`String ""]
  in
  lwt query_post_params, body =
    match meth with
    |`POST -> begin
        (* TODO
             try
               let ct = List.assoc "content-type" headers in (* TODO Not_found *)
               if ct = "application/x-www-form-urlencoded" then
                 (Message.string_of_body body) >|=
                 (fun s -> Parser.split_query_params s, [`String s])
                else
                 return ([], body)
             with Not_found ->
        *)
        return ([], body)
      end
    | _ -> return ([], body)
  in
  let params = query_post_params @ query_get_params in (* prefers POST params *)
  let msg = Message.init ~body ~headers ~version in
  let params_tbl =
    let tbl = Hashtbl.create (List.length params) in
    List.iter (fun (n,v) -> Hashtbl.add tbl n v) params;
    tbl
  in
  return { r_msg=msg; r_params=params_tbl; r_get_params = query_get_params; 
           r_post_params = query_post_params; r_uri=uri_str; r_meth=meth; 
           r_version=version; r_path=path }

let meth r = r.r_meth
let uri r = r.r_uri
let path r = r.r_path
let body r = Message.body r.r_msg
let header r ~name = Message.header r.r_msg ~name

let param ?meth ?default r name =
  try
    (match meth with
     | None -> Hashtbl.find r.r_params name
     | Some `GET -> List.assoc name r.r_get_params
     | Some `POST -> List.assoc name r.r_post_params)
  with Not_found ->
    (match default with
     | None -> raise (Param_not_found name)
     | Some value -> value)

let param_all ?meth r name =
  (match (meth: meth option) with
   | None -> List.rev (Hashtbl.find_all r.r_params name)
   | Some `DELETE
   | Some `HEAD
   | Some `GET -> Misc.list_assoc_all name r.r_get_params
   | Some `POST -> Misc.list_assoc_all name r.r_post_params)

let params r = r.r_params
let params_get r = r.r_get_params
let params_post r = r.r_post_params

let authorization r = 
  match Message.header r.r_msg ~name:"authorization" with
  | [] -> None
  | h :: _ -> 
    let credentials = Base64.decode (remove_basic_auth h) in
    (match Re.split_delim auth_sep_RE credentials with
     | [username; password] -> Some (`Basic (username, password))
     | l -> None)

