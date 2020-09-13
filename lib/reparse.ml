(*-------------------------------------------------------------------------
 * Copyright (c) 2020 Bikal Gurung. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License,  v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 *-------------------------------------------------------------------------*)
type state =
  { src : string
  ; len : int
  ; offset : int
  ; cc : current_char }

and current_char =
  [ `Char of char
  | `Eof ]

type 'a t = state -> state * 'a

exception Parse_error of string

let pp_current_char fmt = function
  | `Char c -> Format.fprintf fmt "%c" c
  | `Eof    -> Format.fprintf fmt "EOF"

let parse src p =
  let len = String.length src in
  let state = {src; len; offset = 0; cc = `Eof} in
  try
    let (_ : state), a = p state in
    Ok a
  with exn -> Error exn

let return v state = (state, v)
let ( <|> ) p q state = try p state with (_ : exn) -> q state

let ( >>= ) p f state =
  let state, a = p state in
  f a state

let ( >|= ) p f state =
  let state, a = p state in
  (state, f a)

let ( *> ) p q state =
  let state, _ = p state in
  q state

let ( <* ) p q state =
  let state, _ = q state in
  p state

let delay f state = f () state

let advance n state =
  let current_char offset = `Char state.src.[offset] in
  if state.offset + n < state.len then
    let offset = state.offset + n in
    let state = {state with offset; cc = current_char offset} in
    (state, ())
  else
    let state = {state with offset = state.len; cc = `Eof} in
    (state, ())

let end_of_input state =
  let is_eof =
    match state.cc with
    | `Char _ -> false
    | `Eof    -> true
  in
  (state, is_eof)

let substring len state =
  if state.offset + len < state.len then
    String.sub state.src state.offset len |> Option.some
  else None

let parser_error fmt = Format.kasprintf (fun s -> raise @@ Parse_error s) fmt

let char c state =
  if state.cc = `Char c then
    let state, () = advance 1 state in
    (state, c)
  else
    parser_error
      "%d: char '%c' expected instead of '%a'"
      state.offset
      c
      pp_current_char
      state.cc

let char_if f state =
  match state.cc with
  | `Char c when f c ->
      let state, () = advance 1 state in
      (state, Some c)
  | `Eof
   |`Char _ ->
      (state, None)

let satisfy f state =
  match state.cc with
  | `Char c when f c ->
      let state, () = advance 1 state in
      (state, c)
  | `Char _
   |`Eof ->
      parser_error
        "%d: satisfy is 'false' for char '%a'"
        state.offset
        pp_current_char
        state.cc

let peek_char state =
  let v =
    match state.cc with
    | `Char c -> Some c
    | `Eof    -> None
  in
  (state, v)

let peek_string n state = (state, substring n state)

let string s state =
  let len = String.length s in
  match substring len state with
  | Some s2 ->
      if String.equal s s2 then advance len state
      else parser_error "%d: string \"%s\" not found" state.offset s
  | None    ->
      parser_error "%d: got EOF while parsing string \"%s\"" state.offset s

let rec skip_while f state =
  try
    let state, (_ : char) = satisfy f state in
    skip_while f state
  with (_ : exn) -> (state, ())

let count_skip_while f state =
  let rec loop count state =
    try
      let state, (_ : char) = satisfy f state in
      loop (count + 1) state
    with (_ : exn) -> (state, count)
  in
  loop 0 state

let count_skip_while_string n f =
  let rec loop count =
    peek_string n
    >>= function
    | Some s -> if f s then advance n *> loop (count + 1) else return count
    | None   -> return count
  in
  loop 0

let take_while f state =
  let rec loop buf state =
    try
      let state, c = satisfy f state in
      Buffer.add_char buf c ;
      loop buf state
    with (_ : exn) -> (state, Buffer.contents buf)
  in
  loop (Buffer.create 10) state

let take_while_n n f state =
  let rec loop count buf state =
    if count < n then
      try
        let state, c = satisfy f state in
        Buffer.add_char buf c ;
        loop (count + 1) buf state
      with (_ : exn) -> (state, Buffer.contents buf)
    else (state, Buffer.contents buf)
  in
  loop 0 (Buffer.create n) state

let many t state =
  let rec loop l state =
    try
      let state, a = t state in
      loop (a :: l) state
    with (_ : exn) -> (state, l)
  in
  let state, v = loop [] state in
  (state, List.rev v)

let count_skip_many t state =
  let rec loop count state =
    try
      let state, _ = t state in
      loop (count + 1) state
    with (_ : exn) -> (state, count)
  in
  loop 0 state

let line state =
  let peek_2chars state =
    let c1 = state.cc in
    let c2 =
      let state2, () = advance 1 state in
      state2.cc
    in
    (c1, c2)
  in
  let rec loop buf state =
    match peek_2chars state with
    | `Char '\r', `Char '\n' ->
        let state, () = advance 2 state in
        (state, Buffer.contents buf |> Option.some)
    | `Char '\n', _          ->
        let state, () = advance 1 state in
        (state, Buffer.contents buf |> Option.some)
    | `Char c1, _            ->
        Buffer.add_char buf c1 ;
        let state, () = advance 1 state in
        loop buf state
    | `Eof, _                -> (state, None)
  in
  loop (Buffer.create 1) state
