(*-------------------------------------------------------------------------
 * Copyright (c) 2020 Bikal Gurung. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License,  v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 *-------------------------------------------------------------------------*)

module Make (I : Input.S) : Parser_sig.S with type input = I.t = struct
  type input = I.t

  type state =
    { input : input
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

  let parse ?(track_lnum = false) input p =
    let lnum, cnum = if track_lnum then (1, 1) else (0, 0) in
    let state = {input; offset = 0; track_lnum; lnum; cnum} in
    let res = ref None in
    p state ~ok:(fun a -> res := Some a) ~err:(fun e -> raise e) ;
    match !res with
    | None   -> assert false
    | Some a -> a

  let fail : string -> 'a t =
   fun err_msg state ~ok:_ ~err -> error ~err err_msg state

  let next state ~ok ~err =
    match I.nth state.offset state.input with
    | c           ->
        state.offset <- state.offset + 1 ;
        if state.track_lnum then
          if Char.equal c '\n' then (
            state.lnum <- state.lnum + 1 ;
            state.cnum <- 1 )
          else state.cnum <- state.cnum + 1 ;
        ok c
    | exception _ -> error ~err "[next]" state

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

  let unit = return ()
  let pos state = (state.offset, state.lnum, state.cnum)

  let backtrack state (o, l, c) =
    assert (0 <= o && o <= state.offset) ;
    state.offset <- o ;
    state.lnum <- l ;
    state.cnum <- c

  let any : 'a t list -> 'a t =
   fun l state ~ok ~err ->
    let item = ref None in
    let err' () = error ~err "[any] all parsers failed" state in
    let rec loop = function
      | []      -> err' ()
      | p :: tl ->
          let ofs = state.offset in
          p
            state
            ~ok:(fun a ->
              if state.offset = ofs then (loop [@tailrec]) tl
              else item := Some a)
            ~err:(fun _ -> (loop [@tailrec]) tl)
    in
    loop l ;
    match !item with
    | Some a -> ok a
    | None   -> err' ()

  let all : 'a t list -> 'a list t =
   fun l state ~ok ~err ->
    let items = ref [] in
    let bt = pos state in
    let rec loop = function
      | []      -> ok (List.rev !items)
      | p :: tl ->
          p
            state
            ~ok:(fun a ->
              items := a :: !items ;
              (loop [@tailrec]) tl)
            ~err:(fun _ ->
              backtrack state bt ;
              error ~err "[all] one of the parsers failed" state)
    in
    loop l

  let all_unit : 'a t list -> unit t =
   fun l state ~ok ~err ->
    let l' = List.map (fun p -> p *> unit) l in
    ((all l' <?> "[all_unit] one of the parsers failed") *> unit) state ~ok ~err

  let delay p state ~ok ~err = Lazy.force p state ~ok ~err

  let named name p state ~ok ~err =
    p state ~ok ~err:(fun e ->
        error ~err (Format.sprintf "[%s] %s" name (Printexc.to_string e)) state)

  let peek_char : char t =
   fun state ~ok ~err ->
    match I.nth state.offset state.input with
    | c           -> ok c
    | exception _ -> error ~err "[peek_char]" state

  let peek_string len state ~ok ~err =
    match I.sub ~offset:state.offset ~len state.input with
    | s            -> ok s
    | exception _e -> error ~err "[peek_string]" state

  let is_done state = I.eof state.offset state.input
  let is_eoi state ~ok ~err:_ = ok (is_done state)

  let eoi : unit t =
   fun state ~ok ~err ->
    if is_done state then ok () else error ~err "[eoi] expected EOI" state

  let not_ : 'a t -> unit t =
   fun p state ~ok ~err ->
    let ofs = state.offset in
    let error' () = error ~err "[failing] expected failure to succeed" state in
    p
      state
      ~ok:(fun _ -> error' ())
      ~err:(fun _ -> if ofs = state.offset then ok () else error' ())

  let is_not : 'a t -> bool t =
   fun p state ~ok ~err:_ ->
    let ofs = state.offset in
    let bt = pos state in
    p
      state
      ~ok:(fun _ ->
        backtrack state bt ;
        ok false)
      ~err:(fun _ ->
        if ofs = state.offset then ok true
        else (
          backtrack state bt ;
          ok false ))

  let is : 'a t -> bool t =
   fun p state ~ok ~err:_ ->
    let ofs = state.offset in
    let bt = pos state in
    p
      state
      ~ok:(fun _ ->
        if ofs = state.offset then ok false else backtrack state bt ;
        ok true)
      ~err:(fun _ ->
        backtrack state bt ;
        ok false)

  let lnum state ~ok ~err:_ = ok state.lnum
  let cnum state ~ok ~err:_ = ok state.cnum
  let offset state ~ok ~err:_ = ok state.offset

  let char : char -> char t =
   fun c state ~ok ~err ->
    peek_char
      state
      ~ok:(fun c2 ->
        if Char.equal c c2 then (c <$ next) state ~ok ~err
        else error ~err (Format.sprintf "[char] expected '%c'" c) state)
      ~err

  let satisfy : (char -> bool) -> char t =
   fun f state ~ok ~err ->
    peek_char
      state
      ~ok:(fun c2 ->
        if f c2 then (c2 <$ next) state ~ok ~err
        else error ~err "[satisfy]" state)
      ~err

  let not_followed_by p q = p <* not_ q

  let optional : 'a t -> 'a option t =
   fun p state ~ok ~err:_ ->
    p state ~ok:(fun a -> ok (Some a)) ~err:(fun _ -> ok None)

  let skip : ?at_least:int -> ?up_to:int -> 'a t -> int t =
   fun ?(at_least = 0) ?up_to p state ~ok ~err ->
    if at_least < 0 then invalid_arg "at_least"
    else if Option.is_some up_to && Option.get up_to < 0 then
      invalid_arg "up_to"
    else () ;

    (* if at_least fails then backtrack to this value. *)
    let at_least_bt = pos state in

    let up_to = ref (Option.value up_to ~default:(-1)) in
    let res = ref 0 in
    let rec loop offset count =
      if !up_to = -1 || count < !up_to then
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
    else (
      backtrack state at_least_bt ;
      error
        ~err
        (Format.sprintf "[skip] unable to parse at_least %d times" at_least)
        state )

  let string : string -> string t =
   fun s state ~ok ~err ->
    let len = String.length s in
    peek_string
      len
      state
      ~ok:(fun s2 ->
        if String.equal s s2 then (s <$ skip ~up_to:len next) state ~ok ~err
        else error ~err "[string]" state)
      ~err

  let skip_while : _ t -> while_:bool t -> int t =
   fun p ~while_ state ~ok ~err:_ ->
    let condition = ref true in
    let skip_count = ref 0 in
    let do_condition () =
      let bt = pos state in
      while_
        state
        ~ok:(fun condition' -> condition := condition')
        ~err:(fun _ -> condition := false) ;
      backtrack state bt
    in
    do_condition () ;
    while !condition do
      let bt = pos state in
      (p *> unit)
        state
        ~ok:(fun _ ->
          skip_count := !skip_count + 1 ;
          do_condition ())
        ~err:(fun _ ->
          backtrack state bt ;
          condition := false)
    done ;
    ok !skip_count

  let take : ?at_least:int -> ?up_to:int -> ?sep_by:_ t -> 'a t -> 'a list t =
   fun ?(at_least = 0) ?up_to ?sep_by p state ~ok ~err ->
    if at_least < 0 then invalid_arg "at_least"
    else if Option.is_some up_to && Option.get up_to < 0 then
      invalid_arg "up_to"
    else () ;

    let sep_by =
      match sep_by with
      | None   -> unit
      | Some p -> p *> unit
    in

    let upto = Option.value up_to ~default:(-1) in
    let count = ref 0 in
    let items = ref [] in
    let ok2 (count', items') =
      count := count' ;
      items := items'
    in

    (* if at_least fails then backtrack to this value. *)
    let at_least_bt = pos state in

    let rec loop count offset acc =
      if upto = -1 || count < upto then
        let bt = pos state in
        (p <* sep_by)
          state
          ~ok:(fun a ->
            if offset <> state.offset then
              (loop [@tailcall]) (count + 1) state.offset (a :: acc)
            else ok2 (count, acc))
          ~err:(fun _ ->
            backtrack state bt ;
            ok2 (count, acc))
      else ok2 (count, acc)
    in

    loop 0 state.offset [] ;

    if !count >= at_least then ok (List.rev !items)
    else (
      backtrack state at_least_bt ;
      error
        ~err
        (Format.sprintf "[take] unable to parse at least %d times" at_least)
        state )

  let take_while_cb :
      ?sep_by:_ t -> 'a t -> while_:bool t -> on_take_cb:('a -> unit) -> int t =
   fun ?sep_by p ~while_ ~on_take_cb state ~ok ~err:_ ->
    let cond = ref true in
    let take_count = ref 0 in
    let do_condition () =
      let bt = pos state in
      while_
        state
        ~ok:(fun cond' -> cond := cond')
        ~err:(fun _ -> cond := false) ;
      backtrack state bt
    in
    let sep_by =
      match sep_by with
      | None   -> unit
      | Some p -> p *> unit
    in
    do_condition () ;
    while !cond do
      let bt = pos state in
      (p <* sep_by)
        state
        ~ok:(fun a ->
          take_count := !take_count + 1 ;
          on_take_cb a ;
          do_condition ())
        ~err:(fun _ ->
          backtrack state bt ;
          cond := false)
    done ;
    ok !take_count

  let take_while : ?sep_by:_ t -> 'a t -> while_:bool t -> 'a list t =
   fun ?sep_by p ~while_ state ~ok ~err ->
    let items = ref [] in
    let count = ref 0 in
    let on_take_cb a = items := a :: !items in
    let sep_by =
      match sep_by with
      | None   -> unit
      | Some p -> p *> unit
    in
    take_while_cb
      p
      ~sep_by
      ~while_
      ~on_take_cb
      state
      ~ok:(fun count' -> count := count')
      ~err ;
    ok (List.rev !items)

  let char_parser name p state ~ok ~err =
    p state ~ok ~err:(fun exn ->
        error
          ~err
          (Format.sprintf "[%s] %s" name (Printexc.to_string exn))
          state)

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

  let spaces = take space

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

  let line : [`LF | `CRLF] -> string t =
   fun line_delimiter state ~ok ~err ->
    let delimit =
      match line_delimiter with
      | `LF   -> lf *> unit
      | `CRLF -> crlf *> unit
    in
    let buf = Buffer.create 0 in
    take_while_cb
      next
      ~while_:(is_not delimit)
      ~on_take_cb:(fun c -> Buffer.add_char buf c)
      state
      ~ok:(fun (_ : int) -> ())
      ~err ;

    ( is_eoi
    >>= function
    | true  -> unit
    | false -> delimit )
      state
      ~ok:(fun (_ : unit) -> ())
      ~err ;
    ok (Buffer.contents buf)

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
    let ( let* ) = ( >>= )
    let ( let+ ) = ( >|= )
  end
end