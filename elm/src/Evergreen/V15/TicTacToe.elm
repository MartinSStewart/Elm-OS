module Evergreen.V15.TicTacToe exposing (..)

{-| Noughts and crosses for two people on one computer. X starts. Click a square to
place your mark there, and click New game to clear the board.

The board is a list of nine squares, top row first, each empty or holding a mark.

-}

import Evergreen.V15.Color
import Evergreen.V15.Coord exposing (Coord)
import Evergreen.V15.Sprite exposing (Font(..), FontSize(..), Style(..))
import Evergreen.V15.TicTacToe.Types
import Evergreen.V15.Ui exposing (Element)
import Evergreen.V15.UiId exposing (UiId(..))
import Evergreen.V15.Units exposing (UiPixels)


type Mark
    = X
    | O


type alias Model =
    { squares : List (Maybe Mark)
    , next : Mark
    }


-- VIEW
