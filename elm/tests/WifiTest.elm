module WifiTest exposing (suite)

{-| Joining a wifi network again by itself, with the password saved when the user
joined it (Main.reconnect, Main.savePassword).
-}

import Dict
import Effect exposing (Effect)
import Expect
import HostMessage
import Main
import Test exposing (Test, describe, test)
import Wifi


run : List HostMessage.ToElm -> Main.Model -> ( Main.Model, List Effect )
run messages model =
    List.foldl
        (\message ( m, effects ) ->
            Main.persistConfig.update (Main.persistConfig.fromHost (Ok message)) m |> Tuple.mapSecond (\more -> effects ++ more)
        )
        ( model, [] )
        messages


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


scan : HostMessage.ToElm
scan =
    HostMessage.WifiScan
        [ { ssid = "Other", signal = -30, security = Wifi.Wpa }
        , { ssid = "Cafe", signal = -70, security = Wifi.Open }
        , { ssid = "Home", signal = -40, security = Wifi.Wpa }
        ]


status : Wifi.State -> String -> HostMessage.ToElm
status state ssid =
    HostMessage.WifiStatus { state = state, ssid = ssid, ip = "", error = "" }


suite : Test
suite =
    describe "Wifi"
        [ test "while idle, a scan with saved networks joins the strongest of them"
            (\_ ->
                run [ status Wifi.Idle "", scan ] saved
                    |> Tuple.second
                    |> connects
                    |> Expect.equal [ "Home secret" ]
            )
        , test "after a failure, scans don't try again"
            (\_ ->
                run [ status Wifi.Failed "Home", scan ] saved
                    |> Tuple.second
                    |> connects
                    |> Expect.equal []
            )
        , test "while connected, scans don't join anything"
            (\_ ->
                run [ status Wifi.Connected "Cafe", scan ] saved
                    |> Tuple.second
                    |> connects
                    |> Expect.equal []
            )
        , test "without saved networks, nothing is joined"
            (\_ ->
                run [ status Wifi.Idle "", scan ] Main.persistConfig.init
                    |> Tuple.second
                    |> connects
                    |> Expect.equal []
            )
        ]
