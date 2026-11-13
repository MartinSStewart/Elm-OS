{-
   MIT License

   Copyright (c) 2022 Dan Neumann

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE.
-}


module Parser.Extra exposing
    ( chompOneOrMore
    , chompUntilLookAhead
    , ifProgress
    , justOneChar
    , lookAhead
    , oneOrMore
    , zeroOrMore
    )

import Parser exposing ((|.), (|=), Parser, Step(..), andThen, backtrackable, chompIf, chompWhile, commit, getChompedString, getOffset, loop, map, oneOf, problem, succeed)


justOneChar : Parser String
justOneChar =
    chompIf (always True)
        |> getChompedString


chompOneOrMore : (Char -> Bool) -> Parser ()
chompOneOrMore predicate =
    chompIf predicate
        |. chompWhile predicate


{-| Chomps until a parser applies but unconsumes that parser's progress.

Pass in a predicate that includes everything until the first char of the
lookAhead parser. This is so that we can short-circuit the slow process
of trying the parser and then consuming just one char over and over again.

e.g. the parser passed to chompUntilLookAhead can be arbitrarily slow,
like parsing the rest of the input before failing somewhere far ahead,
yet all we do in that event is consume a single character and apply
the parser again at offset+1.

-}
chompUntilLookAhead : (Char -> Bool) -> Parser a -> Parser ()
chompUntilLookAhead predicate parser =
    loop ""
        (\acc ->
            oneOf
                [ succeed (\s -> Loop (acc ++ s))
                    |= (chompOneOrMore predicate |> getChompedString)
                , succeed (Done acc)
                    |. lookAhead parser
                , succeed (\s -> Loop (acc ++ s))
                    |= justOneChar
                , succeed (Done acc)
                ]
        )
        |> andThen
            (\acc ->
                if String.isEmpty acc then
                    problem "expected some text"

                else
                    succeed ()
            )


zeroOrMore : Parser a -> Parser (List a)
zeroOrMore parser =
    loop []
        (\acc ->
            oneOf
                [ succeed (\val -> Loop (val :: acc))
                    |= parser
                , succeed (Done (List.reverse acc))
                ]
        )


oneOrMore : String -> Parser a -> Parser (List a)
oneOrMore name parser =
    loop []
        (\acc ->
            oneOf
                [ succeed (\val -> Loop (val :: acc))
                    |= parser
                , if List.isEmpty acc then
                    problem ("expecting at least one " ++ name)

                  else
                    succeed (Done (List.reverse acc))
                ]
        )


{-| Create a parser that backtracks on success.
-}
lookAhead : Parser a -> Parser ()
lookAhead parser =
    oneOf
        [ oneOf
            [ parser
                |> backtrackable
                |> andThen (\_ -> commit ())
                |> andThen (\_ -> problem "")
            , succeed
                (parser
                    |> backtrackable
                    |> map (\_ -> ())
                )
            ]
            |> backtrackable
        , succeed (succeed ())
        ]
        |> andThen identity


{-| Loop a parser only if it actually consumes something.

For example, parsers like `spaces` and `chompWhile` will happily
consume 0 input, so when put in a loop the parser will never terminate.

-}
ifProgress : Parser a -> Int -> Parser (Step Int ())
ifProgress parser offset =
    succeed identity
        |. parser
        |= getOffset
        |> map
            (\newOffset ->
                if offset == newOffset then
                    Done ()

                else
                    Loop newOffset
            )
