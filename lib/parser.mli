(*-------------------------------------------------------------------------
 * Copyright (c) 2020 Bikal Gurung. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License,  v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * %%NAME%% %%VERSION%%
 *-------------------------------------------------------------------------*)

(** {2 Types} *)

(** {3 Parser type} *)

type 'a t
(** Represents a parser which can parse value ['a].

    Use {!val:parse} to execute a parser. *)

(** {3 Parser input types} *)

(** Parser input interface. *)
class type input =
  object
    method eof : int -> bool
    (** [i#eof offset] returns [true] if [offset] position in [i] represents the
        end of input. *)

    method sub : offset:int -> len:int -> string
    (** [i#sub t ~offset ~len] reads and returns a string of length [len] at
        position [offset] from input [i]. May return a string of length less
        than [len]. *)

    method nth : int -> char
    (** [i#nth n] returns the [n]th char from input [i].

        @raise End_of_file if [n] is at eof. *)
  end

class string_input : string -> input
(** Represents a string as a parser input.

    {e example}

    {[
      module P = Reparse.Parser

      let str_input = new P.string_input "hello world"
    ]} *)

class file_input : Unix.file_descr -> input
(** Represents a unix file descriptor as a parser input.

    {e example}

    {[
      module P = Reparse.Parser
      ;;

      let fd = Unix.openfile fname [Unix.O_RDWR; Unix.O_CREAT] 0o640 in
      let file_input = new P.file_input fd
    ]} *)

(** {2 Parse}

    Evaluate a parser. *)

val parse : ?track_lnum:bool -> input -> 'a t -> 'a
(** [parse ~track_lnum input p] returns value [v] as a result of evaluating
    parser [p] with [input].

    If [track_num] is [true] then the parser tracks both the {e line} and the
    {e column} numbers. It is set to [false] by default.

    Line number and column number both start count from [1] if enabled. They are
    both set to [0] otherwise.

    {i Also see} {!val:lnum} and {!val:cnum}.

    @raise Parser
    {e example - track line and column number}

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let p = P.(take next *> map2 (fun lnum cnum -> (lnum, cnum)) lnum cnum) in
      let input = new P.string_input "hello world" in
      let r1 = P.parse ~track_lnum:true input p in
      r1 = (1, 12)
    ]}

    {e example - don't track line, column number. Default behaviour}

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let p = P.(take next *> map2 (fun lnum cnum -> (lnum, cnum)) lnum cnum) in
      let input = new P.string_input "hello world" in
      let r2 = P.parse input p in
      r2 = (0, 0)
    ]} *)

(** {2 Exception} *)

exception
  Parser of
    { offset : int
    ; line_number : int
    ; column_number : int
    ; msg : string }
(** Raised by parsers which are unable to parse successfully.

    [offset] is the current index position of input at the time of failure.

    [lnum], [cnum] is line number and column number respectively at the time of
    failure.

    [msg] contains an error description. *)

(** {2 Parsers} *)

(** {3 Pure}

    Create parsers from values. *)

val pure : 'a -> 'a t
(** [pure v] returns a parser that always parses value [v].

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "" in
      let r1 = P.(parse input (pure 5)) in
      let r2 = P.(parse input (pure "hello")) in
      r1 = 5 && r2 = "hello"
    ]} *)

val return : 'a -> 'a t
(** [return v] is [pure v]. *)

val unit : unit t
(** [unit] is [return ()]. *)

(** {3 Errors}

    Parsers to handle, generate exceptions and failures. *)

val fail : string -> 'a t
(** [fail err_msg] creates a parser that always fails with [err_msg].

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "" in
      let r =
        try
          let _ = P.(parse input (fail "hello error")) in
          assert false
        with e -> e
      in
      r
      = P.Parser
          {offset = 0; line_number = 0; column_number = 0; msg = "hello error"}
    ]} *)

