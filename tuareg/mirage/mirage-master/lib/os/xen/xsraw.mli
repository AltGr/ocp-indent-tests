exception Partial_not_empty
exception Unexpected_packet of string
exception Invalid_path of string
val unexpected_packet : Xb.Op.operation -> Xb.Op.operation -> 'a Lwt.t
type con
val create : unit -> con 
val split_string : ?limit:int -> char -> string -> string list
type perm = PERM_NONE | PERM_READ | PERM_WRITE | PERM_RDWR
type perms = int * perm * (int * perm) list
val string_of_perms : int * perm * (int * perm) list -> string
val perms_of_string : string -> int * perm * (int * perm) list
val pkt_send : con -> unit Lwt.t
val has_watchevents : con -> Queueop.token -> bool
val get_watchevent : con -> Queueop.token -> string * string
val read_watchevent : con -> Queueop.token -> (string * string) Lwt.t
val validate_path : string -> unit
val validate_watch_path : string -> unit
val debug : string list -> con -> string Lwt.t
val directory : int -> string -> con -> string list Lwt.t
val read : int -> string -> con -> string Lwt.t
val readv : int -> string -> string list -> con -> string list Lwt.t
val getperms : int -> string -> con -> (int * perm * (int * perm) list) Lwt.t
val watch : string -> Queueop.token -> con -> unit Lwt.t
val unwatch : string -> Queueop.token -> con -> unit Lwt.t
val transaction_start : con -> int Lwt.t
val transaction_end : int -> bool -> con -> bool Lwt.t
val introduce : int -> nativeint -> int -> con -> unit Lwt.t
val release : int -> con -> unit Lwt.t
val resume : int -> con -> unit Lwt.t
val getdomainpath : int -> con -> string Lwt.t
val write : int -> string -> string -> con -> unit Lwt.t
val writev : int -> string -> (string * string) list -> con -> unit Lwt.t
val mkdir : int -> string -> con -> unit Lwt.t
val rm : int -> string -> con -> unit Lwt.t
val setperms :
  int -> string -> int * perm * (int * perm) list -> con -> unit Lwt.t
val setpermsv :
  int ->
  string ->
  string list -> int * perm * (int * perm) list -> con -> unit Lwt.t
