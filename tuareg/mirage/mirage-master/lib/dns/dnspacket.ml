(*
 * Copyright (c) 2011 Richard Mortier <mort@cantab.net>
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

module DT = Dnstrie
module DL = Dnsloader

module Bitstring = struct
  include Bitstring
  let offset_of_bitstring bits = 
    let (_, offset, _) = bits in offset
end

let sp = Printf.sprintf
let pr = Printf.printf
let ep = Printf.eprintf

exception Unparsable of string * Bitstring.bitstring

let (|>) x f = f x (* pipe *)
let (>>) f g x = g (f x) (* functor pipe *)
let (||>) l f = List.map f l (* element-wise pipe *)

let (+++) x y = Int32.add x y

let (&&&) x y = Int32.logand x y
let (|||) x y = Int32.logor x y
let (^^^) x y = Int32.logxor x y
let (<<<) x y = Int32.shift_left x y
let (>>>) x y = Int32.shift_right_logical x y

let join c l = String.concat c l
let stop (x, bits) = x (* drop remainder to stop parsing and demuxing *) 

type domain_name = string list
type int16 = int
type ipv4 = int32
let ipv4_to_string i =   
  sp "%ld.%ld.%ld.%ld" 
    ((i &&& 0x0_ff000000_l) >>> 24) ((i &&& 0x0_00ff0000_l) >>> 16)
    ((i &&& 0x0_0000ff00_l) >>>  8) ((i &&& 0x0_000000ff_l)       )

type byte = char
let byte (i:int) : byte = Char.chr i
let int_of_byte b = int_of_char b
let int32_of_byte b = b |> int_of_char |> Int32.of_int
let int32_of_int (i:int) = Int32.of_int i

type bytes = string
let bytes_to_hex_string bs = 
  bs |> Array.map (fun b -> sp "%02x." (int_of_byte b))
let bytes_of_bitstring bits = Bitstring.string_of_bitstring bits
let ipv4_addr_of_bytes bs = 
  ((bs.[0] |> int32_of_byte <<< 24) ||| (bs.[1] |> int32_of_byte <<< 16) 
    ||| (bs.[2] |> int32_of_byte <<< 8) ||| (bs.[3] |> int32_of_byte))

type label = 
| L of string * int (* string *)
| P of int * int (* pointer *)
| Z of int (* zero; terminator *)

let parse_charstr bits = 
  bitmatch bits with
  | { len: 8; str: (len*8): string; bits: -1: bitstring }
    -> str, bits

let parse_label base bits = 
  let cur = Bitstring.offset_of_bitstring bits in
  let offset = (cur-base)/8 in
  (bitmatch bits with
  | { length: 8: check(length != 0 && length < 64); 
      name: (length*8): string; data: -1: bitstring } 
    -> (L (name, offset), data)
  | { 0b0_11: 2; ptr: 14; bits: -1: bitstring } 
    -> (P (ptr, offset), bits)
  | { 0: 8; bits: -1: bitstring } 
    -> (Z offset, bits)
  | { _ } -> raise(Unparsable ("parse_label", bits))
  )

let parse_name names base bits = 
  (* what. a. mess. *)
  let rec aux offsets name bits = 
    match parse_label base bits with
    | (L (n, o) as label, data) 
      -> Hashtbl.add names o label;
        offsets |> List.iter (fun off -> (
          Hashtbl.add names off label
        ));
        aux (o :: offsets) (n :: name) data 
    | (P (p, _), data) 
      -> let ns = (Hashtbl.find_all names p 
                      |> List.filter (fun n ->
                        match n with L _ -> true | _ -> false)
                      |> List.rev)
         in
         offsets |> List.iter (fun off ->
           ns |> List.iter (fun n -> Hashtbl.add names off n)
         );
         ((ns |> List.rev
           ||> (function
             | L (nm,_) -> nm
             | _ -> raise(Unparsable ("parse_name", bits)))) 
          @ name), data
    | (Z o as zero, data)
      -> Hashtbl.add names o zero;
        (name, data)
  in 
  let name, bits = aux [] [] bits in
  (List.rev name, bits)

type rr_type = [
| `A | `NS | `MD | `MF | `CNAME | `SOA | `MB | `MG | `MR | `NULL 
| `WKS | `PTR | `HINFO | `MINFO | `MX | `TXT | `RP | `AFSDB | `X25 
| `ISDN | `RT | `NSAP | `NSAP_PTR | `SIG | `KEY | `PX | `GPOS | `AAAA 
| `LOC | `NXT | `EID | `NIMLOC | `SRV | `ATMA | `NAPTR | `KM | `CERT 
| `A6 | `DNAME | `SINK | `OPT | `APL | `DS | `SSHFP | `IPSECKEY 
| `RRSIG | `NSEC | `DNSKEY | `SPF | `UINFO | `UID | `GID | `UNSPEC
| `Unknown of int * bytes
]

let int_of_rr_type : rr_type -> int = function
  | `A        -> 1
  | `NS       -> 2
  | `MD       -> 3
  | `MF       -> 4
  | `CNAME    -> 5
  | `SOA      -> 6
  | `MB       -> 7
  | `MG       -> 8
  | `MR       -> 9
  | `NULL     -> 10
  | `WKS      -> 11
  | `PTR      -> 12
  | `HINFO    -> 13
  | `MINFO    -> 14
  | `MX       -> 15
  | `TXT      -> 16
  | `RP       -> 17
  | `AFSDB    -> 18
  | `X25      -> 19
  | `ISDN     -> 20
  | `RT       -> 21
  | `NSAP     -> 22
  | `NSAP_PTR -> 23
  | `SIG      -> 24
  | `KEY      -> 25
  | `PX       -> 26
  | `GPOS     -> 27
  | `AAAA     -> 28
  | `LOC      -> 29
  | `NXT      -> 30
  | `EID      -> 31
  | `NIMLOC   -> 32
  | `SRV      -> 33
  | `ATMA     -> 34
  | `NAPTR    -> 35
  | `KM       -> 36
  | `CERT     -> 37
  | `A6       -> 38
  | `DNAME    -> 39
  | `SINK     -> 40
  | `OPT      -> 41
  | `APL      -> 42
  | `DS       -> 43
  | `SSHFP    -> 44
  | `IPSECKEY -> 45
  | `RRSIG    -> 46
  | `NSEC     -> 47
  | `DNSKEY   -> 48
    
  | `SPF      -> 99
  | `UINFO    -> 100
  | `UID      -> 101
  | `GID      -> 102
  | `UNSPEC   -> 103
    
  | `Unknown _ -> -1
and rr_type_of_int : int -> rr_type = function
  | 1  -> `A
  | 2  -> `NS
  | 3  -> `MD
  | 4  -> `MF
  | 5  -> `CNAME
  | 6  -> `SOA
  | 7  -> `MB
  | 8  -> `MG
  | 9  -> `MR
  | 10 -> `NULL
  | 11 -> `WKS
  | 12 -> `PTR
  | 13 -> `HINFO
  | 14 -> `MINFO
  | 15 -> `MX
  | 16 -> `TXT
  | 17 -> `RP
  | 18 -> `AFSDB 
  | 19 -> `X25 
  | 20 -> `ISDN 
  | 21 -> `RT
  | 22 -> `NSAP 
  | 23 -> `NSAP_PTR 
  | 24 -> `SIG 
  | 25 -> `KEY
  | 26 -> `PX 
  | 27 -> `GPOS 
  | 28 -> `AAAA 
  | 29 -> `LOC
  | 30 -> `NXT 
  | 31 -> `EID 
  | 32 -> `NIMLOC 
  | 33 -> `SRV 
  | 34 -> `ATMA 
  | 35 -> `NAPTR 
  | 36 -> `KM 
  | 37 -> `CERT 
  | 38 -> `A6 
  | 39 -> `DNAME 
  | 40 -> `SINK 
  | 41 -> `OPT 
  | 42 -> `APL 
  | 43 -> `DS 
  | 44 -> `SSHFP 
  | 45 -> `IPSECKEY 
  | 46 -> `RRSIG 
  | 47 -> `NSEC 
  | 48 -> `DNSKEY 
    
  | 99  -> `SPF 
  | 100 -> `UINFO 
  | 101 -> `UID 
  | 102 -> `GID 
  | 103 -> `UNSPEC

  | _ -> invalid_arg "rr_type_of_int"
and string_of_rr_type:rr_type -> string = function
  | `A        -> "A"
  | `NS       -> "NS"
  | `MD       -> "MD"
  | `MF       -> "MF"
  | `CNAME    -> "CNAME"
  | `SOA      -> "SOA"
  | `MB       -> "MB"
  | `MG       -> "MG"
  | `MR       -> "MR"
  | `NULL     -> "NULL"
  | `WKS      -> "WKS"
  | `PTR      -> "PTR"
  | `HINFO    -> "HINFO"
  | `MINFO    -> "MINFO"
  | `MX       -> "MX"
  | `TXT      -> "TXT"
  | `RP       -> "RP"
  | `AFSDB    -> "AFSDB"
  | `X25      -> "X25"
  | `ISDN     -> "ISDN"
  | `RT       -> "RT"
  | `NSAP     -> "NSAP"
  | `NSAP_PTR -> "NSAP"
  | `SIG      -> "SIG"
  | `KEY      -> "KEY"
  | `PX       -> "PX"
  | `GPOS     -> "GPOS"
  | `AAAA     -> "AAAA"
  | `LOC      -> "LOC"
  | `NXT      -> "NXT"
  | `EID      -> "EID"
  | `NIMLOC   -> "NIMLOC"
  | `SRV      -> "SRV"
  | `ATMA     -> "ATMA"
  | `NAPTR    -> "NAPTR"
  | `KM       -> "KM"
  | `CERT     -> "CERT"
  | `A6       -> "A6"
  | `DNAME    -> "DNAME"
  | `SINK     -> "SINK"
  | `OPT      -> "OPT"
  | `APL      -> "APL"
  | `DS       -> "DS"
  | `SSHFP    -> "SSHFP"
  | `IPSECKEY -> "IPSECKEY"
  | `RRSIG    -> "RRSIG"
  | `NSEC     -> "NSEC"
  | `DNSKEY   -> "DNSKEY"
  | `SPF      -> "SPF"
  | `UINFO    -> "UINFO"
  | `UID      -> "UID"
  | `GID      -> "GID"
  | `UNSPEC   -> "UNSPEC"
  | `Unknown (i, _) -> Printf.sprintf "Unknown (%d)" i

type rr_rdata = [
| `A of int32
| `NS of domain_name
| `MD of domain_name
| `MF of domain_name
| `CNAME of domain_name
| `SOA of 
    domain_name * domain_name * int32 * int32 * int32 * int32 * int32 
| `HINFO of string * string
| `MB of domain_name
| `MG of domain_name
| `MR of domain_name
| `MINFO of domain_name * domain_name
| `MX of int16 * domain_name
| `PTR of domain_name
| `TXT of string list
| `WKS of int32 * byte * string
| `RP of domain_name * domain_name
| `AFSDB of int16 * domain_name
| `X25 of string
| `ISDN of string
| `RT of int16 * domain_name
| `AAAA of bytes
| `SRV of int16 * int16 * int16 * domain_name
| `UNSPEC of bytes
| `UNKNOWN of int * bytes
]

let string_of_rdata r = 
  match r with
  | `A ip -> sp "A (%s)" (ipv4_to_string ip)
  | `NS n -> sp "NS (%s)" (join "." n)
  | _     -> failwith "string_of_rdata: unknown rdata type"

let parse_rdata names base t bits = 
  Dnsrr.(
    match t with
    | `A -> `A (bits |> bytes_of_bitstring |> ipv4_addr_of_bytes)
    | `NS -> `NS (bits |> parse_name names base |> stop)
    | `CNAME -> `CNAME (bits |> parse_name names base |> stop)
      
    | `SOA -> let mn, bits = parse_name names base bits in
              let rn, bits = parse_name names base bits in 
              (bitmatch bits with
              | { serial: 32; refresh: 32; retry: 32; expire: 32;
                  minimum: 32 }
                -> `SOA (mn, rn, serial, refresh, retry, expire, minimum)
              )
                
    | `WKS -> (
      bitmatch bits with 
      | { addr: 32; proto: 8; bitmap: -1: string } 
        -> `WKS (addr, byte proto, bitmap)
    )
    | `PTR -> `PTR (bits |> parse_name names base |> stop)
    | `HINFO -> let cpu, bits = parse_charstr bits in
                let os = bits |> parse_charstr |> stop in
                `HINFO (cpu, os)
    | `MINFO -> let rm, bits = parse_name names base bits in
                let em = bits |> parse_name names base |> stop in
                `MINFO (rm, em)
    | `MX -> (
      bitmatch bits with
      | { preference: 16; bits: -1: bitstring } 
        -> `MX ((preference, bits |> parse_name names base |> stop))
    )
    | `TXT -> let names, _ = 
                let rec aux ns bits = 
                  let n, bits = parse_name names base bits in
                  aux (n :: ns) bits
                in
                aux [] bits
              in
              `TXT names
    | t -> `UNKNOWN (int_of_rr_type t, Bitstring.string_of_bitstring bits)
  )

type rr_class = [ `IN | `CS | `CH | `HS ]
let int_of_rr_class : rr_class -> int = function
  | `IN -> 1
  | `CS -> 2
  | `CH -> 3
  | `HS -> 4
and rr_class_of_int : int -> rr_class = function
  | 1   -> `IN
  | 2   -> `CS
  | 3   -> `CH
  | 4   -> `HS
  | _   -> invalid_arg "rr_class_of_int"
and string_of_rr_class : rr_class -> string = function
  | `IN -> "IN"
  | `CS -> "CS"
  | `CH -> "CH"
  | `HS -> "HS"

type rsrc_record = {
  rr_name  : domain_name;
  rr_class : rr_class;
  rr_ttl   : int32;
  rr_rdata : rr_rdata;
}

let rr_to_string rr = 
  sp "%s <%s|%ld> %s" 
    (join "." rr.rr_name) (string_of_rr_class rr.rr_class) 
    rr.rr_ttl (string_of_rdata rr.rr_rdata)

let parse_rr names base bits =
  let name, bits = parse_name names base bits in
  bitmatch bits with
  | { t: 16; c: 16; ttl: 32; 
      rdlen: 16; rdata: (rdlen*8): bitstring;
      data: -1: bitstring } 
    -> let rdata = parse_rdata names base (rr_type_of_int t) rdata in
       { rr_name = name;
         rr_class = rr_class_of_int c;
         rr_ttl = ttl;
         rr_rdata = rdata;
       }, data
  | { _ } -> raise (Unparsable ("parse_rr", bits))

type q_type = [ rr_type | `AXFR | `MAILB | `MAILA | `ANY | `TA | `DLV ]
let int_of_q_type : q_type -> int = function
  | `AXFR         -> 252
  | `MAILB        -> 253
  | `MAILA        -> 254
  | `ANY          -> 255
  | `TA           -> 32768
  | `DLV          -> 32769
  | #rr_type as t -> int_of_rr_type t
and q_type_of_int : int -> q_type = function
  | 252           -> `AXFR
  | 253           -> `MAILB
  | 254           -> `MAILA
  | 255           -> `ANY
  | 32768         -> `TA
  | 32769         -> `DLV
  | n             -> (rr_type_of_int n :> q_type)
and string_of_q_type:q_type -> string = function
  | `AXFR         -> "AXFR"
  | `MAILB        -> "MAILB"
  | `MAILA        -> "MAILA"
  | `ANY          -> "ANY"
  | `TA           -> "TA"
  | `DLV          -> "DLV"
  | #rr_type as t -> string_of_rr_type t

type q_class = [ rr_class | `NONE | `ANY ]

let int_of_q_class : q_class -> int = function
  | `NONE          -> 254
  | `ANY           -> 255
  | #rr_class as c -> int_of_rr_class c
and q_class_of_int : int -> q_class = function
  | 254            -> `NONE
  | 255            -> `ANY
  | n              -> (rr_class_of_int n :> q_class)
and string_of_q_class : q_class -> string = function
  | `NONE          -> "NONE"
  | `ANY           -> "ANY"
  | #rr_class as c -> string_of_rr_class c

type question = {
  q_name  : domain_name;
  q_type  : q_type;
  q_class : q_class;
}

let question_to_string q = 
  sp "%s <%s|%s>" 
    (join "." q.q_name) 
    (string_of_q_type q.q_type) (string_of_q_class q.q_class)

let parse_question names base bits = 
  let n, bits = parse_name names base bits in
  bitmatch bits with
  | { t: 16; c: 16; data: -1: bitstring }
    -> { q_name = n;
         q_type = q_type_of_int t;
         q_class = q_class_of_int c;
       }, data
  | { _ } -> raise (Unparsable ("parse_question", bits))

type qr = [ `Query | `Answer ]
let qr_of_bool = function
  | false -> `Query
  | true  -> `Answer
let bool_of_qr = function
  | `Query  -> false
  | `Answer -> true

type opcode = [ qr | `Status | `Reserved | `Notify | `Update ]
let opcode_of_int = function
  | 0 -> `Query
  | 1 -> `Answer
  | 2 -> `Status
  | 3 -> `Reserved
  | 4 -> `Notify
  | 5 -> `Update
  | _ -> failwith "dnspacket: unknown opcode"
let int_of_opcode = function
  | `Query -> 0
  | `Answer -> 1
  | `Status -> 2
  | `Reserved -> 3
  | `Notify -> 4
  | `Update -> 5
  | _ -> failwith "dnspacket: unknown opcode"

type rcode = [
| `NoError  | `FormErr
| `ServFail | `NXDomain | `NotImp  | `Refused
| `YXDomain | `YXRRSet  | `NXRRSet | `NotAuth
| `NotZone  | `BadVers  | `BadKey  | `BadTime
| `BadMode  | `BadName  | `BadAlg 
]
let rcode_of_int = function
  | 0 -> `NoError
  | 1 -> `FormErr
  | 2 -> `ServFail
  | 3 -> `NXDomain
  | 4 -> `NotImp
  | 5 -> `Refused
  | 6 -> `YXDomain
  | 7 -> `YXRRSet
  | 8 -> `NXRRSet
  | 9 -> `NotAuth
  | 10 -> `NotZone
    
  | 16-> `BadVers
  | 17-> `BadKey
  | 18-> `BadTime
  | 19-> `BadMode
  | 20-> `BadName
  | 21-> `BadAlg
  | _ -> failwith "dnspacket: unknown rcode"
and int_of_rcode = function
  | `NoError -> 0
  | `FormErr -> 1
  | `ServFail -> 2
  | `NXDomain -> 3
  | `NotImp -> 4
  | `Refused -> 5
  | `YXDomain -> 6
  | `YXRRSet -> 7
  | `NXRRSet -> 8
  | `NotAuth -> 9
  | `NotZone -> 10
    
  | `BadVers -> 16
  | `BadKey -> 17
  | `BadTime -> 18
  | `BadMode -> 19
  | `BadName -> 20
  | `BadAlg -> 21
  | _ -> failwith "dnspacket: unknown rcode"

type detail = {
  qr: qr;
  opcode: opcode;
  aa: bool; 
  tc: bool; 
  rd: bool; 
  ra: bool;
  rcode: rcode;
}
let detail_to_string d = 
  sp "%c:%02x %s:%s:%s:%s %d"
    (match d.qr with `Query -> 'Q' | `Answer -> 'R')
    (int_of_opcode d.opcode)
    (if d.aa then "a" else "na") (* authoritative vs not *)
    (if d.tc then "t" else "c") (* truncated vs complete *)
    (if d.rd then "r" else "nr") (* recursive vs not *)
    (if d.ra then "ra" else "rn") (* recursion available vs not *)
    (int_of_rcode d.rcode)

let parse_detail bits = 
  bitmatch bits with
  | { qr:1; opcode:4; aa:1; tc:1; rd:1; ra:1; z:3; rcode:4 } 
    -> { qr=qr_of_bool qr; opcode=opcode_of_int opcode; 
         aa; tc; rd; ra; 
         rcode=rcode_of_int rcode }

let build_detail d = 
  (BITSTRING {
    (bool_of_qr d.qr):1; (int_of_opcode d.opcode):4; 
    d.aa:1; d.tc:1; d.rd:1; d.ra:1; (* z *) 0:3;
    (int_of_rcode d.rcode):4
  })

type dns = {
  id          : int16;
  detail      : Bitstring.t;
  questions   : question list;
  answers     : rsrc_record list;
  authorities : rsrc_record list;
  additionals : rsrc_record list;
}

let dns_to_string d = 
  sp "%04x %s <qs:%s> <an:%s> <au:%s> <ad:%s>"
    d.id (d.detail |> parse_detail |> detail_to_string)
    (d.questions ||> question_to_string |> join ",")
    (d.answers ||> rr_to_string |> join ",")
    (d.authorities ||> rr_to_string |> join ",")
    (d.additionals ||> rr_to_string |> join ",")

let parse_dns names bits = 
  let parsen pf ns b n bits = 
    let rec aux rs n bits = 
      match n with
      | 0 -> rs, bits
      | _ -> let r, bits = pf ns b bits in 
             aux (r :: rs) (n-1) bits
    in
    aux [] n bits
  in
  let base = Bitstring.offset_of_bitstring bits in
  (bitmatch bits with
  | { id:16; detail:16:bitstring;
      qdcount:16; ancount:16; nscount:16; arcount:16;
      bits:-1:bitstring
    }
    -> (let questions, bits = parsen parse_question names base qdcount bits in
        let answers, bits = parsen parse_rr names base ancount bits in
        let authorities, bits = parsen parse_rr names base nscount bits in
        let additionals, _ = parsen parse_rr names base arcount bits in 
        let dns = { id; detail; questions; answers; authorities; additionals } in
        dns
    )

  | { _ } -> raise (Unparsable ("parse_dns", bits))
  )

let marshal dns = 
  let pos = ref 0 in
  let (names:(string list,int) Hashtbl.t) = Hashtbl.create 8 in

  let lookup h k =
    if Hashtbl.mem h k then Some (Hashtbl.find h k) else None
  in

  let charstr s =
    sp "%c%s" (s |> String.length |> byte) s 
  in

  let pointer off = 
    let ptr = (0b11_l <<< 14) +++ (int32_of_int off) in
    let hi = ((ptr &&& 0xff00_l) >>> 8) |> Int32.to_int |> byte in
    let lo =  (ptr &&& 0x00ff_l)        |> Int32.to_int |> byte in
    sp "%c%c" hi lo
  in
  
  let mn (labels:domain_name) = 
    let lset = 
      let rec aux = function
        | [] -> [ [] ]
        | x :: [] -> [ x :: [] ]
        | hd :: tl -> (hd :: tl) :: (aux tl)
      in aux labels
    in 

    let bits = ref [] in    
    let pointed = ref false in
    List.iter (fun l ->
      if (not !pointed) then (
        match lookup names l with
        | None 
          -> (Hashtbl.add names l !pos;
              match l with 
              | [] 
                -> (bits := "\000" :: !bits; 
                    pos := !pos + 1
                )
              | label :: tail
                -> (let len = String.length label in
                    assert(len < 64);
                    bits := (charstr label) :: !bits;
                    pos := !pos + len +1
                )
          )
        | Some off
          -> (bits := (pointer off) :: !bits;
              pos := !pos + 2;
              pointed := true
          )
      )
    ) lset;
    if (not !pointed) then (
      bits := "\000" :: !bits;
      pos := !pos + 1
    );
    !bits |> List.rev |> String.concat "" |> (fun s -> 
      BITSTRING { s:((String.length s)*8):string })
  in

  (*
    let mn (labels:domain_name) =
    let bits = ref [] in
    List.iter (fun s -> 
    let cs = charstr s in
    bits := cs :: !bits
    ) labels;
    !bits |> List.rev |> String.concat ""
    |> (fun s -> 
    if String.length s > 0 then
    BITSTRING { s:((String.length s)*8):string; 0:8 }
    else
    BITSTRING { 0:8 }
    )
    in
  *)
  
  let mr r = 
    let mrd (rd:rr_rdata) = match rd with
      | `A ip -> BITSTRING { ip:32 }, `A
      | `NS n -> BITSTRING { (mn n):-1:bitstring }, `NS
      | `MD n -> BITSTRING { (mn n):-1:bitstring }, `MD
      | `MF n -> BITSTRING { (mn n):-1:bitstring }, `MF
      | `CNAME n -> BITSTRING { (mn n):-1:bitstring }, `CNAME
      | `SOA (mname, rname, serial, refresh, retry, expire, minimum)
        -> BITSTRING { (mn mname):-1:bitstring;
                       (mn rname):-1:bitstring;
                       serial:32; refresh:32; retry:32; expire:32; minimum:32 
                     }, `SOA
      | `HINFO (cpu, os) 
        -> BITSTRING { cpu:-1:string; os:-1:string }, `HINFO
      | `MB n -> BITSTRING { (mn n):-1:bitstring }, `MB
      | `MG n -> BITSTRING { (mn n):-1:bitstring }, `MG
      | `MR n -> BITSTRING { (mn n):-1:bitstring }, `MR
      | `MINFO (rm,em) 
        -> BITSTRING { (mn rm):-1:bitstring; (mn em):-1:bitstring }, `MINFO
      | `MX (pref, exchange) 
        -> BITSTRING { pref:16; (mn exchange):-1:bitstring }, `MX
      | `TXT sl
        -> (let s = sl ||> charstr |> join "" in
            (BITSTRING { s:-1:string }), `TXT
        )
        
      | _ -> failwith "not done yet"
    in

    let name = mn r.rr_name in 
    pos := !pos + 2+2+4+2;
    let rdata, rtype = mrd r.rr_rdata in    
    let rdlength = Bitstring.bitstring_length rdata in
    (BITSTRING {
      name:-1:bitstring;
      (int_of_rr_type rtype):16;
      (int_of_rr_class r.rr_class):16;
      r.rr_ttl:32;
      (rdlength/8):16;
      rdata:rdlength:bitstring
    }) 
  in

  let mq q =
    let bits = mn q.q_name in
    pos := !pos + 2+2;
    (BITSTRING {
      bits:-1:bitstring; 
      (int_of_q_type q.q_type):16;
      (int_of_q_class q.q_class):16
    })
  in

  let header = 
    (BITSTRING {
      dns.id:16; 
      dns.detail:16:bitstring; 
      (List.length dns.questions):16;
      (List.length dns.answers):16;
      (List.length dns.authorities):16;
      (List.length dns.additionals):16
    })
  in
  let hl = 2+2+2+2+2+2 in  
  pos := !pos + hl;

  let qs = dns.questions ||> mq in
  let ans = dns.answers ||> mr in
  let auths = dns.authorities ||> mr in
  let adds = dns.additionals ||> mr in

  let bs = Bitstring.concat (header :: qs @ ans @ auths @ adds) in 
  bs
