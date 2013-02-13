(*
 * Copyright (c) 2005-2006 Tim Deegan <tjd@phlegethon.org>
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
 *
 * dnsrr.mli --- datatypes and handling for DNS RRs and RRSets
 *
 *)

type serial = int32 
and ipv4 = int32
and cstr = string Hashcons.hash_consed
and dnsnode = { owner : string list Hashcons.hash_consed;
                mutable rrsets : rrset list; } 
and rrset = { ttl : int32; rdata : rdata; }
and rdata =
  A of ipv4 list
| NS of dnsnode list
| CNAME of dnsnode list
| SOA of (dnsnode * dnsnode * serial * int32 * int32 * int32 * int32) list
| MB of dnsnode list
| MG of dnsnode list
| MR of dnsnode list
| WKS of (int32 * int * cstr) list
| PTR of dnsnode list
| HINFO of (cstr * cstr) list
| MINFO of (dnsnode * dnsnode) list
| MX of (int * dnsnode) list
| TXT of cstr list list
| RP of (dnsnode * dnsnode) list
| AFSDB of (int * dnsnode) list
| X25 of cstr list
| ISDN of (cstr * cstr option) list
| RT of (int * dnsnode) list
| AAAA of cstr list
| SRV of (int * int * int * dnsnode) list
| UNSPEC of cstr list
| Unknown of int * cstr list

(* Hashcons values *)
val hashcons_charstring : string -> cstr
val hashcons_domainname : string list -> string list Hashcons.hash_consed
val clear_cons_tables : unit -> unit

(* Extract relevant RRSets given a query type, a list of RRSets
   and a flag to say whether to return Cnames too *)
val get_rrsets :
  [> `A | `AAAA | `AFSDB | `ANY | `CNAME | `HINFO | `ISDN | `MAILB | `MB 
  | `MG | `MINFO | `MR | `MX | `NS | `PTR | `RP | `RT | `SOA 
  | `SRV | `TXT | `UNSPEC | `Unknown of int * string | `WKS | `X25 ] ->
  rrset list -> bool -> rrset list

(* Merge a new RRSet into a list of RRSets. 
   Returns the new list and the ttl of the resulting RRset. 
   Reverses the order of the RRsets in the list *)
val merge_rrset : rrset -> rrset list -> int32 * rrset list
