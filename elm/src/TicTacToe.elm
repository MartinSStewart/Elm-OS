module TicTacToe exposing
    ( Mark(..)
    , Model
    , Status(..)
    , init
    , press
    , status
    , view
    )

{-| Noughts and crosses for two people on one computer. X starts. Click a square to
place your mark there, and click New game to clear the board.

The board is a list of nine squares, top row first, each empty or holding a mark.

-}

import Color
import Coord exposing (Coord)
import Sprite exposing (Font(..), FontSize(..), Style(..))
import TicTacToe.Types
import Ui exposing (Element)
import UiId exposing (UiId(..))
import Units exposing (UiPixels)


type Mark
    = X
    | O


type alias Model =
    { squares : List (Maybe Mark)
    , next : Mark
    }


type Status
    = Playing
    | Won Mark (List Int)
    | Draw


init : Model
init =
    { squares = List.repeat 9 Nothing
    , next = X
    }


{-| The squares of each line of three: rows, columns, then diagonals.
-}
lines : List (List Int)
lines =
    [ [ 0, 1, 2 ]
    , [ 3, 4, 5 ]
    , [ 6, 7, 8 ]
    , [ 0, 3, 6 ]
    , [ 1, 4, 7 ]
    , [ 2, 5, 8 ]
    , [ 0, 4, 8 ]
    , [ 2, 4, 6 ]
    ]


{-| Who has won, or whether the board is full, or whether the game goes on.
-}
status : Model -> Status
status model =
    case List.filterMap (winOf model) lines of
        ( mark, squares ) :: _ ->
            Won mark squares

        [] ->
            if List.all (\square -> square /= Nothing) model.squares then
                Draw

            else
                Playing


{-| The mark and the squares of a line that is all one mark, if it is.
-}
winOf : Model -> List Int -> Maybe ( Mark, List Int )
winOf model line =
    case List.filterMap (\i -> squareAt i model) line of
        [ a, b, c ] ->
            if a == b && b == c then
                Just ( a, line )

            else
                Nothing

        _ ->
            Nothing


squareAt : Int -> Model -> Maybe Mark
squareAt i model =
    List.drop i model.squares
        |> List.head
        |> Maybe.andThen identity


{-| Place the next mark on square `i`, if the game goes on and the square is empty.
-}
press : Int -> Model -> Model
press i model =
    case status model of
        Playing ->
            case List.drop i model.squares |> List.head of
                Just Nothing ->
                    { squares =
                        List.indexedMap
                            (\j square ->
                                if j == i then
                                    Just model.next

                                else
                                    square
                            )
                            model.squares
                    , next = other model.next
                    }

                Just (Just _) ->
                    model

                Nothing ->
                    model

        Won _ _ ->
            model

        Draw ->
            model


other : Mark -> Mark
other mark =
    case mark of
        X ->
            O

        O ->
            X



-- VIEW


spacing : Int
spacing =
    4


squareSize : Coord UiPixels
squareSize =
    Coord.xy 56 56


{-| The width of the board: three squares and the gaps between them.
-}
width : Int
width =
    3 * Coord.xRaw squareSize + 2 * spacing


sans : Font
sans =
    Sans Regular


{-| The game's window: its title, what to do next, the board and a button to start again.
-}
view : Model -> Element UiId
view model =
    let
        title =
            Ui.leftAndRight (Units.uiPixels width)
                (Ui.text "Tic Tac Toe")
                (Ui.button { id = TicTacToe TicTacToe.Types.CloseButton, padding = Ui.paddingXY 6 0 } (Ui.text "×"))

        board =
            Ui.column spacing (List.map (boardRow model) [ [ 0, 1, 2 ], [ 3, 4, 5 ], [ 6, 7, 8 ] ])

        newGame =
            Ui.button { id = TicTacToe TicTacToe.Types.NewGameButton, padding = Ui.paddingXY 8 3 } (Ui.text "New game")
    in
    Ui.elWithId
        (TicTacToe TicTacToe.Types.Panel)
        { padding = Ui.paddingXY 8 8
        , borderAndFill = Ui.defaultElBorderAndFill
        }
        (Ui.column spacing [ title, Ui.text (message model), board, newGame ])


message : Model -> String
message model =
    case status model of
        Playing ->
            markName model.next ++ " to play"

        Won mark _ ->
            markName mark ++ " wins!"

        Draw ->
            "A draw"


markName : Mark -> String
markName mark =
    case mark of
        X ->
            "X"

        O ->
            "O"


boardRow : Model -> List Int -> Element UiId
boardRow model row =
    Ui.row spacing (List.map (squareView model) row)


squareView : Model -> Int -> Element UiId
squareView model i =
    let
        label =
            case squareAt i model of
                Just mark ->
                    markName mark

                Nothing ->
                    ""

        -- The squares of the winning line stay lit.
        isWinning =
            case status model of
                Won _ squares ->
                    List.member i squares

                Playing ->
                    False

                Draw ->
                    False
    in
    Ui.selectableButton { id = TicTacToe (TicTacToe.Types.Square i), padding = Ui.noPadding }
        isWinning
        (Ui.center { size = squareSize } (Ui.customText Big [ { text = label, color = Color.textColor, font = sans, decorations = [] } ]))
