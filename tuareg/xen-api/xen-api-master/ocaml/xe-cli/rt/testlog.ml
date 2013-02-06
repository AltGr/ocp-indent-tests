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
(* Log the tests status *)

type result = 
| Success 
| Warning
| Fail 

let string_of_result = function
  | Success -> "Success"
  | Warning -> "Warnings_issued"
  | Fail -> "Failed"

(* The following functions are for command/response and misc logging       *)
(* Each test starts with a call to reset_log, and logs messages via the    *)
(* log function. The log function passes off all logging to the log.ml     *)
(* module, but intercepts 'warning' or 'error' flags, and sets             *)
(* test_status_flag to indicate this *)

let test_status_flag = ref Success
let ignore_errors = ref false

let get_log () = []

let reset_log () =
  test_status_flag := Success

let log level (fmt: ('a, unit, string, unit) format4) : 'a =
  if not !ignore_errors then begin
    match level,!test_status_flag with
      Log.Error,_ -> test_status_flag := Fail
    | Log.Warn,Success -> test_status_flag := Warning
    | _ -> ()
  end;
  Log.log fmt
    
let set_ignore_errors b = ignore_errors := b

(* Once a test is completed, it is registered here. A test_log *)
(* is a human-readable log of what's happened, generated by *)
(* the code above over the course of the test *)

type vm=string
  
type test_type = 
  OfflineVM of vm
| OnlineVM of vm
| GuestVerified of vm
| Other

let test_type_to_string = function
  | OfflineVM x -> "OfflineVM - VM="^x
  | OnlineVM x -> "OnlineVM - VM="^x
  | GuestVerified x -> "GuestVerified - VM="^x
  | Other -> "Other"

type timestamp = string

type test_info = {
  test_result : result;
  test_ts : timestamp;
  test_type: test_type;
  test_name: string;
  test_class: string;
  test_desc: string;
  test_log: string list;
  test_pic: string option;
}
  

let tests = ref ([] : test_info list)

(* Output functions *)
module StringSet = Set.Make(struct type t=string let compare=compare end)

let get_all_classes tests =
  let foldfn set t =
    StringSet.add t.test_class set 
  in
  List.fold_left foldfn StringSet.empty tests 

let get_all_test_names tests =
  let foldfn set t =
    let testname = t.test_name in 
    StringSet.add testname set 
  in
  List.fold_left foldfn StringSet.empty tests 

let get_all_vms tests =
  let foldfn set t =
    match t.test_type with
      OfflineVM vm -> StringSet.add vm set
    | OnlineVM vm -> StringSet.add vm set
    | GuestVerified vm -> StringSet.add vm set
    | Other -> StringSet.add "none" set   
  in
  List.fold_left foldfn StringSet.empty tests

let get_vm_name test_type =
  match test_type with
    OfflineVM x -> x
  | OnlineVM x -> x
  | GuestVerified x -> x
  | _ -> "none"

let zip logone logtwo =
  let compare (s1,_) (s2,_) =
    try
      let time1 = String.sub s1 1 21 in
      let time2 = String.sub s2 1 21 in
      Pervasives.compare time1 time2
    with _ -> 0
  in
  List.merge compare logone logtwo

let get_combined_log t xapi_log =
  let xelog = List.filter (fun s -> String.length s > 22) t.test_log in (* To make sure each line has a timestamp *)
  let xapilog = List.filter (fun s -> String.length s > 22) xapi_log in
  let xelog = List.rev (List.rev_map (fun s -> (s,"xe")) xelog) in
  let xapilog = List.rev (List.rev_map (fun s -> (s,"xapi")) xapilog) in
  let comblog = zip xelog xapilog in
  comblog

let testloganchor test vm = test^vm 
let testxapiloganchor test vm = "xapi"^test^vm 
let testlogurl test vm = "#"^(testloganchor test vm) 
let testxapilogurl test vm = (testxapiloganchor test vm)^".html" 
let testpicurl test vm = (testxapiloganchor test vm)^".jpg" 

(* Big ugly function to output some HTML *)
let output_html version fname =
  let oc = open_out fname in
  Printf.fprintf oc "%s" ("<html><head><title>Test Results</title>"^
                             "<link rel=\"stylesheet\" type=\"text/css\" href=\"test.css\"/>"^
                             "<script type=\"text/javascript\" src=\"test_log.js\"></script></head><body>"^
                             "<div id=\"header\"><h1>Test Results</h1></div>\n");

  Printf.fprintf oc "<h3>Xapi version: %s</h3>" version;

  Printf.fprintf oc "<div class=\"results\">\n";

  let do_test_type_with_vm test_type tests =
    Printf.fprintf oc "<div class=\"resultblock\">";
    let vms = get_all_vms tests in
    let classes = get_all_classes tests in
    
    Printf.fprintf oc "<h2>%s</h2>\n" test_type;
    Printf.fprintf oc "<table><tr><th>Test name</th><th>Description</th>";
    let vm_func vm =
      Printf.fprintf oc "<th>%s</th>" vm
    in
    StringSet.iter vm_func vms;
    Printf.fprintf oc "</tr>\n";
    
    let class_func classname =
      let tests = List.filter 
        (fun t -> t.test_class=classname) tests in
      let testnames = get_all_test_names tests in
      
      Printf.fprintf oc "<tbody>\n";
      let test_func test =
        let tests = List.filter (fun t -> t.test_name=test) tests in
        let desc = (List.hd tests).test_desc in
        Printf.fprintf oc "<tr><td>%s</td><td>%s</td>" test desc;
        let vm_func vm =
          begin
            try
              let t = List.find (fun t -> vm=get_vm_name t.test_type) tests in
              let r =  t.test_result in
              Printf.fprintf oc "<td class=\"%s\">%s<br/><a href=\"#\" onclick=\"toggle_visible('%s')\">command log</a><br/>%s<a href=\"%s\">xapi log</a></td>" 
                (string_of_result r) (string_of_result r) (testloganchor test vm) 
                (match (List.hd tests).test_pic with None -> "" | Some x -> "<a href=\""^x^"\">pic</a>") (testxapilogurl test vm);
            with
              _ -> Printf.fprintf oc "<td>&nbsp;</td>";
          end;
          Printf.fprintf oc "</td>";
        in
        StringSet.iter vm_func vms;
        Printf.fprintf oc "</tr>\n"
      in
      StringSet.iter test_func testnames;
      Printf.fprintf oc "</tbody><tbody><tr><td>&nbsp;</td></tr></tbody>\n"
        
    in
    
    StringSet.iter class_func classes;
    
    Printf.fprintf oc "</table>\n";
    Printf.fprintf oc "</div>\n"
  in  

  let online_tests = List.filter (fun t -> match t.test_type with OnlineVM _ -> true | _ -> false) !tests in
  do_test_type_with_vm "Online tests (VM in running state)" online_tests;
  
  let offline_tests = List.filter (fun t -> match t.test_type with OfflineVM _ -> true | _ -> false) !tests in
  do_test_type_with_vm "Offline tests (VM in stopped state)" offline_tests;
  
  let verified_tests = List.filter (fun t -> match t.test_type with GuestVerified _ -> true | _ -> false) !tests in
  do_test_type_with_vm "Guest verified tests" verified_tests;

  let other_tests = List.filter (fun t -> match t.test_type with Other -> true | _ -> false) !tests in
  do_test_type_with_vm "Other tests" other_tests;

  Printf.fprintf oc "<div class=\"spacer\">&nbsp;</div></div>\n";

  (* Now do output the logs *)
  
  let dolog t =
    let vm=get_vm_name t.test_type in
    let anchor = testloganchor t.test_name vm in
    Printf.fprintf oc "<div id=\"%s\" class=\"log\">\n" anchor;
    Printf.fprintf oc "<a name=\"%s\"/>" anchor;
    Printf.fprintf oc "<h2>Test log</h2>";
    Printf.fprintf oc "<a href=\"#\" onclick=\"toggle_visible('%s')\" style=\"float:right\">close</a>" anchor;
    Printf.fprintf oc "<h3>Test name: %s</h3>" t.test_name;
    Printf.fprintf oc "<h3>Test type: %s</h3>" (test_type_to_string t.test_type);
    Printf.fprintf oc "<h3>Test result: %s</h3>" (string_of_result t.test_result);
    Printf.fprintf oc "<h3>Timestamp: %s</h3>" t.test_ts;
    Printf.fprintf oc "<pre>";
    List.iter (fun s -> 
      Printf.fprintf oc "%s\n" s) t.test_log;
    Printf.fprintf oc "</pre>";
    Printf.fprintf oc "</div>\n"
  in

  List.iter dolog !tests;

  Printf.fprintf oc "</body>\n</html>\n";
  close_out oc



let output_xenrt_chan oc =
  let dogroup group =
    let tests = List.filter (fun t -> t.test_class = group) !tests in
    let test_to_xml test =
      let vm_name = get_vm_name test.test_type in
      Xml.Element ("test",[],[
        Xml.Element ("name",[],[Xml.PCData (test.test_name^"_"^vm_name)]);
        Xml.Element ("state",[],[Xml.PCData (string_of_result test.test_result)]);
        Xml.Element ("log",[],[Xml.PCData (String.concat "\n" test.test_log)]);
      ])
    in
    Xml.Element("group",[],List.map test_to_xml tests)
  in
  let groups = get_all_classes !tests in
  let xml = Xml.Element ("results",[],(StringSet.fold (fun x m -> ((dogroup x)::m)) groups [])) in
  Printf.fprintf oc "%s" (Xml.to_string_fmt xml)


let output_xenrt filename =
  let oc = open_out filename in
  output_xenrt_chan oc;
  close_out oc

let output_txt fname =
  let oc = open_out fname in
  Printf.fprintf oc "Test report\n";
  Printf.fprintf oc "Time: %s\n" (Debug.gettimestring ());
  Printf.fprintf oc "\n\n";
  
  let printtest t =
    let vm = match t.test_type with
        OfflineVM x -> x
      | OnlineVM x -> x
      | GuestVerified x-> x
      | Other -> "none" in      
    Printf.fprintf oc "VM: %10s test:%40s result: %20s\n" vm t.test_name (string_of_result t.test_result)
  in
  
  List.iter printtest (List.rev !tests);

  Printf.fprintf oc "Detailed logs\n";
  
  let printtest t =
    let vm = match t.test_type with
        OfflineVM x -> x
      | OnlineVM x -> x
      | GuestVerified x -> x
      | Other -> "none" in      
    Printf.fprintf oc "VM: %s\ntest: %s\ndescription: %s\nresult: %s\n" vm t.test_name t.test_desc (string_of_result t.test_result);
    Printf.fprintf oc "Log:\n";
    List.iter (fun l -> Printf.fprintf oc "%s" l) (t.test_log)
  in

  List.iter printtest (List.rev !tests);

  close_out oc
    

    
let register_test name test_type class_name description xapi_log pic =
  let log = List.rev (get_log ()) in
  let timestamp = Debug.gettimestring () in
  let vm=get_vm_name test_type in
  let picurl = testpicurl name vm in
  let pic = 
    (match pic with 
      None -> None
    | Some x -> let (_: int) = Sys.command (Printf.sprintf "mv %s %s" x picurl) in Some picurl) in
  let test_info = {
    test_result= !test_status_flag;
    test_ts=timestamp;
    test_type=test_type;
    test_name=name;
    test_class=class_name;
    test_log=log;
    test_desc=description;
    test_pic=pic;
  } in
  tests := test_info::!tests;
  let t = test_info in
  let url = testxapilogurl name vm in
  let oc=open_out url in
  let comblog = get_combined_log t xapi_log in
  Printf.fprintf oc "<html><head></head><body><pre>\n";
  List.iter (fun (l,t) -> 
    if t="xapi" 
    then Printf.fprintf oc "      XAPI %s\n" l
    else Printf.fprintf oc "%s\n" l) comblog;
  Printf.fprintf oc "</pre></body></html>\n";
  close_out oc;
  output_html "" "test_in_progress.html"


