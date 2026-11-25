module MigrationTest exposing (suite)

{-| A Model saved by version 1 of the fixture's types (tools/wire/test/src/Evergreen)
is read by the current build through the migration to version 2.
-}

import Array
import Bytes exposing (Bytes)
import Bytes.Encode as BE
import Dict
import ElmOs
import Evergreen.V1.Sub.Things
import Evergreen.V1.WireApp
import Expect
import Json.Encode as E
import Persist
import Quantity
import SeqDict
import SeqSet
import Set
import Test exposing (Test, describe, test)
import Time
import Wire
import WireApp


v1Sample : Evergreen.V1.WireApp.Model
v1Sample =
    { int = 5
    , float = 1.5
    , string = "s"
    , bool = True
    , char = 'c'
    , unit = ()
    , pair = ( 1, "one" )
    , triple = ( False, 2, 'z' )
    , list = [ Just 1 ]
    , nested = Nothing
    , array = Array.fromList [ "a" ]
    , set = Set.fromList [ 1 ]
    , dict = Dict.empty
    , result = Ok 3
    , quantity = Quantity.unsafe 2.5
    , time = Time.millisToPosix 0
    , json = E.null
    , record = { a = 1, inner = { b = "b" } }
    , tree = Evergreen.V1.Sub.Things.Node 1 [ Evergreen.V1.Sub.Things.Leaf ]
    , opaque = Evergreen.V1.Sub.Things.Opaque 7 { value = 7, extra = Nothing } (Evergreen.V1.Sub.Things.Chain { value = 7, next = Nothing })
    , box = { value = "b", extra = Nothing }
    , labelled = ( Quantity.unsafe 1, Quantity.unsafe 2 )
    , removed = 9
    , kind = Evergreen.V1.WireApp.Gamma "abc"
    , kinds = [ Evergreen.V1.WireApp.Alpha, Evergreen.V1.WireApp.Gamma "x" ]
    , kindDict = Dict.fromList [ ( "a", Just (Evergreen.V1.WireApp.Beta 4) ), ( "b", Nothing ) ]
    , seqSet = SeqSet.fromList [ 2, 1 ]
    , seqDict = SeqDict.empty
    , kindSeqDict = SeqDict.fromList [ ( "z", Just (Evergreen.V1.WireApp.Gamma "y") ), ( "a", Nothing ) ]
    }


{-| A snapshot as a build of version 1 would have written it.
-}
v1Snapshot : Maybe Bytes
v1Snapshot =
    Just
        (Persist.frame
            (Wire.toBytes
                (BE.sequence
                    [ Wire.encodeString "elmos-persist-7"
                    , Wire.encodeSnapshotInt 1
                    , Wire.encodeString (Persist.hash (Maybe.withDefault "" (ElmOs.codecs.versionShape 1)))
                    , Wire.encodeSnapshotInt 4
                    , Wire.encodeBytes (Wire.toBytes (Evergreen.V1.WireApp.w3_encode_Model v1Sample))
                    , Wire.encodeList Wire.encodeString []
                    ]
                )
            )
        )


text : String -> Bytes
text string =
    BE.encode (BE.string string)


suite : Test
suite =
    describe "migrations"
        [ test "the newest version is 2" (\_ -> ElmOs.codecs.version |> Expect.equal 2)
        , test "version 2's shape is the current one" (\_ -> ElmOs.codecs.versionShape 2 |> Expect.equal (Just ElmOs.codecs.modelShape))
        , test "a version 1 Model migrates"
            (\_ ->
                case ElmOs.codecs.migrate 1 (Wire.toBytes (Evergreen.V1.WireApp.w3_encode_Model v1Sample)) |> Maybe.andThen (Wire.fromBytes ElmOs.codecs.modelDecoder) of
                    Just m ->
                        Expect.all
                            [ \_ -> ( ( m.int, m.order, m.kind ), ( m.kinds, Dict.toList m.kindDict, Quantity.unwrap m.quantity ) ) |> Expect.equal ( ( 5, GT, WireApp.Beta 3 ), ( [ WireApp.Alpha, WireApp.Beta 1 ], [ ( "a", Just (WireApp.Beta 4) ), ( "b", Nothing ) ], 2.5 ) )
                            , \_ -> ( SeqSet.toList m.seqSet, SeqDict.toList m.kindSeqDict ) |> Expect.equal ( [ 2, 1 ], [ ( "z", Just (WireApp.Beta 1) ), ( "a", Nothing ) ] )
                            ]
                            ()

                    _ ->
                        Expect.fail "didn't migrate"
            )
        , test "restoring a version 1 snapshot migrates it"
            (\_ ->
                let
                    restored =
                        Persist.restore WireApp.config ElmOs.codecs v1Snapshot
                in
                Expect.all
                    [ \r -> r.model.kind |> Expect.equal (WireApp.Beta 3)

                    -- The host's log carries on from the snapshot's place in it.
                    , \r -> r.seq |> Expect.equal (Just 4)
                    , \r -> r.unreadable |> Expect.equal Nothing
                    , \r -> r.notes |> Expect.equal [ "migrated the Model from version 1 to 2" ]
                    ]
                    restored
            )
        , test "a snapshot in an older format is kept, and the Model starts afresh"
            (\_ ->
                let
                    old =
                        Persist.frame (text "[\"0123abcd\",3,[]]")

                    restored =
                        Persist.restore WireApp.config ElmOs.codecs (Just old)
                in
                ( restored.unreadable, restored.seq ) |> Expect.equal ( Just old, Nothing )
            )
        , test "a snapshot from a newer version is kept, and the Model starts afresh"
            (\_ ->
                let
                    newer =
                        Persist.frame
                            (Wire.toBytes
                                (BE.sequence
                                    [ Wire.encodeString "elmos-persist-7"
                                    , Wire.encodeSnapshotInt 3
                                    , Wire.encodeString "00000000"
                                    , Wire.encodeSnapshotInt 0
                                    , Wire.encodeBytes (text "")
                                    , Wire.encodeList Wire.encodeString []
                                    ]
                                )
                            )
                in
                (Persist.restore WireApp.config ElmOs.codecs (Just newer)).notes
                    |> Expect.equal [ "the snapshot is of version 3 of the Model, newer than this build's 2; starting afresh, and keeping it as snapshot-unreadable" ]
            )
        ]