val named : string -> 'a t -> 'a t
(** [named name p] names parser [p] with [name] which is used when constructing
    exception {!exception:Parser}.

    Also see {!val:Infix.(<?>)}

    {e example}

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let p = P.(char 'a' |> named "parse_c") in
      let input = new P.string_input "zzd" in
      let r =
        try
          let _ = P.parse input p in
          assert false
        with e -> e
      in
      r
      = P.Parser
          { offset = 0
          ; line_number = 0
          ; column_number = 0
          ; msg =
              "[parse_c] Reparse.Parser.Parser(0, 0, 0, \"[char] expected \
               'a'\")" }
    ]} *)

(** {3 Transforms}

    Parsers that can transform from one parser value to another. *)

val map : ('a -> 'b) -> 'a t -> 'b t
(** [map f p] is [f <$> p].

    {e see} {!Infix.(<$>)}

    {e example}

    {[
      module P = Reparse.Parser

      ;;
      let p = P.map (fun a -> a ^ " world") (P.string "hello") in
      let input = new P.string_input "hello" in
      let r = P.parse input p in
      r = "hello world"
    ]} *)

val map2 : ('a -> 'b -> 'c) -> 'a t -> 'b t -> 'c t
(** [map2 f p q] returns a parser which encapsulates value [c] a result of
    applying [f a b]. [a, b] are the parsed value of parsers [p] and [q]
    respectively.

    {[
      module P = Reparse.Parser

      ;;
      let p = P.(map2 (fun a b -> a + b) (return 1) (return 2)) in
      let input = new P.string_input "" in
      let r = P.parse input p in
      r = 3
    ]} *)

val map3 : ('a -> 'b -> 'c -> 'd) -> 'a t -> 'b t -> 'c t -> 'd t
(** [map3 f p q r] returns a parser encapsulating value [d] as a result of
    applying [f a b c]. [a, b, c] are the parsed value of parsers [p], [q] and
    [r] respectively.

    {[
      module P = Reparse.Parser

      ;;
      let p =
        P.(map3 (fun a b c -> a + b + c) (return 1) (return 2) (return 3))
      in
      let input = new P.string_input "" in
      let r = P.parse input p in
      r = 6
    ]} *)

val map4 : ('a -> 'b -> 'c -> 'd -> 'e) -> 'a t -> 'b t -> 'c t -> 'd t -> 'e t
(** [map4 f p q r s] returns a parser encapsulating value [e] as a result of
    applying [f a b c d]. [a, b, c, d] are the parsed value of parsers [p], [q],
    [r] and [s] respectively.

    {[
      module P = Reparse.Parser

      ;;
      let p =
        P.(
          map4
            (fun a b c d -> a + b + c + d)
            (return 1)
            (return 2)
            (return 3)
            (return 4))
      in
      let input = new P.string_input "" in
      let r = P.parse input p in
      r = 10
    ]} *)

(** {3 Choices} *)

val any : 'a t list -> 'a t
(** [any l] returns a parser encapsulating value [a]. [a] is the parser value of
    the first successfully evaluated parser specified in list [l].

    Specified parsers in [l] are evaluated sequentially from left to right.

    The parser fails if none of the parsers in [l] are evaluated successfully.

    Also see {!val:Infix.(<|>)}

    {e example - first successful parser result is returned}

    {[
      module P = Reparse.Parser

      ;;
      let p = P.(any [char 'z'; char 'x'; char 'a']) in
      let input = new P.string_input "zabc" in
      let r = P.parse input p in
      r = 'z'

      ;;
      let p = P.(any [char 'z'; char 'x'; char 'a']) in
      let input = new P.string_input "xabc" in
      let r = P.parse input p in
      r = 'x'

      ;;
      let p = P.(any [char 'z'; char 'x'; char 'a']) in
      let input = new P.string_input "abc" in
      let r = P.parse input p in
      r = 'a'
    ]}

    {e example - parser fails when none of the parsers in [l] are successful}

    {[
      let p = P.(any [char 'z'; char 'x'; char 'a']) in
      let input = new P.string_input "yyy" in
      let r =
        try
          let _ = P.parse input p in
          false
        with _ -> true
      in
      r = true
    ]} *)

(** {3 All}

    All specified parsers must succeed. *)

val all : 'a t list -> 'a list t
(** [all l] returns a parser encapsulating a list of of parser values
    accumulated by evaluating parsers specified in [l].

    Parsers in [l] are evaluated sequentially - from left to right.

    The parser only succeeds if and only if all of the parsers in [l] succeed.

    {e example - all specified parsers succeed}

    {[
      module P = Reparse.Parser

      ;;
      let p = P.(all [char 'a'; char 'b'; char 'c']) in
      let input = new P.string_input "abc" in
      let r = P.parse input p in
      r = ['a'; 'b'; 'c']
    ]}

    {e example - one of the specified parsers} - [char 'c'] {e fails}

    {[
      module P = Reparse.Parser

      ;;
      let p = P.(all [char 'a'; char 'b'; char 'c']) in
      let input = new P.string_input "abd" in
      let r =
        try
          let _ = P.parse input p in
          false
        with _ -> true
      in
      r = true
    ]} *)

val all_unit : 'a t list -> unit t
(** [all_unit l] returns a parser which behaves similar to {!val:all} - except
    all of the parser values are discarded.

    {e example - all specified parsers succeed}

    {[
      module P = Reparse.Parser

      ;;
      let p = P.(all_unit [char 'a'; char 'b'; char 'c']) in
      let input = new P.string_input "abc" in
      let r = P.parse input p in
      r = ()
    ]}

    {e example - one of the specified parsers} - [char 'c'] {e fails}

    {[
      module P = Reparse.Parser

      ;;
      let p = P.(all_unit [char 'a'; char 'b'; char 'c']) in
      let input = new P.string_input "abd" in
      let r =
        try
          let _ = P.parse input p in
          false
        with _ -> true
      in
      r = true
    ]} *)

(** {3 Delay}

    Delays evaluation of parser. *)

val delay : 'a t Lazy.t -> 'a t
(** [delay p] returns a parser which lazily evaluates parser [p].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let p = P.(delay (lazy (char 'z')) <|> delay (lazy (char 'a'))) in
      let input = new P.string_input "abc" in
      let r = P.parse input p in
      r = 'a'
    ]} *)

