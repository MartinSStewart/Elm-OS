module WifiTest exposing (suite)

{-| Joining a wifi network again by itself, with the password saved when the user
joined it (Network.reconnect, Network.gotStatus).
-}

import Effect exposing (Effect)
import Expect
import HostMessage
import Main
import Network
import Network.Types
import Network.Wpa2Password as Wpa2Password
import SeqDict
import Test exposing (Test)
import Unsafe


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
                    Just
                        (Network.Types.ssidToString ssid
                            ++ " "
                            ++ (case password of
                                    Just password2 ->
                                        Wpa2Password.toString password2

                                    Nothing ->
                                        ""
                               )
                        )

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

        network : Network.Network
        network =
            init.network
    in
    { init | network = { network | savedWifiPasswords = SeqDict.fromList [ ( Network.Types.stringToSsid "Home", Unsafe.wpa2Password "password" ) ] } }


scan : HostMessage.ToElm
scan =
    HostMessage.WifiScan
        [ { ssid = Network.Types.stringToSsid "Other", signal = -30, security = Network.Wpa }
        , { ssid = Network.Types.stringToSsid "Cafe", signal = -70, security = Network.Open }
        , { ssid = Network.Types.stringToSsid "Home", signal = -40, security = Network.Wpa }
        ]


status : Network.WifiState -> String -> HostMessage.ToElm
status state ssid =
    HostMessage.WifiStatus { state = state, ssid = Network.Types.stringToSsid ssid, ip = Nothing, error = "" }


suite : Test
suite =
    Test.describe "Wifi"
        [ Test.test "while idle, a scan with saved networks joins the strongest of them"
            (\_ ->
                run [ status Network.Idle "", scan ] saved
                    |> Tuple.second
                    |> connects
                    |> Expect.equal [ "Home password" ]
            )
        , Test.test "after a failure, scans don't try again"
            (\_ ->
                run [ status Network.Failed "Home", scan ] saved
                    |> Tuple.second
                    |> connects
                    |> Expect.equal []
            )
        , Test.test "while connected, scans don't join anything"
            (\_ ->
                run [ status Network.Connected "Cafe", scan ] saved
                    |> Tuple.second
                    |> connects
                    |> Expect.equal []
            )
        , Test.test "without saved networks, nothing is joined"
            (\_ ->
                run [ status Network.Idle "", scan ] Main.persistConfig.init
                    |> Tuple.second
                    |> connects
                    |> Expect.equal []
            )
        ]
