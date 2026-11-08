module WifiTest exposing (suite)

{-| Joining a wifi network again by itself, with the password saved when the user
joined it (Main.reconnect, Main.savePassword).
-}

import Dict
import Effect exposing (Effect)
import Expect
import Json.Decode as D
import Json.Encode as E
import Main
import Test exposing (Test, describe, test)


run : List String -> Main.Model -> ( Main.Model, List Effect )
run messages model =
    List.foldl
        (\json ( m, effects ) ->
            Main.persistConfig.update (hostMsg json) m |> Tuple.mapSecond (\more -> effects ++ more)
        )
        ( model, [] )
        messages


hostMsg : String -> Main.Msg
hostMsg json =
    D.decodeString D.value json
        |> Result.map Main.persistConfig.fromHost
        |> Result.withDefault (Main.persistConfig.fromHost E.null)


connects : List Effect -> List String
connects effects =
    List.filterMap
        (\effect ->
            case effect of
                Effect.WifiConnect { ssid, password } ->
                    Just (ssid ++ " " ++ password)

                _ ->
                    Nothing
        )
        effects


saved : Main.Model
saved =
    let
        init : Main.Model
        init =
            Main.persistConfig.init
    in
    { init | savedWifiPasswords = Dict.fromList [ ( "Home", "secret" ), ( "Cafe", "" ) ] }


scan : String
scan =
    """{"t":"wifiScan","networks":[{"ssid":"Other","signal":-30,"security":"wpa"},{"ssid":"Cafe","signal":-70,"security":"open"},{"ssid":"Home","signal":-40,"security":"wpa"}]}"""


suite : Test
suite =
    describe "Wifi"
        [ test "while idle, a scan with saved networks joins the strongest of them"
            (\_ ->
                run [ """{"t":"wifiStatus","state":"idle","ssid":"","ip":"","error":""}""", scan ] saved
                    |> Tuple.second
                    |> connects
                    |> Expect.equal [ "Home secret" ]
            )
        , test "after a failure, scans don't try again"
            (\_ ->
                run [ """{"t":"wifiStatus","state":"failed","ssid":"Home","ip":"","error":"wrong password"}""", scan ] saved
                    |> Tuple.second
                    |> connects
                    |> Expect.equal []
            )
        , test "while connected, scans don't join anything"
            (\_ ->
                run [ """{"t":"wifiStatus","state":"connected","ssid":"Cafe","ip":"10.0.0.2","error":""}""", scan ] saved
                    |> Tuple.second
                    |> connects
                    |> Expect.equal []
            )
        , test "without saved networks, nothing is joined"
            (\_ ->
                run [ """{"t":"wifiStatus","state":"idle","ssid":"","ip":"","error":""}""", scan ] Main.persistConfig.init
                    |> Tuple.second
                    |> connects
                    |> Expect.equal []
            )
        ]
