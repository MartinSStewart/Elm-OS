module AsciiCollab.LocalGrid exposing
    ( LocalGrid
    , LocalModel
    , fromBackend
    , init
    , localGrid
    , update
    )

{-| ascii-collab's LocalModel and LocalGrid: the grid as the server last said it was,
and the changes made here that the server hasn't sent back yet, applied on top. When
the server sends a change back it is dropped from the local ones, so each counts once.
-}

import AsciiCollab.Grid as Grid
import AsciiCollab.Types exposing (Bounds, CellUnit, Change(..), ClientChange(..), Grid(..), LoadingData_, LocalChange(..), Nonempty(..), ServerChange(..), UserId)
import Coord
import Dict exposing (Dict)
import SeqSet exposing (SeqSet)


type alias LocalGrid =
    { grid : Grid
    , undoHistory : List (Dict ( Int, Int ) Int)
    , redoHistory : List (Dict ( Int, Int ) Int)
    , user : UserId
    , hiddenUsers : SeqSet UserId
    , adminHiddenUsers : SeqSet UserId
    , viewBounds : Bounds CellUnit
    , undoCurrent : Dict ( Int, Int ) Int
    }


{-| `model` is the server's grid; `localModel` is that with `localMsgs` applied.
-}
type alias LocalModel =
    { localMsgs : List Change
    , localModel : LocalGrid
    , model : LocalGrid
    }


init : LoadingData_ -> LocalModel
init data =
    let
        grid =
            { grid = data.grid
            , undoHistory = data.undoHistory
            , redoHistory = data.redoHistory
            , user = data.user
            , hiddenUsers = data.hiddenUsers
            , adminHiddenUsers = data.adminHiddenUsers
            , viewBounds = data.viewBounds
            , undoCurrent = data.undoCurrent
            }
    in
    { localMsgs = [], localModel = grid, model = grid }


localGrid : LocalModel -> LocalGrid
localGrid model =
    model.localModel


{-| A change made here.
-}
update : Change -> LocalModel -> LocalModel
update change model =
    { model
        | localMsgs = model.localMsgs ++ [ change ]
        , localModel = updateGrid change model.localModel
    }


{-| Changes from the server, which may include ones made here coming back.
-}
fromBackend : Nonempty Change -> LocalModel -> LocalModel
fromBackend (Nonempty first rest) model =
    let
        changes =
            first :: rest

        newModel =
            List.foldl updateGrid model.model changes

        newLocalMsgs =
            List.foldl
                (\serverMsg localMsgs ->
                    List.foldl
                        (\localMsg ( newList, isDone ) ->
                            if isDone then
                                ( localMsg :: newList, True )

                            else if msgEqual localMsg serverMsg then
                                ( newList, True )

                            else
                                ( localMsg :: newList, False )
                        )
                        ( [], False )
                        localMsgs
                        |> Tuple.first
                        |> List.reverse
                )
                model.localMsgs
                changes
    in
    { localMsgs = newLocalMsgs
    , localModel = List.foldl updateGrid newModel newLocalMsgs
    , model = newModel
    }


msgEqual : Change -> Change -> Bool
msgEqual localMsg serverMsg =
    case localMsg of
        ClientChange (ViewBoundsChange localBounds _) ->
            case serverMsg of
                ClientChange (ViewBoundsChange serverBounds _) ->
                    localBounds == serverBounds

                LocalChange _ ->
                    False

                ServerChange _ ->
                    False

        LocalChange _ ->
            localMsg == serverMsg

        ServerChange _ ->
            localMsg == serverMsg


incrementUndoCurrent : { a | cellPosition : Coord.Coord units } -> Dict ( Int, Int ) Int -> Dict ( Int, Int ) Int
incrementUndoCurrent gridChange undoCurrent =
    Dict.update
        (Coord.toTuple gridChange.cellPosition)
        (\count -> Just (Maybe.withDefault 0 count + 1))
        undoCurrent


toggleSet : a -> SeqSet a -> SeqSet a
toggleSet value set =
    if SeqSet.member value set then
        SeqSet.remove value set

    else
        SeqSet.insert value set


updateGrid : Change -> LocalGrid -> LocalGrid
updateGrid msg model =
    case msg of
        LocalChange (LocalGridChange gridChange) ->
            { model
                | redoHistory = []
                , grid =
                    if Grid.boundsContains gridChange.cellPosition model.viewBounds then
                        Grid.addChange
                            { cellPosition = gridChange.cellPosition
                            , localPosition = gridChange.localPosition
                            , change = gridChange.change
                            , userId = model.user
                            }
                            model.grid

                    else
                        model.grid
                , undoCurrent = incrementUndoCurrent gridChange model.undoCurrent
            }

        LocalChange LocalRedo ->
            case model.redoHistory of
                head :: rest ->
                    { model
                        | undoHistory = model.undoCurrent :: model.undoHistory
                        , redoHistory = rest
                        , undoCurrent = head
                        , grid = Grid.moveUndoPoint model.user head model.grid
                    }

                [] ->
                    model

        LocalChange LocalUndo ->
            case model.undoHistory of
                head :: rest ->
                    { model
                        | undoHistory = rest
                        , redoHistory = model.undoCurrent :: model.redoHistory
                        , undoCurrent = head
                        , grid = Grid.moveUndoPoint model.user (Dict.map (\_ a -> -a) model.undoCurrent) model.grid
                    }

                [] ->
                    model

        LocalChange LocalAddUndo ->
            { model
                | redoHistory = []
                , undoHistory = model.undoCurrent :: model.undoHistory
                , undoCurrent = Dict.empty
            }

        LocalChange (LocalHideUser userId _) ->
            { model
                | hiddenUsers =
                    if userId == model.user then
                        model.hiddenUsers

                    else
                        SeqSet.insert userId model.hiddenUsers
            }

        LocalChange (LocalUnhideUser userId) ->
            { model
                | hiddenUsers =
                    if userId == model.user then
                        model.hiddenUsers

                    else
                        SeqSet.remove userId model.hiddenUsers
            }

        LocalChange (LocalToggleUserVisibilityForAll userId) ->
            { model | adminHiddenUsers = toggleSet userId model.adminHiddenUsers }

        ServerChange (ServerGridChange gridChange) ->
            if Grid.boundsContains gridChange.cellPosition model.viewBounds then
                { model | grid = Grid.addChange gridChange model.grid }

            else
                model

        ServerChange (ServerUndoPoint undoPoint) ->
            { model | grid = Grid.moveUndoPoint undoPoint.userId undoPoint.undoPoints model.grid }

        ServerChange (ServerToggleUserVisibilityForAll userId) ->
            { model | adminHiddenUsers = toggleSet userId model.adminHiddenUsers }

        ClientChange (ViewBoundsChange bounds newCells) ->
            let
                (Grid cells) =
                    model.grid
            in
            { model
                | grid =
                    cells
                        |> Dict.filter (\coord _ -> Grid.boundsContains (Coord.xy (Tuple.first coord) (Tuple.second coord)) bounds)
                        |> Dict.union (List.map (Tuple.mapFirst Coord.toTuple) newCells |> Dict.fromList)
                        |> Grid
                , viewBounds = bounds
            }
