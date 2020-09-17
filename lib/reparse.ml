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
  ; track_lnum : bool (* Track line numbers. *)
  ; mutable offset : int (* Input offset. *)
  ; mutable lnum : int (* Line count. *)
  ; mutable cnum : int (* Column count. *) }

type 'a t = state -> ok:('a -> unit) -> err:(exn -> unit) -> unit

exception
  Parse_error of
    { offset : int
    ; line_number : int
    ; column_number : int
    ; msg : string }

let error ~err msg state =
  err
    (Parse_error
       { offset = state.offset
       ; line_number = state.lnum
       ; column_number = state.cnum
       ; msg })

let parse ?(track_lnum = false) src p =
  let lnum, cnum = if track_lnum then (1, 1) else (0, 0) in
  let state = {src; offset = 0; track_lnum; lnum; cnum} in
  let res = ref None in
  p state ~ok:(fun a -> res := Some a) ~err:(fun e -> raise e) ;
  match !res with
  | None   -> assert false
  | Some a -> a

let advance : int -> unit t =
 fun n state ~ok ~err ->
  let len = String.length state.src in
  if state.offset + n <= len then (
    let offset = state.offset + n in
    if state.track_lnum then
      for i = state.offset to offset - 1 do
        let c = state.src.[i] in
        if Char.equal c '\n' then (
          state.lnum <- state.lnum + 1 ;
          state.cnum <- state.cnum + 1 )
        else state.cnum <- state.cnum + 1
      done ;
    state.offset <- offset ;
    ok () )
  else error ~err "[advance]" state

let return : 'a -> 'a t = fun v _state ~ok ~err:_ -> ok v

let ( >>= ) : 'a t -> ('a -> 'b t) -> 'b t =
 fun p f state ~ok ~err -> p state ~ok:(fun a -> f a state ~ok ~err) ~err

let ( >|= ) : 'a t -> ('a -> 'b) -> 'b t =
 fun p f st ~ok ~err -> p st ~ok:(fun a -> ok (f a)) ~err

let ( <*> ) p q = p >>= fun f -> q >|= f
let ( <$> ) f p = return f <*> p
let map = ( <$> )
let map2 f p q = return f <*> p <*> q
let map3 f p q r = return f <*> p <*> q <*> r
let map4 f p q r s = return f <*> p <*> q <*> r <*> s
let ( <$ ) v p = (fun _ -> v) <$> p
let ( *> ) p q = p >>= fun _ -> q
let ( <* ) p q = p >>= fun a -> a <$ q

let ( <|> ) : 'a t -> 'a t -> 'a t =
 fun p q state ~ok ~err ->
  let ofs = state.offset in
  p state ~ok ~err:(fun e ->
      if ofs = state.offset then q state ~ok ~err else err e)

let ( <?> ) : 'a t -> string -> 'a t =
 fun p err_msg state ~ok ~err ->
  let ofs = state.offset in
  p state ~ok ~err:(fun e ->
      if state.offset = ofs then error ~err err_msg state else err e)

(* let delay f state ~err = f () state ~err *)

(* let named name p state ~err = *)
(*   try p state *)
(*   with exn -> *)
(*     fail (Format.sprintf "[%s] %s" name (Printexc.to_string exn)) state *)

let peek_char : char t =
 fun state ~ok ~err ->
  match state.src.[state.offset] with
  | c           -> ok c
  | exception _ -> error ~err "[peek_char]" state

let peek_string len state ~ok ~err =
  if state.offset + len <= String.length state.src then
    ok (String.sub state.src state.offset len)
  else error ~err "[peek_string]" state

let is_done state = state.offset = String.length state.src
let next = peek_char <?> "[next]" <* advance 1
let is_eoi state ~ok ~err:_ = ok (is_done state)

let eoi : unit t =
 fun state ~ok ~err ->
  if is_done state then ok () else error ~err "[eoi] expected EOI" state

