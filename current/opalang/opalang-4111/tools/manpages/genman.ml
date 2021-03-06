(*
    Copyright © 2011, 2012 MLstate

    This file is part of Opa.

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*)

(** This program is meant to quickly build manpages either from existing sections in proper files, or by a quick-and-dirty parsing of the result of --help *)

let cmdname =
  try
    Sys.argv.(1)
  with
    _ -> (Printf.eprintf ("Usage: %s <cmdname> [sectionbasename]\n") Sys.argv.(0); exit 1)

let sectionbasename =
  try
    Sys.argv.(2)
  with
    _ -> cmdname

let read_section name = File.content_opt (sectionbasename ^ "." ^ name)

let help_summary, help_synopsis, help_description, help_options =
  match read_section "help" with
    None -> "","","",""
  | Some help ->
      let reg0 = (* one line summary ? *)
        Str.regexp ("^.*"^ (Str.quote cmdname) ^"[ \t]*:[ \t]*\\(.*\\)$")
      in
      let is_blank x =
        BaseString.contains " \n\t" x
      in  
      let summary, pos0 =
        try
          if Str.string_partial_match reg0 help 0
          then
            BaseString.ltrim ~is_space:is_blank (Str.matched_group 1 help), (Str.match_end () + 1) (* +1 is meant to skip \n *)
          else
            "", 0
        with
          Not_found -> "", 0
      in
      let reg1 = (* one line synopsis ? *)
        Str.regexp ("^[ \t]*[Uu]sage[ \t]*:.*\\("^ (Str.quote cmdname) ^".*\\)$")
      in
      let synopsis, pos1 =
        try
          if Str.string_partial_match reg1 help pos0
          then
            BaseString.ltrim ~is_space:is_blank (Str.matched_group 1 help), (Str.match_end () +1)
          else
            "", pos0
        with
          Not_found -> "", pos0
      in
      let reg2 = (* beginning of the list of options after the description ? *)
        Str.regexp "^\\(.*[Oo]ptions.*\\):[ \t]*\n\\([ \t]*--?[a-zA-Z0-0]+\\)"
      in
      let description, options =
        try
          let pos1a = Str.search_forward reg2 help pos1
          in
          (* description *)
          BaseString.ltrim ~is_space:is_blank (BaseString.sub help pos1 (pos1a-pos1)),
          (* options *)
          let first_words =
            BaseString.trim ~is_space:is_blank (Str.matched_group 1 help)
          in
          (* N.B. we try keep the last line before the first option unless it's just "Options:" *)
          let pos2 = 
            if first_words = "Options" || first_words = "options" then Str.group_beginning 2 else pos1a
          in
          BaseString.rtrim ~is_space:is_blank (Str.string_after help pos2)
        with
          Not_found ->
            BaseString.ltrim ~is_space:is_blank (Str.string_after help pos1), ""
            (* no option? then put everything in description *)
      in
      summary, synopsis, description, options    

let summary = 
  match read_section "summary", help_summary with
    None, s when s <> "" -> Some(s)
  | x, _ -> x

let synopsis =
  match read_section "synopsis", help_synopsis with
  | None, s when s <> "" -> Some(s)
  | x, _ -> x

let description =
  match read_section "description", help_description with
    None, s when s <> "" -> Some(s)
  | x, _ -> x

let options =
  match read_section "options", help_options with
    None, s when s <> "" -> Some(s)
  | x, _ -> x

let _ = BaseArg.write_simple_manpage
    ~cmdname
    ?summary
    ~section:1
    ~centerheader:"Opa Manual"
    ?synopsis
    ?description
    ?other:(match options with Some(str) -> Some["OPTIONS", str] | None -> None)
    stdout