(** {3 Input state}

    Returns parser input details. *)

val is_eoi : bool t
(** [is_eoi] returns [true] if parser has reached end of input.

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "" in
      let r = P.(parse input is_eoi) in
      r = true

      ;;
      let input = new P.string_input "a" in
      let r = P.(parse input is_eoi) in
      r = false
    ]} *)

val eoi : unit t
(** [eoi] returns a parser which parses end of input. Fails if parser is not at
    end of input.

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "" in
      let r = P.(parse input eoi) in
      r = ()

      ;;
      let input = new P.string_input "a" in
      let r =
        try
          let _ = P.(parse input eoi) in
          false
        with _ -> true
      in
      r = true
    ]} *)

val lnum : int t
(** [lnum] returns a parser encapsulating the current line number. The first
    line number is [1].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "bcb" in
      let p = P.(next *> lnum) in
      let r = P.parse ~track_lnum:true input p in
      r = 1
    ]} *)

val cnum : int t
(** [cnum] returns the current column number. The first column number is [1].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "bcb" in
      let p = P.(next *> cnum) in
      let r = P.parse ~track_lnum:true input p in
      r = 2
    ]} *)

val offset : int t
(** [offset] returns a parser encapsulating the current input offset. The first
    offset is [0].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "bcb" in
      let p = P.(next *> offset) in
      let r = P.parse ~track_lnum:true input p in
      r = 1
    ]} *)

(** {3 Negation, un-negation}*)

val not_ : 'a t -> unit t
(** [not_ p] returns a parser which succeeds if and only if [p] fails to parse.

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "bbb" in
      let p = P.(not_ (char 'a')) in
      let r = P.parse input p in
      r = ()
    ]} *)