let failing : 'a t -> unit t =
 fun p state ~ok ~err ->
  let ofs = state.offset in
  let error' () = error ~err "[failing] expected failure to succeed" state in
  p
    state
    ~ok:(fun _ -> error' ())
    ~err:(fun _ -> if ofs = state.offset then error' () else ok ())

let lnum state ~ok ~err:_ = ok state.lnum
let cnum state ~ok ~err:_ = ok state.cnum
let offset state ~ok ~err:_ = ok state.offset
let unit = return ()

let char : char -> unit t =
 fun c state ~ok ~err ->
  peek_char
    state
    ~ok:(fun c2 ->
      if Char.equal c c2 then (advance 1) state ~ok ~err
      else error ~err (Format.sprintf "[char] expected '%c'" c) state)
    ~err

let satisfy : (char -> bool) -> char t =
 fun f state ~ok ~err ->
  peek_char
    state
    ~ok:(fun c2 ->
      if f c2 then (c2 <$ advance 1) state ~ok ~err
      else error ~err "[satisfy]" state)
    ~err

let string : string -> unit t =
 fun s state ~ok ~err ->
  let len = String.length s in
  peek_string
    len
    state
    ~ok:(fun s2 ->
      if String.equal s s2 then advance len state ~ok ~err
      else error ~err "[string]" state)
    ~err

let not_followed_by p q = p <* failing q

let optional : 'a t -> 'a option t =
 fun p state ~ok ~err:_ ->
  p state ~ok:(fun a -> ok (Some a)) ~err:(fun _ -> ok None)

let pos state = (state.offset, state.lnum, state.cnum)

let backtrack state (o, l, c) =
  assert (0 <= o && o <= state.offset) ;
  state.offset <- o ;
  state.lnum <- l ;
  state.cnum <- c

let skip : ?at_least:int -> ?up_to:int -> 'a t -> int t =
 fun ?(at_least = 0) ?up_to p state ~ok ~err ->
  if at_least < 0 then invalid_arg "at_least"
  else if Option.is_some up_to && Option.get up_to < 0 then invalid_arg "up_to"
  else () ;

  let up_to = Option.value up_to ~default:(-1) in
  let res = ref 0 in

  let rec loop offset count =
    if (up_to = -1 || count < up_to) && not (is_done state) then
      let bt = pos state in
      p
        state
        ~ok:(fun _ ->
          if offset <> state.offset then
            (loop [@tailcall]) state.offset (count + 1)
          else res := count)
        ~err:(fun _ ->
          backtrack state bt ;
          res := count)
    else res := count
  in

  loop state.offset 0 ;

  if !res >= at_least then ok !res
  else
    error
      ~err
      (Format.sprintf "[skip] unable to parse at_least %d times" at_least)
      state

let take :
    ?at_least:int -> ?up_to:int -> ?sep_by:unit t -> 'a t -> (int * 'a list) t =
 fun ?(at_least = 0) ?up_to ?(sep_by = return ()) p state ~ok ~err ->
  if at_least < 0 then invalid_arg "at_least"
  else if Option.is_some up_to && Option.get up_to < 0 then invalid_arg "up_to"
  else () ;

  let upto = Option.value up_to ~default:(-1) in
  let count = ref 0 in
  let items = ref [] in
  let ok2 (count', items') =
    count := count' ;
    items := items'
  in
  let rec loop count offset acc =
    if (upto = -1 || count < upto) && not (is_done state) then
      let bt = pos state in
      ( p
      >>= fun a ->
      optional sep_by
      >|= function
      | Some _ -> (a, true)
      | None   -> (a, false) )
        state
        ~ok:(fun (a, sep_by_parsed) ->
          if not sep_by_parsed then ok2 (count, a :: acc)
          else if offset <> state.offset then
            (loop [@tailcall]) (count + 1) state.offset (a :: acc)
          else ok2 (count, acc))
        ~err:(fun _ ->
          backtrack state bt ;
          ok2 (count, acc))
    else ok2 (count, acc)
  in
  loop 0 state.offset [] ;
  if !count >= at_least then ok (!count, List.rev !items)
  else
    error
      ~err
      (Format.sprintf "[many] unable to parse at least %d times" at_least)
      state

let line : string t =
 fun state ~ok ~err ->
  let f _ = () in
  let buf = Buffer.create 0 in

  let rec loop () =
    let c1 = ref None in
    let c2 = ref None in
    map2
      (fun a b ->
        c1 := a ;
        c2 := b)
      (optional next)
      (optional next)
      state
      ~ok:f
      ~err:f ;

    match (!c1, !c2) with
    | Some '\r', Some '\n' -> (Buffer.contents buf <$ advance 2) state ~ok ~err
    | Some '\n', _         -> (Buffer.contents buf <$ advance 1) state ~ok ~err
    | Some c1, _           ->
        Buffer.add_char buf c1 ;
        advance 1 state ~ok:f ~err ;
        (loop [@tailcall]) ()
    | None, _              -> ok (Buffer.contents buf)
  in
  loop ()

let char_parser name p state ~ok ~err =
  p state ~ok ~err:(fun exn ->
      error ~err (Format.sprintf "[%s] %s" name (Printexc.to_string exn)) state)

let is_alpha = function
  | 'a' .. 'z'
  | 'A' .. 'Z' ->
      true
  | _ -> false

let is_digit = function
  | '0' .. '9' -> true
  | _          -> false

let alpha = char_parser "ALPHA" (satisfy is_alpha)

let alpha_num =
  char_parser "ALPHA NUM" (satisfy (function c -> is_alpha c || is_digit c))

let bit =
  char_parser
    "BIT"
    (satisfy (function
        | '0'
        | '1' ->
            true
        | _ -> false))

let ascii_char =
  char_parser
    "US-ASCII"
    (satisfy (function
        | '\x00' .. '\x7F' -> true
        | _                -> false))

let cr =
  char_parser
    "CR"
    (satisfy (function
        | '\r' -> true
        | _    -> false))

let crlf = string "\r\n" <?> "[crlf]"

let control =
  char_parser
    "CONTROL"
    (satisfy (function
        | '\x00' .. '\x1F'
        | '\x7F' ->
            true
        | _ -> false))

let digit = char_parser "DIGIT" (satisfy is_digit)

let dquote =
  char_parser
    "DQUOTE"
    (satisfy (function
        | '"' -> true
        | _   -> false))

let hex_digit =
  char_parser
    "HEX DIGIT"
    (satisfy (function
        | c when is_digit c -> true
        | 'A' .. 'F' -> true
        | _ -> false))

let htab =
  char_parser
    "HTAB"
    (satisfy (function
        | '\t' -> true
        | _    -> false))

let lf =
  char_parser
    "LF"
    (satisfy (function
        | '\n' -> true
        | _    -> false))

let octect = next

let space =
  char_parser
    "SPACE"
    (satisfy (function
        | '\x20' -> true
        | _      -> false))

let spaces = snd <$> take space

let vchar =
  char_parser
    "VCHAR"
    (satisfy (function
        | '\x21' .. '\x7E' -> true
        | _                -> false))

let whitespace =
  char_parser
    "WSP"
    (satisfy (function
        | '\x20'
        | '\x09' ->
            true
        | _ -> false))

module Infix = struct
  let ( >>= ) = ( >>= )
  let ( >|= ) = ( >|= )
  let ( <*> ) = ( <*> )
  let ( <$ ) = ( <$ )
  let ( <$> ) = ( <$> )
  let ( *> ) = ( *> )
  let ( <* ) = ( <* )
  let ( <|> ) = ( <|> )
  let ( <?> ) = ( <?> )
end
