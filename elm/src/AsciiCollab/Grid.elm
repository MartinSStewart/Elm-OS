module AsciiCollab.Grid exposing
    ( addChange
    , asciiToCellAndLocalCoord
    , boundsContains
    , boundsContainsBounds
    , cellSize
    , flatten
    , fromChar
    , moveUndoPoint
    , singleton
    , space
    , toChar
    )

{-| ascii-collab's grid (its Grid.elm, GridCell.elm and Bounds.elm), the parts the Elm OS
app uses: the same rules for who wrote what and for undo, so the grid looks like it
does on ascii-collab.app.
-}

import Array exposing (Array)
import AsciiCollab.Types exposing (Ascii(..), AsciiUnit, Bounds(..), Cell(..), CellUnit, Grid(..), GridChangeData, Nonempty(..), UserId(..))
import Coord exposing (Coord)
import Dict exposing (Dict)
import Quantity exposing (Quantity(..))
import SeqSet exposing (SeqSet)
import Sprite


{-| A cell is this many characters across and down.
-}
cellSize : Int
cellSize =
    16


singleton : a -> Nonempty a
singleton a =
    Nonempty a []


fromChar : Char -> Maybe Ascii
fromChar char =
    Sprite.asciiIndex char |> Maybe.map Ascii


toChar : Ascii -> Char
toChar (Ascii index) =
    Sprite.asciiChar index


space : Ascii
space =
    fromChar ' ' |> Maybe.withDefault (Ascii 0)


{-| The cell a character is in, and its place in the cell (left to right, then down).
-}
asciiToCellAndLocalCoord : Coord AsciiUnit -> ( Coord CellUnit, Int )
asciiToCellAndLocalCoord ( Quantity x, Quantity y ) =
    ( ( Quantity (floorDiv x), Quantity (floorDiv y) )
    , modBy cellSize x + modBy cellSize y * cellSize
    )


floorDiv : Int -> Int
floorDiv n =
    (n - modBy cellSize n) // cellSize


boundsContains : Coord unit -> Bounds unit -> Bool
boundsContains ( Quantity x, Quantity y ) (Bounds bounds) =
    let
        ( Quantity minX, Quantity minY ) =
            bounds.min

        ( Quantity maxX, Quantity maxY ) =
            bounds.max
    in
    minX <= x && x <= maxX && minY <= y && y <= maxY


{-| Whether the first bounds are all inside the second.
-}
boundsContainsBounds : Bounds unit -> Bounds unit -> Bool
boundsContainsBounds (Bounds inner) outer =
    boundsContains inner.min outer && boundsContains inner.max outer


addChange : GridChangeData -> Grid -> Grid
addChange change (Grid grid) =
    let
        key =
            Coord.toTuple change.cellPosition

        cell =
            Dict.get key grid |> Maybe.withDefault (Cell { history = [], undoPoint = Dict.empty })
    in
    Grid (Dict.insert key (addLine change.userId change.localPosition change.change cell) grid)


{-| A user's change to a cell. Their changes that were undone go, since this one can't
be redone past them.
-}
addLine : UserId -> Int -> Nonempty Ascii -> Cell -> Cell
addLine ((UserId rawUserId) as userId) position line (Cell cell) =
    let
        userUndoPoint =
            Dict.get rawUserId cell.undoPoint |> Maybe.withDefault 0
    in
    Cell
        { history =
            List.foldr
                (\change ( newHistory, counter ) ->
                    if change.userId == userId then
                        if counter > 0 then
                            ( change :: newHistory, counter - 1 )

                        else
                            ( newHistory, counter )

                    else
                        ( change :: newHistory, counter )
                )
                ( [], userUndoPoint )
                cell.history
                |> Tuple.first
                |> (::) { userId = userId, position = position, line = line }
        , undoPoint = Dict.insert rawUserId (userUndoPoint + 1) cell.undoPoint
        }


moveUndoPoint : UserId -> Dict ( Int, Int ) Int -> Grid -> Grid
moveUndoPoint (UserId rawUserId) undoPoint (Grid grid) =
    Dict.foldl
        (\coord moveAmount newGrid ->
            Dict.update
                coord
                (Maybe.map
                    (\(Cell cell) ->
                        Cell { cell | undoPoint = Dict.update rawUserId (Maybe.map ((+) moveAmount)) cell.undoPoint }
                    )
                )
                newGrid
        )
        grid
        undoPoint
        |> Grid


{-| What a cell shows: each of its characters, and who wrote it (Nothing for a blank
never written). Changes by `hidden` users are left out.
-}
flatten : SeqSet UserId -> Cell -> Array ( Maybe UserId, Ascii )
flatten hidden (Cell cell) =
    List.foldr
        (\{ userId, position, line } state ->
            if SeqSet.member userId hidden then
                state

            else
                let
                    (UserId rawUserId) =
                        userId
                in
                case Dict.get rawUserId state.undoPoint of
                    Just stepsLeft ->
                        if stepsLeft > 0 then
                            { array =
                                nonemptyToList line
                                    |> List.foldl
                                        (\ascii ( position_, array ) ->
                                            ( position_ + 1, Array.set position_ ( Just userId, ascii ) array )
                                        )
                                        ( position, state.array )
                                    |> Tuple.second
                            , undoPoint = Dict.insert rawUserId (stepsLeft - 1) state.undoPoint
                            }

                        else
                            state

                    Nothing ->
                        state
        )
        { array = Array.repeat (cellSize * cellSize) ( Nothing, space ), undoPoint = cell.undoPoint }
        cell.history
        |> .array


nonemptyToList : Nonempty a -> List a
nonemptyToList (Nonempty head rest) =
    head :: rest