val not_followed_by : 'a t -> 'b t -> 'a t
(** [not_followed_by p q] returns a parser which encapsulates value [a] which is
    evaluated from parser [p]. The parser evaluates successfully if parser [p]
    succeeds and then parser [q] fails. The second parser [q] never consumes any
    input.

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "ab" in
      let p = P.(not_followed_by (char 'a') (char 'a')) in
      let r = P.parse input p in
      r = 'a'
    ]}*)

val is_not : 'a t -> bool t
(** [is_not p] returns a parser encapsulating value [true] if [p] fails to parse
    and [false] otherwise. {b Note} evaluating [p] doesn't consume any input.

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "bbb" in
      let r = P.(parse input (is_not (char 'a'))) in
      r = true
    ]} *)

val is : 'a t -> bool t
(** [is p] returns a parser which encapsulates [true] is [p] parses
    successfully, [false] otherwise. {b Note} evaluation of [p] doesn't consume
    any input.

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "bcb" in
      let r = P.(parse input (is (char 'b'))) in
      r = true
    ]} *)

(** {3 Text}

    Text parsing. *)

val peek_char : char t
(** [peek_char t] returns a parser encapsulating a character from input without
    consuming it.

    {[
      module P = Reparse.Parser
      ;;

      let input = new P.string_input "hello" in
      let p = P.peek_char in
      let r = P.parse input p in
      r = 'h'

      let input = new P.string_input "hello" in
      (* Input offset value remains the same. *)
      let p = P.(peek_char *> offset) in
      let r = P.parse input p in
      r = 0
    ]} *)

val peek_string : int -> string t
(** [peek_string n] returns a parser encapsulating a string of length [n] from
    input. No input is consumed.

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "hello" in
      let r = P.(parse input (peek_string 5)) in
      r = "hello"

      ;;
      let input = new P.string_input "hello" in
      let r = P.(parse input (peek_string 5 *> offset)) in
      r = 0
    ]} *)

val next : char t
(** [next] Returns a parser which consumes and encapsulates the next character
    of input.

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "hello" in
      let r = P.(parse input next) in
      r = 'h'
    ]} *)

val char : char -> char t
(** [char c] returns a parser which accepts a character [c] from input exactly.

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "hello" in
      let p = P.char 'h' in
      let r = P.parse input p in
      r = 'h'
    ]} *)

val satisfy : (char -> bool) -> char t
(** [satisfy f] returns a parser which accepts a character [c] from input if
    [f c] is true and encapsulates it.

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "abc" in
      let p =
        P.satisfy (function
            | 'a' -> true
            | _   -> false)
      in
      let r = P.parse input p in
      r = 'a'
    ]} *)

val string : string -> string t
(** [string s] returns a parser which accepts [s] exactly.

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "hello world" in
      let p = P.string "hello" in
      let r = P.parse input p in
      r = "hello"
    ]} *)

