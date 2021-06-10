(*-------------------------------------------------------------------------
 * Copyright (c) 2020, 2021 Bikal Gurung. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License,  v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * %%NAME%% %%VERSION%%
 *-------------------------------------------------------------------------*)

module type PARSER = sig
  type 'a t

  type 'a promise

  type input

  val parse : 'a t -> input -> ('a, string) result promise

  (** {2 Monadic operators} *)

  val return : 'a -> 'a t

  val unit : unit t

  val ignore : _ t -> unit t

  val fail : string -> 'a t

  val bind : ('a -> 'b t) -> 'a t -> 'b t

  val both : 'a t -> 'b t -> ('a * 'b) t

  val map : ('a -> 'b) -> 'a t -> 'b t

  val map2 : ('a -> 'b -> 'c) -> 'a t -> 'b t -> 'c t

  val map3 : ('a -> 'b -> 'c -> 'd) -> 'a t -> 'b t -> 'c t -> 'd t

  val map4 :
    ('a -> 'b -> 'c -> 'd -> 'e) -> 'a t -> 'b t -> 'c t -> 'd t -> 'e t

  module Infix : sig
    val ( >>= ) : 'a t -> ('a -> 'b t) -> 'b t

    val ( >>| ) : 'a t -> ('a -> 'b) -> 'b t

    val ( <*> ) : ('a -> 'b) t -> 'a t -> 'b t

    val ( <$> ) : ('a -> 'b) -> 'a t -> 'b t

    val ( <$ ) : 'a -> 'b t -> 'a t

    val ( $> ) : 'a t -> 'b -> 'b t

    val ( *> ) : _ t -> 'b t -> 'b t

    val ( <* ) : 'a t -> _ t -> 'a t

    val ( <|> ) : 'a t -> 'a t -> 'a t

    val ( let* ) : 'a t -> ('a -> 'b t) -> 'b t

    val ( and* ) : 'a t -> 'b t -> ('a * 'b) t

    val ( let+ ) : 'a t -> ('a -> 'b) -> 'b t

    val ( and+ ) : 'a t -> 'b t -> ('a * 'b) t

    val ( <?> ) : 'a t -> string -> 'a t
  end

  include module type of Infix

  module Let_syntax : sig
    val return : 'a -> 'a t

    val ( >>| ) : 'a t -> ('a -> 'b) -> 'b t

    val ( >>= ) : 'a t -> ('a -> 'b t) -> 'b t

    module Let_syntax : sig
      val return : 'a -> 'a t

      val map : 'a t -> f:('a -> 'b) -> 'b t

      val bind : 'a t -> f:('a -> 'b t) -> 'b t

      val both : 'a t -> 'b t -> ('a * 'b) t

      val map2 : 'a t -> 'b t -> f:('a -> 'b -> 'c) -> 'c t

      val map3 : 'a t -> 'b t -> 'c t -> f:('a -> 'b -> 'c -> 'd) -> 'd t

      val map4 :
        'a t -> 'b t -> 'c t -> 'd t -> f:('a -> 'b -> 'c -> 'd -> 'e) -> 'e t
    end
  end

  (** {2 Char/String parsers} *)

  val peek_char : char t

  val peek_char_opt : char option t

  val peek_string : int -> string t

  val any_char : char t

  val char : char -> char t

  val char_if : (char -> bool) -> char t

  val string : ?case_sensitive:bool -> string -> string t

  val string_of_chars : char list -> string t

  val take_string : int -> string t

  val unsafe_take_cstruct : int -> Cstruct.t t

  (** {2 Alternate parsers} *)

  val any : ?failure_msg:string -> 'a t list -> 'a t

  val alt : 'a t -> 'a t -> 'a t

  val optional : 'a t -> 'a option t

  (** {2 Boolean} *)

  val not_ : 'a t -> unit t

  val is : 'a t -> bool t

  val is_not : 'a t -> bool t

  (** {2 Repetition} *)

  val recur : ('a t -> 'a t) -> 'a t

  val all : 'a t list -> 'a list t

  val all_unit : _ t list -> unit t

  val skip : ?at_least:int -> ?up_to:int -> _ t -> int t

  val take : ?at_least:int -> ?up_to:int -> ?sep_by:_ t -> 'a t -> 'a list t

  val take_while_cb :
    ?sep_by:_ t -> while_:bool t -> on_take_cb:('a -> unit) -> 'a t -> int t

  val take_while : ?sep_by:_ t -> while_:bool t -> 'a t -> 'a list t

  val take_between : ?sep_by:_ t -> start:_ t -> end_:_ t -> 'a t -> 'a list t

  (** RFC 5234 parsers *)

  val alpha : char t

  val alpha_num : char t

  val lower_alpha : char t

  val upper_alpha : char t

  val bit : char t

  val ascii_char : char t

  val cr : char t

  val crlf : string t

  val control : char t

  val digit : char t

  val digits : string t

  val dquote : char t

  val hex_digit : char t

  val htab : char t

  val lf : char t

  val octet : char t

  val space : char t

  val vchar : char t

  val whitespace : char t

  (** {2 Parser State} *)

  val advance : int -> unit t

  val eoi : unit t

  val commit : unit -> unit t

  val pos : int t

  val committed_pos : int t
end

module type INPUT = sig
  type t

  type 'a promise

  val return : 'a -> 'a promise

  val bind : ('a -> 'b promise) -> 'a promise -> 'b promise

  val commit : t -> pos:int -> unit promise

  val get : t -> pos:int -> len:int -> [ `Cstruct of Cstruct.t | `Eof ] promise

  val get_unbuffered :
    t -> pos:int -> len:int -> [ `Cstruct of Cstruct.t | `Eof ] promise

  val committed_pos : t -> int promise
end

module Make (Input : INPUT) :
  PARSER with type 'a promise = 'a Input.promise with type input = Input.t =
struct
  type input = Input.t

  type 'a promise = 'a Input.promise

  type 'a t =
       Input.t
    -> pos:int
    -> succ:(pos:int -> 'a -> unit Input.promise)
    -> fail:(pos:int -> string -> unit Input.promise)
    -> unit Input.promise

  (** Variable names:

      inp/_inp : Input.t

      pos : int

      p/q/r/s .. : 'a t

      f : function type

      v/a : polymorphic value types *)

  (*+++++ Monadic operators +++++*)

  let return : 'a -> 'a t = fun v _inp ~pos ~succ ~fail:_ -> succ ~pos v

  let unit = return ()

  let ignore : _ t -> unit t =
   fun p inp ~pos ~succ ~fail ->
    p inp ~pos ~succ:(fun ~pos _ -> succ ~pos ()) ~fail

  let fail : string -> 'a t = fun msg _inp ~pos ~succ:_ ~fail -> fail ~pos msg

  let bind f p inp ~pos ~succ ~fail =
    p inp ~pos ~succ:(fun ~pos a -> f a inp ~pos ~succ ~fail) ~fail

  let map f p inp ~pos ~succ ~fail =
    p inp ~pos ~succ:(fun ~pos a -> succ ~pos (f a)) ~fail

  module Infix = struct
    let ( >>= ) p f = bind f p

    let ( >>| ) p f = map f p

    let ( <*> ) f q = f >>= fun f' -> map f' q

    let ( <$> ) f p = return f <*> p

    let ( <$ ) v p = (fun _ -> v) <$> p

    let ( $> ) p v = (fun _ -> v) <$> p

    let ( *> ) : _ t -> 'b t -> 'b t = fun p q -> p >>= fun _ -> q

    let ( <* ) : 'a t -> _ t -> 'a t = fun p q -> p >>= fun a -> a <$ q

    let ( <|> ) : 'a t -> 'a t -> 'a t =
     fun p q inp ~pos ~succ ~fail ->
      p inp ~pos ~succ ~fail:(fun ~pos:_ _s -> q inp ~pos ~succ ~fail)

    let both a b = a >>= fun a -> b >>| fun b -> (a, b)

    let ( let* ) = ( >>= )

    let ( and* ) = both

    let ( let+ ) = ( >>| )

    let ( and+ ) = both

    let ( <?> ) : 'a t -> string -> 'a t =
     fun p msg inp ~pos ~succ ~fail ->
      p inp ~pos ~succ ~fail:(fun ~pos _ -> fail ~pos msg)
  end

  include Infix

  let map2 f p q = return f <*> p <*> q

  let map3 f p q r = return f <*> p <*> q <*> r

  let map4 f p q r s = return f <*> p <*> q <*> r <*> s

  module Let_syntax = struct
    let return = return

    let ( >>| ) = ( >>| )

    let ( >>= ) = ( >>= )

    module Let_syntax = struct
      let return = return

      let map p ~f = map f p

      let bind p ~f = bind f p

      let both = both

      let map2 p q ~f = map2 f p q

      let map3 p q r ~f = map3 f p q r

      let map4 p q r s ~f = map4 f p q r s
    end
  end

  let parse (p : 'a t) (inp : Input.t) =
    let v = ref (Error "") in
    p inp ~pos:0
      ~succ:(fun ~pos:_ a -> Input.return (v := Ok a))
      ~fail:(fun ~pos:_ e -> Input.return (v := Error e))
    |> Input.bind (fun () -> Input.return !v)

  let input : int -> Cstruct.t t =
   fun n inp ~pos ~succ ~fail ->
    Input.(
      get inp ~pos ~len:n
      |> bind (function
           | `Cstruct s when Cstruct.length s = n -> succ ~pos s
           | `Cstruct _ ->
             fail ~pos (Format.sprintf "pos:%d, n:%d not enough input" pos n)
           | `Eof -> fail ~pos (Format.sprintf "pos:%d, n:%d eof" pos n)))

  (*+++++ String/Char parsers ++++++*)

  let peek_char : char t =
   fun inp ~pos ~succ ~fail ->
    input 1 inp ~pos
      ~succ:(fun ~pos s -> succ ~pos (Cstruct.get_char s 0))
      ~fail

  let peek_char_opt : char option t =
   fun inp ~pos ~succ ~fail:_ ->
    input 1 inp ~pos
      ~succ:(fun ~pos c -> succ ~pos (Some (Cstruct.get_char c 0)))
      ~fail:(fun ~pos _ -> succ ~pos None)

  let peek_string : int -> string t = fun n -> input n >>| Cstruct.to_string

  let any_char : char t =
    input 1
    >>= fun s _ ~pos ~succ ~fail:_ -> succ ~pos:(pos + 1) (Cstruct.get_char s 0)

  let char : char -> char t =
   fun c ->
    input 1
    >>= fun s _ ~pos ~succ ~fail ->
    let c' = Cstruct.get_char s 0 in
    if c' = c then
      succ ~pos:(pos + 1) c
    else
      fail ~pos (Format.sprintf "[char] pos: %d, expected %C, got %C" pos c c')

  let char_if f =
    input 1
    >>= fun s _ ~pos ~succ ~fail ->
    let c = Cstruct.get_char s 0 in
    if f c then
      succ ~pos:(pos + 1) c
    else
      fail ~pos (Format.sprintf "[char_if] pos:%d %C" pos c)

  let string ?(case_sensitive = true) s =
    let len = String.length s in
    input len
    >>= fun s' _ ~pos ~succ ~fail ->
    let s' = Cstruct.to_string s' in
    if case_sensitive && String.equal s s' then
      succ ~pos:(pos + len) s
    else if String.(equal (lowercase_ascii s) (lowercase_ascii s')) then
      succ ~pos:(pos + len) s
    else
      fail ~pos (Format.sprintf "[string] %S" s)

  let string_of_chars chars = return (String.of_seq @@ List.to_seq chars)

  let take_string : int -> string t =
   fun n ->
    input n
    >>= fun s _ ~pos ~succ ~fail:_ -> succ ~pos:(pos + n) (Cstruct.to_string s)

  (*++++++ Alternates +++++*)

  let any : ?failure_msg:string -> 'a t list -> 'a t =
   fun ?failure_msg parsers inp ~pos ~succ ~fail ->
    let rec loop = function
      | [] ->
        let failure_msg =
          match failure_msg with
          | Some msg -> msg
          | None -> "[any] all parsers failed"
        in
        fail ~pos failure_msg
      | p :: parsers ->
        p inp ~pos
          ~succ:(fun ~pos a -> succ ~pos a)
          ~fail:(fun ~pos:_ _ -> (loop [@tailcall]) parsers)
    in
    loop parsers

  let alt = ( <|> )

  let optional : 'a t -> 'a option t =
   fun p inp ~pos ~succ ~fail:_ ->
    p inp ~pos
      ~succ:(fun ~pos a -> succ ~pos (Some a))
      ~fail:(fun ~pos _ -> succ ~pos None)

  (*+++++ Boolean +++++*)

  let not_ : 'a t -> unit t =
   fun p inp ~pos ~succ ~fail ->
    p inp ~pos
      ~succ:(fun ~pos:_ _ -> fail ~pos "[not_] expected failure but succeeded")
      ~fail:(fun ~pos _ -> succ ~pos ())

  let is : 'a t -> bool t =
   fun p inp ~pos ~succ ~fail:_ ->
    p inp ~pos
      ~succ:(fun ~pos _ -> succ ~pos true)
      ~fail:(fun ~pos _ -> succ ~pos false)

  let is_not : 'a t -> bool t =
   fun p inp ~pos ~succ ~fail:_ ->
    p inp ~pos
      ~succ:(fun ~pos:_ _ -> succ ~pos false)
      ~fail:(fun ~pos:_ _ -> succ ~pos true)

  (*+++++ Repetition +++++*)

  let recur f =
    let rec p inp ~pos ~succ ~fail = f p inp ~pos ~succ ~fail in
    p

  let all : 'a t list -> 'a list t =
   fun parsers inp ~pos ~succ ~fail ->
    let items = ref [] in
    let rec loop pos = function
      | [] -> succ ~pos (List.rev !items)
      | p :: parsers ->
        p inp ~pos
          ~succ:(fun ~pos a ->
            items := a :: !items;
            (loop [@tailcall]) pos parsers)
          ~fail:(fun ~pos e ->
            fail ~pos (Format.sprintf "[all] one of the parsers failed: %s" e))
    in
    loop pos parsers

  let all_unit : _ t list -> unit t =
   fun parsers inp ~pos ~succ ~fail ->
    let rec loop pos = function
      | [] -> succ ~pos ()
      | p :: parsers ->
        p inp ~pos
          ~succ:(fun ~pos _ -> (loop [@tailcall]) pos parsers)
          ~fail:(fun ~pos e ->
            fail ~pos (Format.sprintf "[all] one of the parsers failed: %s" e))
    in
    loop pos parsers

  let skip : ?at_least:int -> ?up_to:int -> 'a t -> int t =
   fun ?(at_least = 0) ?up_to p inp ~pos ~succ ~fail ->
    if at_least < 0 then
      invalid_arg "at_least"
    else if Option.is_some up_to && Option.get up_to < 0 then
      invalid_arg "up_to"
    else
      ();
    let up_to = Option.value up_to ~default:(-1) in
    let rec loop pos skipped_count =
      if up_to = -1 || skipped_count < up_to then
        p inp ~pos
          ~succ:(fun ~pos _ -> (loop [@tailcall]) pos (skipped_count + 1))
          ~fail:(fun ~pos _ -> check skipped_count pos)
      else
        check skipped_count pos
    and check skipped_count pos =
      if skipped_count >= at_least then
        succ ~pos skipped_count
      else
        fail ~pos
          (Format.sprintf "[skip] skipped_count:%d at_least:%d" skipped_count
             at_least)
    in
    loop pos 0

  let sep_by_to_bool ?sep_by =
    match sep_by with
    | None -> return true
    | Some sep_by -> (
      optional sep_by
      >>| function
      | Some _ -> true
      | None -> false)

  let take : ?at_least:int -> ?up_to:int -> ?sep_by:_ t -> 'a t -> 'a list t =
   fun ?(at_least = 0) ?up_to ?sep_by p inp ~pos ~succ ~fail ->
    if at_least < 0 then
      invalid_arg "at_least"
    else if Option.is_some up_to && Option.get up_to < 0 then
      invalid_arg "up_to"
    else
      ();
    let sep_by = sep_by_to_bool ?sep_by in
    let items = ref [] in
    let up_to = Option.value ~default:(-1) up_to in
    let rec loop pos taken_count =
      if up_to = -1 || taken_count < up_to then
        let p = map2 (fun v sep_by_ok -> (v, sep_by_ok)) p sep_by in
        p inp ~pos
          ~succ:(fun ~pos (a, sep_by_ok) ->
            items := a :: !items;
            if sep_by_ok then
              (loop [@tailcall]) pos (taken_count + 1)
            else
              check taken_count pos)
          ~fail:(fun ~pos _ -> check taken_count pos)
      else
        check taken_count pos
    and check taken_count pos =
      if taken_count >= at_least then
        succ ~pos (List.rev !items)
      else
        fail ~pos
          (Format.sprintf "[take] taken_count:%d at_least:%d" taken_count
             at_least)
    in
    loop pos 0

  let take_while_cb :
      ?sep_by:_ t -> while_:bool t -> on_take_cb:('a -> unit) -> 'a t -> int t =
   fun ?sep_by ~while_ ~on_take_cb p inp ~pos ~succ ~fail:_ ->
    let sep_by = sep_by_to_bool ?sep_by in
    let rec loop pos taken_count =
      while_ inp ~pos
        ~succ:(fun ~pos:_ continue ->
          if continue then
            let p = map2 (fun v sep_by_ok -> (v, sep_by_ok)) p sep_by in
            p inp ~pos
              ~succ:(fun ~pos (v, sep_by_ok) ->
                on_take_cb v;
                if sep_by_ok then
                  (loop [@tailcall]) pos (taken_count + 1)
                else
                  succ ~pos taken_count)
              ~fail:(fun ~pos _ -> succ ~pos taken_count)
          else
            succ ~pos taken_count)
        ~fail:(fun ~pos:_ _ -> succ ~pos taken_count)
    in
    loop pos 0

  let take_while : ?sep_by:_ t -> while_:bool t -> 'a t -> 'a list t =
   fun ?sep_by ~while_ p inp ~pos ~succ ~fail ->
    let items = ref [] in
    take_while_cb ?sep_by ~while_
      ~on_take_cb:(fun a -> items := a :: !items)
      p inp ~pos
      ~succ:(fun ~pos _ -> succ ~pos (List.rev !items))
      ~fail

  let take_between : ?sep_by:_ t -> start:_ t -> end_:_ t -> 'a t -> 'a list t =
   fun ?sep_by ~start ~end_ p ->
    start *> take_while ?sep_by ~while_:(is_not end_) p <* end_

  (*+++++ RFC 5234 parsers *)

  let named_ch name f inp ~pos ~succ ~fail =
    (char_if f) inp ~pos ~succ ~fail:(fun ~pos msg ->
        fail ~pos (Format.sprintf "[%s] %s" name msg))

  let is_alpha = function
    | 'a' .. 'z'
    | 'A' .. 'Z' ->
      true
    | _ -> false

  let is_digit = function
    | '0' .. '9' -> true
    | _ -> false

  let alpha = named_ch "ALPHA" is_alpha

  let alpha_num =
    named_ch "ALPHA NUM" (function c -> is_alpha c || is_digit c)

  let lower_alpha =
    named_ch "LOWER ALPHA" (function
      | 'a' .. 'z' -> true
      | _ -> false)

  let upper_alpha =
    named_ch "UPPER ALPHA" (function
      | 'A' .. 'Z' -> true
      | _ -> false)

  let bit =
    named_ch "BIT" (function
      | '0'
      | '1' ->
        true
      | _ -> false)

  let cr =
    named_ch "CR" (function
      | '\r' -> true
      | _ -> false)

  let crlf = string "\r\n" <?> "[crlf]"

  let digit = named_ch "DIGIT" is_digit

  let digits =
    take ~at_least:1 digit
    >>| (fun d -> List.to_seq d |> String.of_seq)
    <?> "[digits]"

  let dquote =
    named_ch "DQUOTE" (function
      | '"' -> true
      | _ -> false)

  let htab =
    named_ch "HTAB" (function
      | '\t' -> true
      | _ -> false)

  let lf =
    named_ch "LF" (function
      | '\n' -> true
      | _ -> false)

  let octet = any_char

  let space =
    named_ch "SPACE" (function
      | '\x20' -> true
      | _ -> false)

  let vchar =
    named_ch "VCHAR" (function
      | '\x21' .. '\x7E' -> true
      | _ -> false)

  let whitespace =
    named_ch "WSP" (function
      | ' '
      | '\t' ->
        true
      | _ -> false)

  let ascii_char =
    named_ch "US-ASCII" (function
      | '\x00' .. '\x7F' -> true
      | _ -> false)

  let control =
    named_ch "CONTROL" (function
      | '\x00' .. '\x1F'
      | '\x7F' ->
        true
      | _ -> false)

  let hex_digit =
    named_ch "HEX DIGIT" (function
      | c when is_digit c -> true
      | 'A' .. 'F' -> true
      | _ -> false)

  (*+++++ Parser State +++++*)

  let advance : int -> unit t =
   fun n _inp ~pos ~succ ~fail:_ -> succ ~pos:(pos + n) ()

  let eoi : unit t =
   fun inp ~pos ~succ ~fail ->
    Input.(
      get inp ~pos ~len:1
      |> bind (function
           | `Cstruct _ ->
             fail ~pos (Format.sprintf "[eof] pos:%d, not eof" pos)
           | `Eof -> succ ~pos ()))

  let commit : unit -> unit t =
   fun () inp ~pos ~succ ~fail:_ ->
    Input.(commit inp ~pos |> bind (fun () -> succ ~pos ()))

  let pos : int t = fun _inp ~pos ~succ ~fail:_ -> succ ~pos pos

  let unsafe_take_cstruct : int -> Cstruct.t t =
   fun n inp ~pos ~succ ~fail ->
    Input.(
      get_unbuffered inp ~pos ~len:n
      |> bind (function
           | `Cstruct s when Cstruct.length s = n ->
             let pos = pos + n in
             commit inp ~pos |> bind (fun () -> succ ~pos s)
           | `Cstruct _ ->
             fail ~pos (Format.sprintf "pos:%d, n:%d not enough input" pos n)
           | `Eof -> fail ~pos (Format.sprintf "pos:%d, n:%d eof" pos n)))

  let committed_pos : int t =
   fun inp ~pos ~succ ~fail:_ ->
    Input.(
      committed_pos inp |> bind (fun commited_pos' -> succ ~pos commited_pos'))
end

module String = struct
  type t' =
    { input : Cstruct.t
    ; mutable committed_pos : int
    }

  include Make (struct
    type 'a promise = 'a

    type t = t'

    let return a = a

    let bind f promise = f promise

    let commit t ~pos =
      t.committed_pos <- pos;
      return ()

    let get_unbuffered t ~pos ~len =
      if len < 0 then raise (invalid_arg "len");
      if pos < 0 || pos < t.committed_pos then
        invalid_arg (Format.sprintf "pos: %d" pos);

      if pos + len <= Cstruct.length t.input then
        `Cstruct (Cstruct.sub t.input pos len)
      else
        `Eof

    let get t ~pos ~len = get_unbuffered t ~pos ~len

    let committed_pos t = return t.committed_pos
  end)

  let of_string s = { input = Cstruct.of_string s; committed_pos = 0 }

  let of_bigstring ?off ?len ba =
    { input = Cstruct.of_bigarray ?off ?len ba; committed_pos = 0 }

  let of_cstruct input = { input; committed_pos = 0 }
end
