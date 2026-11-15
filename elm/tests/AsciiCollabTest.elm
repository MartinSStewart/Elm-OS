module AsciiCollabTest exposing (suite)

{-| ascii-collab's messages in Lamdera's bytes (WireCodecs, as tools/wire writes it),
and its grid's rules.
-}

import Array
import AsciiCollab.Grid as Grid
import AsciiCollab.LocalGrid as LocalGrid
import AsciiCollab.Types exposing (Ascii(..), Bounds(..), Change(..), Grid(..), LocalChange(..), Nonempty(..), ServerChange(..), ToBackend(..), ToFrontend(..), UserId(..))
import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Bytes.Encode as BE
import Coord
import Dict
import Expect
import SeqSet
import Test exposing (Test, describe, test)
import Wire
import WireCodecs


bytesToList : Bytes -> List Int
bytesToList bytes =
    BD.decode
        (BD.loop ( Bytes.width bytes, [] )
            (\( left, acc ) ->
                if left <= 0 then
                    BD.succeed (BD.Done (List.reverse acc))

                else
                    BD.map (\b -> BD.Loop ( left - 1, b :: acc )) BD.unsignedInt8
            )
        )
        bytes
        |> Maybe.withDefault []


listToBytes : List Int -> Bytes
listToBytes list =
    BE.encode (BE.sequence (List.map BE.unsignedInt8 list))


toBackend : ToBackend -> List Int
toBackend message =
    Wire.toBytes (WireCodecs.encodeToBackend message) |> bytesToList


bounds : ( Int, Int ) -> ( Int, Int ) -> Bounds unit
bounds ( minX, minY ) ( maxX, maxY ) =
    Bounds { min = Coord.xy minX minY, max = Coord.xy maxX maxY }


loadingData : AsciiCollab.Types.LoadingData_
loadingData =
    { user = UserId 7
    , grid = Grid Dict.empty
    , hiddenUsers = SeqSet.empty
    , adminHiddenUsers = SeqSet.empty
    , undoHistory = []
    , redoHistory = []
    , undoCurrent = Dict.empty
    , viewBounds = bounds ( -1, -1 ) ( 1, 1 )
    }


{-| What a cell shows, as text.
-}
cellText : LocalGrid.LocalModel -> ( Int, Int ) -> String
cellText local key =
    let
        (Grid cells) =
            (LocalGrid.localGrid local).grid
    in
    case Dict.get key cells of
        Just cell ->
            Grid.flatten SeqSet.empty cell |> Array.toList |> List.map (\( _, ascii ) -> Grid.toChar ascii) |> String.fromList |> String.trimRight

        Nothing ->
            ""


typed : Char -> Int -> LocalChange
typed char localPosition =
    LocalGridChange
        { cellPosition = Coord.xy 0 0
        , localPosition = localPosition
        , change = Grid.singleton (Grid.fromChar char |> Maybe.withDefault Grid.space)
        }


suite : Test
suite =
    describe "ascii-collab"
        [ test "ConnectToBackend is the bytes ascii-collab.app answered (tag 1, Bounds' fields max then min, Quantities tagged 0)"
            (\_ ->
                toBackend (ConnectToBackend (bounds ( 0, 0 ) ( 3, 3 )) Nothing)
                    |> Expect.equal [ 1, 0, 0, 6, 0, 6, 0, 0, 0, 0, 0 ]
            )
        , test "GridChange: tag 3, then a Nonempty of LocalGridChange (tag 1 of LocalChange), fields cellPosition, change, localPosition"
            (\_ ->
                toBackend
                    (GridChange
                        (Nonempty
                            (LocalGridChange { cellPosition = Coord.xy -1 2, localPosition = 17, change = Nonempty (Ascii 36) [] })
                            [ LocalAddUndo ]
                        )
                    )
                    |> Expect.equal [ 3, 0, 1, 0, 1, 0, 4, 0, 0, 72, 0, 34, 2, 0 ]
            )
        , test "a ToFrontend reads"
            (\_ ->
                -- ChangeBroadcast (tag 2): one ServerChange (tag 2 of Change) ServerToggleUserVisibilityForAll (tag 1) (UserId 5)
                Wire.fromBytes WireCodecs.decodeToFrontend (listToBytes [ 2, 0, 2, 1, 0, 10, 0 ])
                    |> Expect.equal (Just (ChangeBroadcast (Nonempty (ServerChange (ServerToggleUserVisibilityForAll (UserId 5))) [])))
            )
        , test "characters left of and above 0 are in cell -1"
            (\_ ->
                [ Coord.xy -1 -1, Coord.xy -16 0, Coord.xy -17 15, Coord.xy 16 33 ]
                    |> List.map (\coord -> Grid.asciiToCellAndLocalCoord coord |> Tuple.mapFirst Coord.toTuple)
                    |> Expect.equal [ ( ( -1, -1 ), 255 ), ( ( -1, 0 ), 0 ), ( ( -2, 0 ), 255 ), ( ( 1, 2 ), 16 ) ]
            )
        , test "the grid's characters are Elm OS's pixel font's"
            (\_ -> List.map (\char -> Grid.fromChar char |> Maybe.map Grid.toChar) [ 'a', '║', '█', ' ', '€' ] |> Expect.equal [ Just 'a', Just '║', Just '█', Just ' ', Nothing ])
        , test "typing shows at once, and the server sending it back doesn't apply it twice"
            (\_ ->
                let
                    local =
                        LocalGrid.init loadingData |> LocalGrid.update (LocalChange (typed 'h' 0)) |> LocalGrid.update (LocalChange (typed 'i' 1))

                    confirmed =
                        LocalGrid.fromBackend (Nonempty (LocalChange (typed 'h' 0)) []) local
                in
                ( cellText local ( 0, 0 ), cellText confirmed ( 0, 0 ), List.length confirmed.localMsgs )
                    |> Expect.equal ( "hi", "hi", 1 )
            )
        , test "undo takes back the changes since the last undo point, and redo puts them back"
            (\_ ->
                let
                    local =
                        LocalGrid.init loadingData
                            |> LocalGrid.update (LocalChange (typed 'a' 0))
                            |> LocalGrid.update (LocalChange LocalAddUndo)
                            |> LocalGrid.update (LocalChange (typed 'b' 1))

                    undone =
                        LocalGrid.update (LocalChange LocalUndo) local
                in
                ( cellText local ( 0, 0 ), cellText undone ( 0, 0 ), cellText (LocalGrid.update (LocalChange LocalRedo) undone) ( 0, 0 ) )
                    |> Expect.equal ( "ab", "a", "ab" )
            )
        , test "someone else's change shows"
            (\_ ->
                LocalGrid.init loadingData
                    |> LocalGrid.fromBackend
                        (Nonempty
                            (ServerChange
                                (ServerGridChange
                                    { cellPosition = Coord.xy 0 0, localPosition = 2, change = Nonempty (Ascii (Grid.fromChar 'x' |> Maybe.map (\(Ascii i) -> i) |> Maybe.withDefault 0)) [], userId = UserId 3 }
                                )
                            )
                            []
                        )
                    |> (\local -> cellText local ( 0, 0 ))
                    |> Expect.equal "  x"
            )
        ]
