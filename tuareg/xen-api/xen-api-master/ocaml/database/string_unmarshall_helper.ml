(*
 * Copyright (C) 2006-2009 Citrix Systems Inc.
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
(** Called in the autogenerated String_to_DM module *)

exception Failure of string

let set f (m: string) = 
  match SExpr_TS.of_string m with
  | SExpr.Node xs ->
    List.map (function SExpr.String x -> f x
    | _ -> raise (Failure m)) xs
  | _ -> raise (Failure m)

let map f g (m: string) = 
  match SExpr_TS.of_string m with
  | SExpr.Node xs ->
    List.map (function SExpr.Node [ SExpr.String k; SExpr.String v ] -> f k, g v
    | _ -> raise (Failure m)) xs
  | _ -> raise (Failure m)

