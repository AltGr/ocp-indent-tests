(* Ocsigen
 * ocsigen_headers.ml Copyright (C) 2005 Vincent Balat
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*)

(* TODO: rewrite header parsing! *)

(** This module is for getting informations from HTTP header. *)
(** It uses the lowel level module Ocsigen_http_frame.Http_header.    *)
(** It is very basic and must be completed for exhaustiveness. *)
(* Operation on strings are hand-written ... *)
(* Include in a better cooperative parser for header or use regexp?. *)

open Ocsigen_http_frame
open Ocsigen_senders
open Ocsigen_lib
open Ocsigen_cookies


let find name frame =
  Http_headers.find (Http_headers.name name)
    frame.frame_header.Http_header.headers

let find_all name frame =
  Http_headers.find_all (Http_headers.name name)
    frame.frame_header.Http_header.headers

(*
XXX Get rid of all "try ... with _ -> ..."
*)
let list_flat_map f l = List.flatten (List.map f l)

(* splits a quoted string, for ex "azert", "  sdfmlskdf",    "dfdsfs" *)
(* We are too kind ... We accept even if the separator is not ok :-( ? *)
let rec quoted_split char (* char is not used in that version *) s =
  let longueur = String.length s in
  let rec aux deb =
    let rec nextquote s i =
      if i>=longueur
      then failwith ""
      else
      if s.[i] = '"'
      then i
      else
      if s.[i] = '\\'
      then nextquote s (i+2)
      else nextquote s (i+1)
    in
    try
      let first = (nextquote s deb) + 1 in
      let afterlast = nextquote s first in
      let value = String.sub s first (afterlast - first) in
      value::
        (if (afterlast + 1) < longueur
         then aux (afterlast + 1)
         else [])
    with Failure _ | Invalid_argument _ -> []
  in
  aux 0


let parse_quality parse_name s =
  try
    let a,b = String.sep ';' s in
    let q,qv = String.sep '=' b in
    if q="q"
    then ((parse_name a), Some (float_of_string qv))
    else failwith "Parse error"
  with _ -> ((parse_name s), None)

let parse_star a =
  if a = "*"
  then None
  else Some a

let parse_mime_type a =
  let b,c = String.sep '/' a in
  ((parse_star b), (parse_star c))

let parse_extensions parse_name s =
  try
    let a,b = String.sep ';' s in
    ((parse_name a), List.map (String.sep '=') (String.split ';' b))
  with _ -> ((parse_name s), [])

let parse_list_with_quality parse_name s =
  let splitted = list_flat_map (String.split ',') s in
  List.map (parse_quality parse_name) splitted

let parse_list_with_extensions parse_name s =
  let splitted = list_flat_map (String.split ',') s in
  List.map (parse_extensions parse_name) splitted


(*****************************************************************************)
let rec parse_cookies s =
  let splitted = String.split ';' s in
  try
    List.fold_left
      (fun beg a ->
        let (n, v) = String.sep '=' a in
        CookiesTable.add n v beg)
      CookiesTable.empty
      splitted
  with _ -> CookiesTable.empty
      (*VVV Actually the real syntax of cookies is more complex! *)
      (*
http://www.w3.org/Protocols/rfc2109/rfc2109
Mozilla spec + RFC2109
http://ws.bokeland.com/blog/376/1043/2006/10/27/76832
*)


let get_keepalive http_header =
  Http_header.get_proto http_header = Ocsigen_http_frame.Http_header.HTTP11
  &&
  try
    String.lowercase
      (Http_header.get_headers_value http_header Http_headers.connection)
    <> "close"
  with Not_found ->
      true
      (* 06/02/2008
         If HTTP/1.0, we do not keep alive, even if the client asks so.
         It would be possible, but only if the content-length is known.
         Chunked encoding is not possible with HTTP/1.0.
         As we cannot know if the output will be chunked or not,
         we decided that we won't keep the connection open at all for
         HTTP/1.0.
         Another solution would be to keep it open if the client asks so,
         and answer connection:close (and close) if we don't know the size
         of the document. In that case, all requests that have been pipelined
         would be processed by the server, but not sent back to the client.
         Which one is the best? It really depends on the client.
         If the client waits the answer before doing the following request,
         it would be ok to keep the connection opened,
         otherwise it is better not.
         (+ pb with non-idempotent requests, that should not be pipelined)
      *)



(* RFC 2616, sect. 14.23 *)
(* XXX Not so simple: the host name may contain a colon! (RFC 3986) *)
let get_host_from_host_header =
  let host_re = 
    Netstring_pcre.regexp "^(\\[[0-9A-Fa-f:.]+\\]|[^:]+)(:([0-9]+))?$" 
  in
  fun http_frame ->
    try
      let hostport =
        Http_header.get_headers_value
          http_frame.Ocsigen_http_frame.frame_header Http_headers.host
      in
      match Netstring_pcre.string_match host_re hostport 0 with
        | Some m -> 
            (Some (Netstring_pcre.matched_group m 1 hostport),
             try Some (int_of_string 
                   (Netstring_pcre.matched_group m 3 hostport))
             with Not_found -> None | Failure _ -> raise Ocsigen_Bad_Request)
        | None -> raise Ocsigen_Bad_Request
    with Not_found ->
        (None, None)

let get_user_agent http_frame =
  try (Http_header.get_headers_value
      http_frame.Ocsigen_http_frame.frame_header Http_headers.user_agent)
  with Not_found -> ""

let get_cookie_string http_frame =
  try
    Some (Http_header.get_headers_value
        http_frame.Ocsigen_http_frame.frame_header Http_headers.cookie)
  with Not_found ->
      None

let get_if_modified_since http_frame =
  try
    Some (Netdate.parse_epoch
        (Http_header.get_headers_value
           http_frame.Ocsigen_http_frame.frame_header
           Http_headers.if_modified_since))
  with _ -> None


let get_if_unmodified_since http_frame =
  try
    Some (Netdate.parse_epoch
        (Http_header.get_headers_value
           http_frame.Ocsigen_http_frame.frame_header
           Http_headers.if_unmodified_since))
  with _ -> None


let get_if_none_match http_frame =
  try
    Some (list_flat_map
        (quoted_split ',')
        (Http_header.get_headers_values
           http_frame.Ocsigen_http_frame.frame_header Http_headers.if_none_match))
  with _ -> None


let get_if_match http_frame =
  try
    Some
      (list_flat_map
         (quoted_split ',')
         (Http_header.get_headers_values
            http_frame.Ocsigen_http_frame.frame_header Http_headers.if_match))
  with _ -> None


let get_content_type http_frame =
  try
    Some
      (Http_header.get_headers_value
         http_frame.Ocsigen_http_frame.frame_header Http_headers.content_type)
  with Not_found -> None

let parse_content_type = function
  | None -> None
  | Some s ->
      match String.split ';' s with
        | [] -> None
        | a::l ->
            try
              let (typ, subtype) = String.sep '/' a in
              let params = 
                try
                  List.map (String.sep '=') l 
                with Not_found -> []
              in 
              (*VVV If syntax error, we return no parameter at all *)
              Some ((typ, subtype), params)
            with Not_found -> None
            (*VVV If syntax error in type, we return None *)


let get_content_length http_frame =
  try
    Some
      (Int64.of_string
         (Http_header.get_headers_value
            http_frame.Ocsigen_http_frame.frame_header Http_headers.content_length))
  with Not_found | Failure _ | Invalid_argument _ -> None


let get_referer http_frame =
  try
    Some
      (Http_header.get_headers_value
         http_frame.Ocsigen_http_frame.frame_header Http_headers.referer)
  with _ -> None


let get_origin http_frame =
  try
    Some
      (Http_header.get_headers_value
         http_frame.Ocsigen_http_frame.frame_header Http_headers.origin)
  with _ -> None

let get_access_control_request_method http_frame =
  try
    Some
      (Http_header.get_headers_value
         http_frame.Ocsigen_http_frame.frame_header
         Http_headers.access_control_request_method)
  with _ -> None

let get_access_control_request_headers http_frame =
  try
    let s = (Http_header.get_headers_value
        http_frame.Ocsigen_http_frame.frame_header
        Http_headers.access_control_request_headers) in
    Some (String.split ',' s)
  with _ -> None

let get_referrer = get_referer


let get_accept http_frame =
  try
    let l =
      parse_list_with_extensions
        parse_mime_type
        (Http_header.get_headers_values
           http_frame.Ocsigen_http_frame.frame_header Http_headers.accept)
    in
    let change_quality (a, l) =
      try
        let q,ll = List.assoc_remove "q" l in
        (a, Some (float_of_string q), ll)
      with _ -> (a, None, l)
    in
    List.map change_quality l
  with _ -> []


let get_accept_charset http_frame =
  try
    parse_list_with_quality
      parse_star
      (Http_header.get_headers_values
         http_frame.Ocsigen_http_frame.frame_header Http_headers.accept_charset)
  with _ -> []


let get_accept_encoding http_frame =
  try
    parse_list_with_quality
      parse_star
      (Http_header.get_headers_values
         http_frame.Ocsigen_http_frame.frame_header Http_headers.accept_encoding)
  with _ -> []


let get_accept_language http_frame =
  try
    parse_list_with_quality
      id
      (Http_header.get_headers_values
         http_frame.Ocsigen_http_frame.frame_header Http_headers.accept_language)
  with _ -> []

