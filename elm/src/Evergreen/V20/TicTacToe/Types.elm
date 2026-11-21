module Evergreen.V20.TicTacToe.Types exposing (..)

{-| The ids of the noughts and crosses window's elements: here rather than in TicTacToe.elm, as UiId.elm can't import
a module that imports it.
-}


type UiId
    = Square Int
    | NewGameButton
    | CloseButton
    | Panel
