(* Simple openflow controller that listens on port 6633 and replies
   with echo request on every packet_in event *)

open Lwt
open Printf
let resolve t = Lwt.on_success t (fun _ -> ())

module OP = Openflow.Ofpacket
module OC = Openflow.Controller
module OE = OC.Event

let pp = Printf.printf
let sp = Printf.sprintf

(* TODO this the mapping is incorrect. the datapath must be moved to the key
 * of the hashtbl *)
type mac_switch = {
  addr: OP.eaddr; 
  switch: OP.datapath_id;
}

type switch_state = {
  mutable mac_cache: (mac_switch, OP.Port.t) Hashtbl.t;
  mutable dpid: OP.datapath_id list
}

let switch_data = { mac_cache = Hashtbl.create 0; 
                    dpid = [] 
                  } 


let datapath_join_cb controller dpid evt =
  let dp = 
    match evt with
    | OE.Datapath_join c -> c
    | _ -> invalid_arg "bogus datapath_join event match!"
  in
  switch_data.dpid <- switch_data.dpid @ [dp];
  pp "+ datapath:0x%012Lx\n" dp

let packet_in_cb controller dpid evt =
  OS.Console.log (sp "* dpid:0x%012Lx evt:%s" dpid (OE.string_of_event evt));
  let (in_port, buffer_id, data, dp) = 
    match evt with
    | OE.Packet_in (inp, buf, dat, dp) -> (inp, buf, dat, dp)
    | _ -> invalid_arg "bogus datapath_join event match!"
  in

  (* Parse Ethernet header *)
  let m = OP.Match.parse_from_raw_packet in_port data in 

  (* save src mac address *)
  let ix = {addr= (OP.Match.get_dl_src m); switch=dpid} in
  if not (Hashtbl.mem switch_data.mac_cache ix ) then
    (Hashtbl.add switch_data.mac_cache ix in_port)
  else 
    (Hashtbl.replace switch_data.mac_cache ix in_port);

  (* check if I know the output port in order to define what type of message
   * we need to send *)
  let ix = {addr= (OP.Match.get_dl_dst m); switch=dpid} in
  if ( (OP.eaddr_is_broadcast ix.addr)
       || (not (Hashtbl.mem switch_data.mac_cache ix)) ) 
  then (
    let pkt = OP.Packet_out.create
      ~buffer_id:buffer_id ~actions:[| OP.(Flow.Output(Port.All , 2000)) |] 
      ~data:data ~in_port:in_port () 
    in
    let bs = OP.Packet_out.packet_out_to_bitstring pkt in 
    resolve (OC.send_of_data controller dpid bs)
  ) else (
    let out_port = (Hashtbl.find switch_data.mac_cache ix) in
    let actions = [| OP.Flow.Output(out_port, 2000) |] in
    let pkt = OP.Flow_mod.create m 0_L OP.Flow_mod.ADD 
      ~buffer_id:(Int32.to_int buffer_id)
      actions () in 
    let bs = OP.Flow_mod.flow_mod_to_bitstring pkt in
    resolve (OC.send_of_data controller dpid bs);
    printf "%s\n" (OP.Match.match_to_string m)
  )

let init controller = 
  pp "test controller register datapath cb\n";
  OC.register_cb controller OE.DATAPATH_JOIN datapath_join_cb;
  pp "test controller register packet_in cb\n";
  OC.register_cb controller OE.PACKET_IN packet_in_cb

let main () =
  Log.info "OF Controller" "starting controller";
  Net.Manager.create (fun mgr interface id ->
    let port = 6633 in 
    OC.listen mgr (None, port) init
    >> return (Log.info "OF Controller" "done!")
  )

