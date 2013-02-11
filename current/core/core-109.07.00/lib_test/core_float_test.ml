open Core.Std
open OUnit

let () = Random.self_init ()

(* round:
   ...  <-)[-><-)[-><-)[-><-)[-><-)[-><-)[->   ...
   ... -+-----+-----+-----+-----+-----+-----+- ...
   ... -3    -2    -1     0     1     2     3  ...
   so round x -. x should be in (-0.5,0.5]
*)
let round_test x =
  let y = Float.round x in
  -0.5 < y -. x && y -. x <= 0.5

(* Float.iround ~dir:`Nearest built so this should always be true *)
let iround_nearest_test x =
  let y = Float.iround ~dir:`Nearest x in
  match y with
  | None -> true
  | Some y ->
    let y = Float.of_int y in
    -0.5 < y -. x && y -. x <= 0.5

(* iround_down:
   ... )[<---)[<---)[<---)[<---)[<---)[<---)[  ...
   ... -+-----+-----+-----+-----+-----+-----+- ...
   ... -3    -2    -1     0     1     2     3  ...
   so x -. iround_down x should be in [0,1)
*)
let iround_down_test x =
  let y = Float.iround ~dir:`Down x in
  match y with
  | None -> true
  | Some y ->
    let y = Float.of_int y in
    0. <= x -. y && x -. y < 1.

(* iround_up:
   ...  ](--->](--->](--->](--->](--->](--->]( ...
   ... -+-----+-----+-----+-----+-----+-----+- ...
   ... -3    -2    -1     0     1     2     3  ...
   so iround_up x -. x should be in [0,1)
*)
let iround_up_test x =
  let y = Float.iround ~dir:`Up x in
  match y with
  | None -> true
  | Some y ->
    let y = Float.of_int y in
    0. <= y -. x && y -. x < 1.

(* iround_towards_zero:
   ...  ](--->](--->](---><--->)[<---)[<---)[  ...
   ... -+-----+-----+-----+-----+-----+-----+- ...
   ... -3    -2    -1     0     1     2     3  ...
   so abs x -. abs (iround_towards_zero x) should be in [0,1)
*)
let iround_towards_zero_test x =
  let y = Float.iround ~dir:`Zero x in
  match y with
  | None -> true
  | Some y ->
    let x = Float.abs x in
    let y = Float.abs (Float.of_int y) in
    0. <= x -. y && x -. y < 1.

let special_values_test () =
  Float.round (-.1.50001) = -.2. &&
  Float.round (-.1.5) = -.1. &&
  Float.round (-.0.50001) = -.1. &&
  Float.round (-.0.5) = 0. &&
  Float.round 0.49999 = 0. &&
  Float.round 0.5 = 1. &&
  Float.round 1.49999 = 1. &&
  Float.round 1.5 = 2. &&
  Float.iround_exn ~dir:`Up (-.2.) = -2 &&
  Float.iround_exn ~dir:`Up (-.1.9999) = -1 &&
  Float.iround_exn ~dir:`Up (-.1.) = -1 &&
  Float.iround_exn ~dir:`Up (-.0.9999) = 0 &&
  Float.iround_exn ~dir:`Up 0. = 0 &&
  Float.iround_exn ~dir:`Up 0.00001 = 1 &&
  Float.iround_exn ~dir:`Up 1. = 1 &&
  Float.iround_exn ~dir:`Up 1.00001 = 2 &&
  Float.iround_exn ~dir:`Down (-.1.00001) = -2 &&
  Float.iround_exn ~dir:`Down (-.1.) = -1 &&
  Float.iround_exn ~dir:`Down (-.0.00001) = -1 &&
  Float.iround_exn ~dir:`Down 0. = 0 &&
  Float.iround_exn ~dir:`Down 0.99999 = 0 &&
  Float.iround_exn ~dir:`Down 1. = 1 &&
  Float.iround_exn ~dir:`Down 1.99999 = 1 &&
  Float.iround_exn ~dir:`Down 2. = 2 &&
  Float.iround_exn ~dir:`Zero (-.2.) = -2 &&
  Float.iround_exn ~dir:`Zero (-.1.99999) = -1 &&
  Float.iround_exn ~dir:`Zero (-.1.) = -1 &&
  Float.iround_exn ~dir:`Zero (-.0.99999) = 0 &&
  Float.iround_exn ~dir:`Zero 0.99999 = 0 &&
  Float.iround_exn ~dir:`Zero 1. = 1 &&
  Float.iround_exn ~dir:`Zero 1.99999 = 1 &&
  Float.iround_exn ~dir:`Zero 2. = 2

(* code for generating random floats on which to test functions *)
let absirand () =
  let rec aux acc cnt =
    if cnt = 0 then
      acc
    else
      let bit = if Random.bool () then 1 else 0 in
      aux (2 * acc + bit) (cnt / 2)
  in
  (* we only go to 2. ** 52. -. 1. since our various round functions lose precision after
     this and our tests may (and do) fail when precision is lost *)
  aux 0 (Float.to_int (2. ** 52. -. 1.))

let frand () =
  let x = (float (absirand ())) +. Random.float 1.0 in
  if Random.bool () then
    -1.0 *. x
  else
    x

let test =
  let randoms = List.init ~f:(fun _ -> frand ()) 10_000 in
  "core_float" >:::
    [ "to_string_hum" >::
        (fun () ->
          "random iround_nearest" @? (randoms |! List.for_all ~f:iround_nearest_test);
          "max_int iround_nearest" @? iround_nearest_test (Float.of_int Int.max_value);
          "min_int iround_nearest" @? iround_nearest_test (Float.of_int Int.min_value);
          "random round" @? (randoms |! List.for_all ~f:round_test);
          "random iround_towards_zero_exn" @?
            (randoms |! List.for_all ~f:iround_towards_zero_test);
          "random iround_down_exn" @? (randoms |! List.for_all ~f:iround_down_test);
          "random iround_up_exn" @? (randoms |! List.for_all ~f:iround_up_test);
          "special values" @? special_values_test ();
        )
    ]
