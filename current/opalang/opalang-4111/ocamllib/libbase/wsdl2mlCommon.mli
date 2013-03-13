(*
    Copyright © 2011 MLstate

    This file is part of Opa.

    Opa is free software: you can redistribute it and/or modify it under the
    terms of the GNU Affero General Public License, version 3, as published by
    the Free Software Foundation.

    Opa is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for
    more details.

    You should have received a copy of the GNU Affero General Public License
    along with Opa. If not, see <http://www.gnu.org/licenses/>.
*)
(** Wsdl2mlCommon:
    Common code between wsdl2ml translator and generated code runtime.
*)

(** Simple tree type, straight out of the example docs for Xmlm.
*)
type tree = E of Xmlm.tag * tree list | D of string

(** Some basic conversion functions *)
val sname : Xmlm.name -> string
val satt : Xmlm.attribute -> string
val satts : Xmlm.attribute list -> string
val stag : Xmlm.tag -> string
val gtag : tree -> Xmlm.tag
val gts : tree -> tree list
val mkname : string -> string -> Xmlm.name
val mkatt : Xmlm.name -> string -> Xmlm.attribute
val mktag : Xmlm.name -> Xmlm.attribute list -> Xmlm.tag
val mkstag : string -> Xmlm.tag

(** Xml input/output *)
val in_tree : Xmlm.input -> Xmlm.dtd * tree
val out_tree : Xmlm.output -> Xmlm.dtd * tree -> unit
val string_of_tree : ?hint:int -> Xmlm.dtd * tree -> string
val sxml : tree list -> string

(** Searching the Xmlm data structure *)
val is_name : Xmlm.name -> Xmlm.name -> bool
val is_uqname : Xmlm.name -> Xmlm.name -> bool
val find_tag : (Xmlm.tag -> bool) -> tree list -> tree option
val find_att : Xmlm.name -> Xmlm.attribute list -> string option

(** Read in XML tree from string, file etc. *)
val get_tree_string : string -> Xmlm.dtd * tree
val get_tree_filename : string -> Xmlm.dtd * tree

(** Tree transformers *)
val null_fold_tree_f : 'a -> tree -> 'a
val fold_tree : ('a -> tree -> 'a) -> 'a -> tree -> 'a
val fold_trees : ('a -> tree -> 'a) -> 'a -> ('b * ('c * tree)) list -> 'a
val find_trees : ('a -> bool) -> ('b * ('c * 'a)) list -> 'a list

(** Support for XMLScema datatypes *)

(** dateTime *)
type t_dateTime = Time.t
val string_of_dateTime : t_dateTime -> string
val dateTime_of_string : string -> t_dateTime

(** byte: just an int with range checks -127 <= b <= 128 *)
type t_byte = int
val chk_byte : string -> int -> unit
val string_of_byte : t_byte -> string
val byte_of_string : string -> t_byte

(** Error exceptions generated by the code *)
exception Wsdl2mlOccurs of int * int * tree list
exception Wsdl2mlNonMtchCon of string
exception Wsdl2mlInputFailure of string

(** fx does nothing except translate error exceptions
    into Wsdl2mlInputFailure.  Needed by fromxml functions
    and is used by generated code.
*)
val fx : string -> ('a -> 'b) -> 'a -> 'b

(** Generic transformers for types found in <any/> elements. *)
val toxml_string : string -> tree list
val toxml_int : int -> tree list
val toxml_byte : t_byte -> tree list
val toxml_float : float -> tree list
val toxml_bool : bool -> tree list
val toxml_dateTime : t_dateTime -> tree list
val fromxml_string : tree list -> string
val fromxml_int : tree list -> int
val fromxml_byte : tree list -> t_byte
val fromxml_float : tree list -> float
val fromxml_bool : tree list -> bool
val fromxml_dateTime : tree list -> t_dateTime

(** Support for generated input parser. *)
val find_name : string -> tree list -> tree list
val find_names : string list -> tree list -> tree list

(** Some support for digging around in the XML tree. *)
val get_sts : string -> tree list -> tree list
val sts_names : tree list -> string list
val dig_sts : string list -> tree list -> string list * tree list
val is_tree_name : string -> tree -> bool

