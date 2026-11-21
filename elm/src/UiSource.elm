module UiSource exposing (at1, at2, at3)

{-| What tools/wire (tools/wire/src/Source.elm) puts in place of each Ui function that
makes an element, so that the element knows where it was made, for the outline mode's
inspector (Ctrl+Shift+Q, Ui.inspect). On line 12 of Main,

    Ui.text "Hello"

becomes

    UiSource.at1 "Main" 12 "text" Ui.text "Hello"

on the same line, so line numbers stay as they are. `at2` and `at3` are the same for
functions of two and three arguments. Nothing in elm/src calls them.

-}

import Ui exposing (Element)


at1 : String -> Int -> String -> (a -> Element id) -> a -> Element id
at1 module_ line function f a =
    Ui.sourced { module_ = module_, line = line, function = function } (f a)


at2 : String -> Int -> String -> (a -> b -> Element id) -> a -> b -> Element id
at2 module_ line function f a b =
    Ui.sourced { module_ = module_, line = line, function = function } (f a b)


at3 : String -> Int -> String -> (a -> b -> c -> Element id) -> a -> b -> c -> Element id
at3 module_ line function f a b c =
    Ui.sourced { module_ = module_, line = line, function = function } (f a b c)
