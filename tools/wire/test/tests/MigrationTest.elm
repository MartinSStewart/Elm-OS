module MigrationTest exposing (suite)

{-| A Model saved by version 1 of the fixture's types (tools/wire/test/src/Evergreen)
is read by the current build through the migration to version 2.
-}

import App
import Array
import Dict
import ElmOs
import Evergreen.V1.App
import Evergreen.V1.Sub.Things
import Expect
import Json.Decode as D
import Json.Encode as E
import Persist
import Quantity
import Set
import Test exposing (Test, describe, test)
import Time


v1Sample : Evergreen.V1.App.Model
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
    , kind = Evergreen.V1.App.Gamma "abc"
    , kinds = [ Evergreen.V1.App.Alpha, Evergreen.V1.App.Gamma "x" ]
    , kindDict = Dict.fromList [ ( "a", Just (Evergreen.V1.App.Beta 4) ), ( "b", Nothing ) ]
    }


{-| A snapshot as a build of version 1 would have written it (in the format before the
host logged messages).
-}
v1Snapshot : Maybe String
v1Snapshot =
    Just
        (Persist.frame
                (E.encode 0
                    (E.list identity
                        [ E.string "elmos-persist-4"
                        , E.int 1
                        , E.string (Persist.hash (Maybe.withDefault "" (ElmOs.codecs.versionShape 1)))
                        , E.string "an older Msg type"
                        , E.int 4
                        , Evergreen.V1.App.w3_encode_Model v1Sample
                        , E.list E.string []
                        ]
                    )
                )
        )


suite : Test
suite =
    describe "migrations"
        [ test "the newest version is 2" (\_ -> ElmOs.codecs.version |> Expect.equal 2)
        , test "version 2's shape is the current one" (\_ -> ElmOs.codecs.versionShape 2 |> Expect.equal (Just ElmOs.codecs.modelShape))
        , test "a version 1 Model migrates"
            (\_ ->
                case ElmOs.codecs.migrate 1 (Evergreen.V1.App.w3_encode_Model v1Sample) |> Maybe.map (D.decodeValue ElmOs.codecs.modelDecoder) of
                    Just (Ok m) ->
                        ( ( m.int, m.order, m.kind ), ( m.kinds, Dict.toList m.kindDict, Quantity.unwrap m.quantity ) ) |> Expect.equal ( ( 5, GT, App.Beta 3 ), ( [ App.Alpha, App.Beta 1 ], [ ( "a", Just (App.Beta 4) ), ( "b", Nothing ) ], 2.5 ) )

                    _ ->
                        Expect.fail "didn't migrate"
            )
        , test "restoring a version 1 snapshot migrates it"
            (\_ ->
                let
                    restored =
                        Persist.restore App.config ElmOs.codecs v1Snapshot
                in
                Expect.all
                    [ \r -> r.model.kind |> Expect.equal (App.Beta 3)

                    -- Its Msg log is gone: the host's log starts from 1.
                    , \r -> r.seq |> Expect.equal (Just 0)
                    , \r -> r.unreadable |> Expect.equal Nothing
                    , \r -> r.notes |> Expect.equal [ "migrated the Model from version 1 to 2" ]
                    ]
                    restored
            )
        , test "a snapshot in an older format is kept, and the Model starts afresh"
            (\_ ->
                let
                    old =
                        Persist.frame "[\"0123abcd\",3,[]]"

                    restored =
                        Persist.restore App.config ElmOs.codecs (Just old)
                in
                ( restored.unreadable, restored.seq ) |> Expect.equal ( Just old, Nothing )
            )
        , test "a snapshot from a newer version is kept, and the Model starts afresh"
            (\_ ->
                let
                    newer =
                        Persist.frame "[\"elmos-persist-4\",3,\"00000000\",\"00000000\",0,[],[]]"
                in
                (Persist.restore App.config ElmOs.codecs (Just newer)).notes
                    |> Expect.equal [ "the snapshot is of version 3 of the Model, newer than this build's 2; starting afresh, and keeping it as snapshot-unreadable" ]
            )
        ]