val line : [`LF | `CRLF] -> string t
(** [line c] returns a parser which consumes a line of text from input. The line
    delimiter is specified by [c].

    Line delimiter [c] can be either [`LF] or [`CRLF]. This corresponds to [\n]
    or [\r\n] character respectively.

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "line1\r\nline2" in
      let l = P.(parse input (line `CRLF)) in
      l = "line1"
    ]} *)

(** {3 Skip}

    Parsers which discards parsed values. *)

val skip : ?at_least:int -> ?up_to:int -> _ t -> int t
(** [skip ~at_least ~up_to p] returns a parser which discards values returned by
    evaluating parser [p] repeatedly.

    The lower and upper bound of repetition is specified by arguments [at_least]
    and [up_to] respectively. The default value of [at_least] is 0. The default
    value of [up_to] is unspecified, i.e. there is no upper limit.

    The repetition ends when one of the following occurs:

    - [p] evaluates to failure
    - [up_to] upper bound value is reached

    The parser encapsulates the count of times [p] was evaluated successfully.

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "     " in
      let r = P.(parse input (skip space)) in
      r = 5
    ]} *)

val skip_while : _ t -> while_:bool t -> int t
(** [skip_while p ~while_] returns a parser which discards parsed values
    returned by evaluating parser [p] repeatedly.

    [p] is only evaluated when [while_] evaluates to [true].

    The repetition ends when one of the following occurs:

    - [p] evaluates to failure
    - [while_] returns [false]

    {b Note} [while_] does not consume input.

    The parser encapsulates the count of times [p] was evaluated successfully.

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "     " in
      let p = P.(skip_while next ~while_:(is space)) in
      let r = P.parse input p in
      r = 5
    ]} *)

(** {3 Take}

    Collects parsed values *)

val take : ?at_least:int -> ?up_to:int -> ?sep_by:_ t -> 'a t -> 'a list t
(** [take ~at_least ~up_to ~sep_by p] returns a parser which encapsulates a list
    of values returned by evaluating parser [p] repeatedly.

    The lower and upper bound of repetition is specified by arguments [at_least]
    and [up_to] respectively. The default value of [at_least] is [0]. The
    default value of [up_to] is unspecified, i.e. there is no upper limit.

    If [sep_by] is specified then the evaluation of [p] must be followed by a
    successful evaluation of [sep_by]. The parsed value of [sep_by] is
    discarded.

    The repetition ends when one of the following occurs:

    - [p] evaluates to failure
    - [sep_by] evaluates to failure
    - [up_to] upper boudn value is reached

    The parser fails if the count of repetition of [p] does not match the value
    specified by [at_least].

    {e example - default behaviour}

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "aaaaa" in
      let p = P.(take (char 'a')) in
      let r = P.parse input p in
      r = ['a'; 'a'; 'a'; 'a'; 'a']
    ]}

    {e example - specify [~sep_by]}

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "a,a,a,a,a" in
      let p = P.(take ~sep_by:(char ',') (char 'a')) in
      let r = P.parse input p in
      r = ['a'; 'a'; 'a'; 'a']
    ]}

    {e example - specify lower bound argument [at_least]}

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "a,a,a,a,a" in
      (* lower bound restriction met *)
      let p = P.(take ~at_least:3 ~sep_by:(char ',') (char 'a')) in
      let r = P.parse input p in
      r = ['a'; 'a'; 'a'; 'a']
    ]}

    {e example - lower bound not met results in error}

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "a,a,a,a,a" in
      let p = P.(take ~at_least:5 ~sep_by:(char ',') (char 'a')) in
      let r =
        try
          let _ = P.parse input p in
          false
        with _ -> true
      in
      r = true
    ]}

    {e example - specify upper bound [up_to]}

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "a,a,a,a,a" in
      let p = P.(take ~up_to:3 ~sep_by:(char ',') (char 'a')) in
      let r = P.parse input p in
      r = ['a'; 'a'; 'a']
    ]} *)

val take_while : ?sep_by:_ t -> while_:bool t -> 'a t -> 'a list t
(** [take_while ~sep_by p ~while_ p] returns a parser which encapsulates a list
    of values returned by evaluating parser [p] repeatedly.

    [p] is evaluated only after [while_] evaluates to [true].

    If [sep_by] is specified then the evaluation of [p] must be followed by a
    successful evaluation of [sep_by]. The parsed value of [sep_by] is
    discarded.

    The repetition ends when one of the following occurs:

    - [p] evaluates to failure
    - [while_] returns [false]
    - [sep_by] evaluates to failure

    {b Note} [while_] does not consume input.

    {e example - default}

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "aab" in
      let p = P.(take_while ~while_:(is_not (char 'b')) (char 'a')) in
      let r = P.parse input p in
      r = ['a'; 'a']
    ]}

    {e example - specify [sep_by]}

    {[
      module P = Reparse.Parser

      ;;
      let input = new P.string_input "a,a,ab" in
      let p =
        P.(take_while ~sep_by:(char ',') ~while_:(is_not (char 'b')) (char 'a'))
      in
      let r = P.parse input p in
      r = ['a'; 'a']
    ]} *)

val take_while_cb :
  ?sep_by:_ t -> while_:bool t -> on_take_cb:('a -> unit) -> 'a t -> int t
(** [take_while_on ~sep_by ~while_ ~on_take p] returns a parser which evaluates
    [on_take_cb a] on every successful evaluation of [p]. [a] is the parsed
    value of [p].

    [p] is evaluated only after [while_] evaluates to [true].

    If [sep_by] is specified then the evaluation of [p] must be followed by a
    successful evaluation of [sep_by]. The parsed value of [sep_by] is
    discarded.

    [p] is evaluated repeatedly. The repetition ends when one of the following
    occurs:

    [on_take_cb] is the callback function that is called every time [p] is
    evaluated.

    - [p] evaluates to failure
    - [while_] returns [false]
    - [sep_by] evaluates to failure

    [take_while_cb] is the general version of {!val:take_while}. It allows to
    specify how the value [a] is to be collected.

    {b Note} [while_] does not consume input.

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "aaab" in
      let buf = Buffer.create 0 in
      let on_take_cb a = Buffer.add_char buf a in
      let p =
        P.(take_while_cb (char 'a') ~while_:(is_not (char 'b')) ~on_take_cb)
      in
      let r = P.parse input p in
      let s = Buffer.contents buf in
      r = 3 && s = "aaa"
    ]} *)

(** {3 Optional}

    Doesn't fail when parsing is not successful*)

val optional : 'a t -> 'a option t
(** [optional p] returns a parser which evaluates to [Some a] if successful and
    [None] otherwise. [a] is the value evaluated from parser [p].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "ab" in
      let p = P.(optional (char 'a')) in
      let r = P.parse input p in
      r = Some 'a'

      ;;
      let input = new P.string_input "ab" in
      let p = P.(optional (char 'z')) in
      let r = P.parse input p in
      r = None
    ]}*)

(** {2 RFC 5234 parsers}

    Parsers as defined in RFC 5234, Appendix B.1.

    @see <https://tools.ietf.org/html/rfc5234#appendix-B> *)

val alpha : char t
(** [alpha] parses a character in range [A- Z] or [a-z].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "abcdABCD" in
      let r = P.(parse input (take alpha)) in
      r = ['a'; 'b'; 'c'; 'd'; 'A'; 'B'; 'C'; 'D']
    ]} *)

val alpha_num : char t
(** [alpha_num] parses a character in range [A-Z] or [a-z] or [0-9].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "ab123ABCD" in
      let r = P.(parse input (take alpha_num)) in
      r = ['a'; 'b'; '1'; '2'; '3'; 'A'; 'B'; 'C'; 'D']
    ]} *)

val bit : char t
(** [bit] parses a character which is either ['0'] or ['1'].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "0110 ab" in
      let r = P.(parse input (take bit)) in
      r = ['0'; '1'; '1'; '0']
    ]} *)

val ascii_char : char t
(** [ascii_char] parses any US-ASCII character.

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "0110 abc '" in
      let r = P.(parse input (take ascii_char)) in
      r = ['0'; '1'; '1'; '0'; ' '; 'a'; 'b'; 'c'; ' '; '\'']
    ]} *)

val cr : char t
(** [cr] parses character ['\r'].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "\rab" in
      let r = P.(parse input cr) in
      r = '\r'
    ]} *)

val crlf : string t
(** [crlf] parses string ["\r\n"].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "\r\n abc" in
      let r = P.(parse input crlf) in
      r = "\r\n"
    ]} *)

val control : char t
(** [control] parses characters in range [0x00 - 0x1F] or character [0x7F].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "\x00" in
      let r = P.(parse input control) in
      r = '\x00'
    ]} *)

val digit : char t
(** [digit] parses a digit character - [0 .. 9].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "0123456789a" in
      let r = P.(parse input (take digit)) in
      r = ['0'; '1'; '2'; '3'; '4'; '5'; '6'; '7'; '8'; '9']
    ]} *)

val dquote : char t
(** [dquote] parses double quote character ['"'].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "\"hello " in
      let r = P.(parse input dquote) in
      r = '"'
    ]} *)

val hex_digit : char t
(** [hex_digit] parses any of the hexadecimal digits - [0..9, A, B, C, D, E, F].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "0ABCDEFa" in
      let r = P.(parse input (take hex_digit)) in
      r = ['0'; 'A'; 'B'; 'C'; 'D'; 'E'; 'F']
    ]} *)

val htab : char t
(** [htab] parses a horizontal tab character ['\t'].

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "\t" in
      let r = P.(parse input htab) in
      r = '\t'
    ]} *)

val lf : char t
(** [lf] parses a linefeed ['\n'] character.

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "\n" in
      let r = P.(parse input lf) in
      r = '\n'
    ]} *)

val octet : char t
(** [octect] parses any character in the range [\x00 - \xFF]. Synonym for
    {!val:next}

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "0110 abc '" in
      let r = P.(parse input (take octet)) in
      r = ['0'; '1'; '1'; '0'; ' '; 'a'; 'b'; 'c'; ' '; '\'']
    ]} *)

val space : char t
(** [space] parses a space character.

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input " abc '" in
      let r = P.(parse input space) in
      r = ' '
    ]} *)

val spaces : char list t
(** {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "   abc" in
      let r = P.(parse input spaces) in
      r = [' '; ' '; ' ']
    ]} *)

val vchar : char t
(** [vchar] parses any of the visible - printable - characters.

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "0110abc\x00" in
      let r = P.(parse input (take vchar)) in
      r = ['0'; '1'; '1'; '0'; 'a'; 'b'; 'c']
    ]} *)

val whitespace : char t
(** [whitespace] parses a space [' '] or horizontal tab ['\t'] character.

    {[
      module P = Reparse.Parser
      open P.Infix

      ;;
      let input = new P.string_input "\t \t " in
      let r = P.(parse input (take whitespace)) in
      r = ['\t'; ' '; '\t'; ' ']
    ]} *)

(** {2 Infix & Let operators} *)

(** Provides {i infix} and {i let syntax} operators.

    Usage recommendation:

    {[ open Reparse.Parser.Infix ]} *)
module Infix : sig
  val ( >>= ) : 'a t -> ('a -> 'b t) -> 'b t
  (** [p >>= f] Binder.

      Returns a parser as a result of applying [f a] where [a] is the parsed
      value of [p].

      {[
        module P = Reparse.Parser
        open P.Infix

        ;;
        let p = P.(char 'h' >>= fun c -> return (Char.code c)) in
        let input = new P.string_input "hello" in
        let r = P.parse input p in
        r = 104
      ]} *)

  val ( >|= ) : 'a t -> ('a -> 'b) -> 'b t
  (** [p >|= f] Mapper.

      Returns a parser which encapsulates value [b] as a result of applying
      [f a] where [a] is the parsed value of [p].

      {[
        module P = Reparse.Parser
        open P.Infix

        ;;
        let p = P.(char 'h' >|= fun c -> Char.code c) in
        let input = new P.string_input "hello" in
        let r = P.parse input p in
        r = 104
      ]} *)

  val ( <*> ) : ('a -> 'b) t -> 'a t -> 'b t
  (** [pf <*> q] Applicative.

      Returns a parser encapsulating value [b] as a result of applying [f a],
      where [f] is the function value parsed by parser [pf] and [a] is the value
      parsed by [q].

      {[
        module P = Reparse.Parser
        open P.Infix

        ;;
        let p = P.(return (fun a -> a + 2) <*> return 2) in
        let input = new P.string_input "hello" in
        let r = P.parse input p in
        r = 4
      ]} *)

  val ( <$ ) : 'b -> 'a t -> 'b t
  (** [v <$ p] replaces the result of [p] with [v].

      {[
        module P = Reparse.Parser
        open P.Infix

        ;;
        let p = P.("hello" <$ char 'h') in
        let input = new P.string_input "hello" in
        let r = P.parse input p in
        r = "hello"
      ]} *)

  val ( <$> ) : ('a -> 'b) -> 'a t -> 'b t
  (** [f <$> p] returns a parser encapsulating value [b] as a result of applying
      [f a]. [a] is value parsed by [p].

      {[
        module P = Reparse.Parser
        open P.Infix

        ;;
        let p = P.((fun a -> a ^ " world") <$> string "hello") in
        let input = new P.string_input "hello" in
        let r = P.parse input p in
        r = "hello world"
      ]} *)

  val ( *> ) : _ t -> 'a t -> 'a t
  (** [p *> q] returns a parser which executes parsers [p] and then [q] and
      encapsulates value [a]. [a] is the parsed value of [q]. The parsed value
      of [p] is discarded.

      {[
        module P = Reparse.Parser
        open P.Infix

        ;;
        let p = P.(string "world" *> P.return "hello") in
        let input = new P.string_input "world" in
        let r = P.parse input p in
        r = "hello"
      ]} *)

  val ( <* ) : 'a t -> _ t -> 'a t
  (** [p <* q] similar to [*>]. However, the result of [q] is discarded instead.

      {[
        module P = Reparse.Parser
        open P.Infix

        ;;
        let p = P.(string "world" <* P.return "hello") in
        let input = new P.string_input "world" in
        let r = P.parse input p in
        r = "world"
      ]} *)

  val ( <|> ) : 'a t -> 'a t -> 'a t
  (** [p <|> q] Alternate.

      Returns a parser which evaluates both [p] and [q] returning values [a] and
      [b] respectively. If [p] succeeds then it returns a parser encapsulating
      [a]. If [p] fails and [q] is a success, then it returns a parser
      encapsulating [b].

      If both - [p] and [q] - fails, then the parser fails with [Parser].

      @raise Parser
      {[
        module P = Reparse.Parser
        open P.Infix

        ;;
        let p = P.(char 'h' <|> char 'w') in
        let input = new P.string_input "world" in
        let r = P.parse input p in
        r = 'w'

        ;;
        let p = P.(char 'h' <|> char 'w') in
        let input = new P.string_input "hello" in
        let r = P.parse input p in
        r = 'h'

        ;;
        let p = P.(char 'h' <|> char 'w') in
        let input = new P.string_input "" in
        let r =
          try
            let _ = P.parse input p in
            false
          with _ -> true
        in
        r = true
      ]} *)

  val ( <?> ) : 'a t -> string -> 'a t
  (** [p <?> err_mg] returns a parser where if parser [p] is unable to parse
      successfully then fails with error message [err_msg]. Used as a last
      choice in [<|>], e.g. [a <|> b <|> c <?> "expected a b c"].

      {[
        module P = Reparse.Parser
        open P.Infix

        ;;
        let input = new P.string_input "" in
        let p = P.next <?> "[error]" in
        let r =
          try
            let _ = P.parse input p in
            false
          with
          | P.Parser
              {offset = 0; line_number = 0; column_number = 0; msg = "[error]"}
            ->
              true
          | _ -> false
        in
        r = true
      ]} *)

  val ( let* ) : 'a t -> ('a -> 'b t) -> 'b t
  (** [let*] is let binding for {!val:(>>=)}

      {e example}

      {[
        module P = Reparse.Parser
        open P.Infix

        ;;
        let input = new P.string_input "" in
        let p =
          let* a = P.return 5 in
          let total = a + 5 in
          P.return total
        in
        let r = P.parse input p in
        r = 10
      ]} *)

  val ( let+ ) : 'a t -> ('a -> 'b) -> 'b t
  (** [let*] is let binding for {!val:(>|=)}

      {e example}

      {[
        module P = Reparse.Parser
        open P.Infix

        ;;
        let input = new P.string_input "" in
        let p =
          let+ a = P.return 5 in
          let total = a + 5 in
          total
        in
        let r = P.parse input p in
        r = 10
      ]} *)
end
