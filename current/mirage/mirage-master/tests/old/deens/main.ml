(*
 * Copyright (c) 2005-2010 Anil Madhavapeddy <anil@recoil.org>
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

open Lwt 
open Printf

module Eth = Mletherip.Ethif.T(OS.Ethif)
module Arp = Mletherip.Arp.T(Eth)
module IPv4 = Mletherip.Ipv4.T(Eth)(Arp)
module ICMP = Mletherip.Icmp.T(IPv4)
module UDP = Mludp.Udp.Socket(IPv4)
module TCP = Mltcp.Tcp.Server(IPv4)
module DHCP = Mldhcp.Client.T(IPv4)(UDP)(OS.Time)


module M = Mpl.Mpl_stdlib
module DL = Mldns.Dnsloader
module DQ = Mldns.Dnsquery
module DR = Mldns.Dnsrr

let dnstrie = DL.state.DL.db.DL.trie

(* Specialise dns packet to a smaller closure *)
let dnsfn = Mpl.Dns.t ~qr:`Answer ~opcode:`Query ~truncation:0 ~rd:0 ~ra:0 

let log (ipv4:Mpl.Ipv4.o) (dnsq:Mpl.Dns.Questions.o) =
  printf "%.0f: %s %s %s (%s)\n%!" (OS.Clock.time())
    (String.concat "." dnsq#qname)
    (Mpl.Dns.Questions.qtype_to_string dnsq#qtype)
    (Mpl.Dns.Questions.qclass_to_string dnsq#qclass)
    (Mlnet.Types.(ipv4_addr_to_string (ipv4_addr_of_uint32 ipv4#src)))

let get_answer (qname,qtype) id =
  let qname = List.map String.lowercase qname in  
  let ans = DQ.answer_query qname qtype dnstrie in
  let authoritative = if ans.DQ.aa then 1 else 0 in
  let questions = [Mpl.Dns.Questions.t ~qname:qname ~qtype:qtype ~qclass:`IN] in
  let rcode = (ans.DQ.rcode :> Mpl.Dns.rcode_t) in
  dnsfn ~id ~authoritative ~rcode
    ~questions ~answers:ans.DQ.answer
    ~authority:ans.DQ.authority
    ~additional:ans.DQ.additional

let zonebuf = "
$ORIGIN www.openmirage.org. ;
$TTL    240
www.openmirage.org. 604800 IN SOA  (
        www.openmirage.org. anil.recoil.org.
        2010100401 ; serial
        3600 ; refresh
        1800 ; retry
        3024000 ; expire
        1800 ; minimum
)
        IN  NS     ns1.www.openmirage.org.
        IN  NS     ns2.www.openmirage.org.
ns1     IN  A      184.72.217.237
ns2     IN  A      204.236.217.197
@       IN  MX     smtp.recoil.org.
@       IN  A      184.73.180.47
@       IN  TXT    \"I wish I were a llama in Peru!\"
"

let init_dns t =
  Mldns.Dnsserver.load_zone [] zonebuf;
  printf "Loaded zone\n%!"; 
  (fun ip udp ->
    let env = udp#data_env in
    Mpl.Mpl_stdlib.Mpl_dns_label.init_unmarshal env;
    let d = Mpl.Dns.unmarshal env in
    let q = d#questions.(0) in
    log ip d#questions.(0);
    let r = get_answer (q#qname, q#qtype) d#id in
    let dnsfn env = 
      Mpl.Mpl_stdlib.Mpl_dns_label.init_marshal env;
      ignore(r env) in
    let dest_ip = Mlnet.Types.ipv4_addr_of_uint32 ip#src in
    let udp = Mpl.Udp.t ~source_port:53 ~dest_port:udp#source_port
        ~checksum:0 ~data:(`Sub dnsfn) in
    UDP.output t ~dest_ip udp
  )

let main () =
  lwt vifs = Eth.enumerate () in
  let vif_t = List.map (fun id ->
      lwt (ip,thread) = IPv4.create id in
      let icmp = ICMP.create ip in
      let udp,_ = UDP.create ip in
      lwt () = OS.Time.sleep 5. in
      lwt dhcp = DHCP.create ip udp in
      UDP.listen udp 53 (init_dns udp);
      thread
    ) vifs in
  join vif_t

let _ = OS.Main.run (main ())

