module HostMessage exposing (HttpFailure(..), ToElm(..), decode, decodeNumbered)

{-| What the host sends on `fromHost` (Effect.elm): Elm's copy of host/protocol's
`ToElm`, one variant for each of its variants, in the same order, and `decode`, which
reads postcard (Postcard.elm) as the host writes it. ProtocolTest checks it against
the host's bytes for every example in host/protocol/examples.json.

Persist.elm takes the data disk's messages and its own files; the rest go to the
program (Main.persistConfig.fromHost).

-}

import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Postcard as P
import Wifi
import Wired


type ToElm
    = -- First, once: the screen's size in pixels.
      Screen Int Int
      -- Draw a frame now: the host's monotonic clock, in milliseconds.
    | Frame Float
    | Mouse Int Int
    | Button Int Bool
      -- Wheel clicks, positive is up.
    | Wheel Int
      -- A key went down or up (evdev's code), and whether it's the keyboard's autorepeat.
    | Key Int Bool Bool
    | Renderer { gpu : Bool, name : String, hardwareCursor : Bool }
    | System { kernel : String, cpu : String, commit : String }
      -- Once, when the first frame is on screen: milliseconds since the kernel started.
    | Boot { initMs : Float, elmMs : Float, frameMs : Float }
      -- For the debug overlay. -1 for a time the host doesn't know.
    | Stats
        { cores : Int
        , cpu : Float
        , cpuElm : Float
        , cpuHost : Float
        , cpuGpu : Float
        , memUsed : Int
        , memTotal : Int
        , gpuMs : Float
        , elmMs : Float
        , drawMs : Float
        }
      -- The wifi card's name, if there is one.
    | WifiDevice (Maybe String)
    | WifiScan (List Wifi.Network)
    | WifiStatus Wifi.Status
    | Wired (List Wired.Link)
    | NetConfig { geoUrl : String, weatherUrl : String }
      -- Where the data disk is mounted, if there is one, and the HTTP requests an
      -- earlier program made that the host is still working on (Persist.elm).
    | DataDisk (Maybe String) (List String)
      -- id, status (404 included), body (Effect.bodyToString reads text)
    | HttpResponse String Int Bytes
      -- id, what went wrong, the host's message
    | HttpError String HttpFailure String
      -- Sorted; Nothing if the directory can't be listed.
    | Dir String (Maybe (List String))
      -- The id of the ReadFiles, and each path with its text, Nothing if it can't be read.
    | Files String (List ( String, Maybe String ))
      -- Path, offset, the bytes in hex: Nothing unless all the bytes asked for were read.
    | Bytes String Int (Maybe String)
      -- Path, the SHA-256 in hex: Nothing if the file is shorter than asked or can't be read.
    | Sha256 String (Maybe String)
      -- The host is about to replace this program with this build (Main.elm).
    | Switching String
      -- The newest deployed build, which needs the USB stick flashed again (Main.elm).
    | ReflashNeeded String
      -- Once a second.
    | Tick
      -- The snapshot file's text (Persist.elm).
    | Snapshot (Maybe String)
      -- After the logged messages Persist asked for again: the number of the last one
      -- an earlier program got.
    | ReplayDone Int


type HttpFailure
    = BadUrl
    | Timeout
    | Network


{-| Nothing if the bytes aren't a message.
-}
decode : Bytes -> Maybe ToElm
decode =
    BD.decode decoder


{-| What comes on `fromHost`: the message's number in the host's message log (if the
host logged it), then the message (protocol::from\_host\_payload).
-}
decodeNumbered : Bytes -> Maybe ( Maybe Int, ToElm )
decodeNumbered =
    BD.decode (BD.map2 Tuple.pair (P.decodeMaybe P.decodeUnsigned) decoder)


decoder : BD.Decoder ToElm
decoder =
    P.decodeUnsigned
        |> BD.andThen
            (\index ->
                case index of
                    0 ->
                        BD.map2 Screen P.decodeUnsigned P.decodeUnsigned

                    1 ->
                        BD.map Frame P.decodeFloat64

                    2 ->
                        BD.map2 Mouse P.decodeInt P.decodeInt

                    3 ->
                        BD.map2 Button P.decodeInt P.decodeBool

                    4 ->
                        BD.map Wheel P.decodeInt

                    5 ->
                        BD.map3 Key P.decodeUnsigned P.decodeBool P.decodeBool

                    6 ->
                        BD.map3 (\gpu name cursor -> Renderer { gpu = gpu, name = name, hardwareCursor = cursor })
                            P.decodeBool
                            P.decodeString
                            P.decodeBool

                    7 ->
                        BD.map3 (\kernel cpu commit -> System { kernel = kernel, cpu = cpu, commit = commit })
                            P.decodeString
                            P.decodeString
                            P.decodeString

                    8 ->
                        BD.map3 (\initMs elmMs frameMs -> Boot { initMs = initMs, elmMs = elmMs, frameMs = frameMs })
                            P.decodeFloat64
                            P.decodeFloat64
                            P.decodeFloat64

                    9 ->
                        stats

                    10 ->
                        BD.map WifiDevice (P.decodeMaybe P.decodeString)

                    11 ->
                        BD.map WifiScan (P.decodeList network)

                    12 ->
                        BD.map4 (\state ssid ip error -> WifiStatus { state = state, ssid = ssid, ip = ip, error = error })
                            wifiState
                            P.decodeString
                            P.decodeString
                            P.decodeString

                    13 ->
                        BD.map Wired (P.decodeList wiredLink)

                    14 ->
                        BD.map2 (\geo weather -> NetConfig { geoUrl = geo, weatherUrl = weather })
                            P.decodeString
                            P.decodeString

                    15 ->
                        BD.map2 DataDisk (P.decodeMaybe P.decodeString) (P.decodeList P.decodeString)

                    16 ->
                        BD.map3 HttpResponse P.decodeString P.decodeUnsigned P.decodeBytes

                    17 ->
                        BD.map3 HttpError P.decodeString httpFailure P.decodeString

                    18 ->
                        BD.map2 Dir P.decodeString (P.decodeMaybe (P.decodeList P.decodeString))

                    19 ->
                        BD.map2 Files
                            P.decodeString
                            (P.decodeList (P.decodeTuple P.decodeString (P.decodeMaybe P.decodeString)))

                    20 ->
                        BD.map3 Bytes P.decodeString P.decodeUnsigned (P.decodeMaybe P.decodeString)

                    21 ->
                        BD.map2 Sha256 P.decodeString (P.decodeMaybe P.decodeString)

                    22 ->
                        BD.map Switching P.decodeString

                    23 ->
                        BD.map ReflashNeeded P.decodeString

                    24 ->
                        BD.succeed Tick

                    25 ->
                        BD.map Snapshot (P.decodeMaybe P.decodeString)

                    26 ->
                        BD.map ReplayDone P.decodeUnsigned

                    _ ->
                        BD.fail
            )


stats : BD.Decoder ToElm
stats =
    BD.map5
        (\cores cpu cpuElm cpuHost cpuGpu ->
            BD.map5
                (\memUsed memTotal gpuMs elmMs drawMs ->
                    Stats
                        { cores = cores
                        , cpu = cpu
                        , cpuElm = cpuElm
                        , cpuHost = cpuHost
                        , cpuGpu = cpuGpu
                        , memUsed = memUsed
                        , memTotal = memTotal
                        , gpuMs = gpuMs
                        , elmMs = elmMs
                        , drawMs = drawMs
                        }
                )
                P.decodeInt
                P.decodeInt
                P.decodeFloat64
                P.decodeFloat64
                P.decodeFloat64
        )
        P.decodeInt
        P.decodeFloat64
        P.decodeFloat64
        P.decodeFloat64
        P.decodeFloat64
        |> BD.andThen identity


network : BD.Decoder Wifi.Network
network =
    BD.map3 Wifi.Network P.decodeString P.decodeInt security


{-| protocol::Security's variants, in order.
-}
security : BD.Decoder Wifi.Security
security =
    variants [ Wifi.Open, Wifi.Wpa, Wifi.Wpa3, Wifi.Enterprise, Wifi.Wep ]


wifiState : BD.Decoder Wifi.State
wifiState =
    variants [ Wifi.Idle, Wifi.Connecting, Wifi.Dhcp, Wifi.Connected, Wifi.Failed ]


wiredLink : BD.Decoder Wired.Link
wiredLink =
    BD.map3 Wired.Link
        P.decodeString
        (variants [ Wired.NoCable, Wired.Dhcp, Wired.Connected, Wired.Failed ])
        P.decodeString


httpFailure : BD.Decoder HttpFailure
httpFailure =
    variants [ BadUrl, Timeout, Network ]


{-| An enum whose variants have no fields: the nth of these for variant n.
-}
variants : List a -> BD.Decoder a
variants values =
    P.decodeUnsigned
        |> BD.andThen
            (\index ->
                case List.drop index values of
                    value :: _ ->
                        BD.succeed value

                    [] ->
                        BD.fail
            )
