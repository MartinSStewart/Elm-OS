module DoomApp exposing
    ( Disk
    , Download
    , Game
    , Model
    , Patching
    , Settings
    , UiId(..)
    , button
    , captured
    , click
    , dataDisk
    , directory
    , downloadProgress
    , downloaded
    , edited
    , entered
    , file
    , focusOn
    , frame
    , idToString
    , init
    , inputState
    , isTextInput
    , key
    , mouseMotion
    , open
    , restarted
    , takesButtons
    , view
    )

{-| Doom (the `sjalq/elm-doom` package, a pure Elm port of DOS Doom v1.9) as an app: a
window like the calculator's that shows the game's 320 x 200 screen as a picture (Ui.picture),
scaled up by a whole number with the 4:3 aspect DOS gave it (x times k, y times 1.2 k),
and plays it with the keyboard and the mouse.

  - The game runs in the Model, in a `Transient` (Transient.elm): it isn't saved. After
    a restart the window comes back with the game at its title screen, the WAD read
    again. What is saved is whether the window is open, which WAD, and Doom's settings.
  - The WADs: none come with the system. The WADs panel downloads them
    (Effect.Download) into the data disk's doom/ directory: shareware Doom, Doom with
    Evan Czaplicki on the status bar (a patch, from elm-doom's releases, that
    Doom.Wad.patch puts into the shareware WAD, here), and Freedoom Phase 1, each from
    an address the player can change, or a WAD from an address of their own. A
    download from its usual address must have the SHA-256 it should. Any `*.wad`
    already in doom/ is offered too. Each WAD's saved games are in doom/saves/<its name>/.
  - Time: the host's frame clock, as `Doom.Tick`; Doom paces itself at 35 tics a second.
  - Keyboard: Linux key codes to Doom's (i\_video.c's xlatekey), while the window has the
    keyboard. Autorepeat goes to Doom too, as DOS Doom's keyboard handler saw it.
  - Mouse: the pointer is the game's only while the player plays: in a game they
    started, with no menu or message of Doom's on the screen, not paused, and nothing
    of the window's (the Controls panel, a question) open. Then a click on the picture
    captures it (Effect.CapturePointer; that click isn't Doom's, so it doesn't fire),
    and the mouse's motion is Doom's (times 4, forwards up, as i\_video.c reports it).
    Everything else lets it go: so Esc (Doom's menu) and Pause give it back, as pointer
    lock does in a browser, without taking a key from the game. It isn't taken again
    when the game goes on: the player clicks the game. The automap keeps it.
  - Controls: DOS Doom changed its keys in its setup program, outside the game, so
    the window has a Controls panel around the game (Doom's menus stay the original's):
    each action and its key or mouse button, rebound by clicking it and pressing the
    new one (DoomControls.elm), and two presets, DOS's and WASD's. The game waits
    while the panel is open. The bindings are saved with the Model.
  - Sound: `sounds` turns Doom's sound and music commands into the host's (Effect.PlaySound
    and the rest): each of Doom's channels is a voice, and the music is MIDI.

-}

import Array exposing (Array)
import Bitwise
import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Bytes.Encode as BE
import Color
import Coord exposing (Coord)
import Dict exposing (Dict)
import Doom
import Doom.Audio as Audio
import Doom.Audio.Midi as Midi
import Doom.Config
import Doom.Event as Event
import Doom.Video as Video
import Doom.Wad as Wad
import DoomControls
import Effect exposing (Effect)
import Keyboard
import Quantity
import Scene
import Sprite
import TextInput
import Transient exposing (Transient)
import Ui
import Units exposing (DevicePixels, UiScale)



-- MODEL


{-| What is saved: whether the window is open, the WAD it plays (Nothing until the
player picks one), where its WADs come from, Doom's settings as its menus left them,
and its controls. `game` and `disk` aren't (Transient.elm): empty after a restart,
until the WAD is read and the data disk looked at again.
-}
type alias Model =
    { open : Bool
    , wad : Maybe String
    , settings : Settings
    , bindings : DoomControls.Bindings
    , dataDir : Maybe String

    -- A built-in WAD's address (`builtins`), by its file, where the player changed it.
    , addresses : Dict String String

    -- The addresses of WADs the player added, and the one they're typing.
    , ownWads : List String
    , newAddress : String

    -- The WADs panel is open (it is shown without a WAD to play, too).
    , choosing : Bool
    , game : Transient Game
    , disk : Transient Disk

    -- The pointer is captured, for Doom's mouse.
    , captured : Bool
    }


{-| Doom.Config.Settings, as the Model keeps them (tools/wire saves only Elm OS's own types).
-}
type alias Settings =
    { mouseSensitivity : Int
    , showMessages : Bool
    , detailLevel : Int
    , screenblocks : Int
    , sfxVolume : Int
    , musicVolume : Int
    , usegamma : Int
    }


{-| The game, from asking for the WAD on.
-}
type Game
    = Loading
    | Running Session
    | Failed String


type alias Session =
    { doom : Doom.Model

    -- The host clock at the last frame, for the time between frames.
    , lastFrame : Maybe Float
    , saveCount : Int

    -- The saved games read from the disk so far, for Doom.SavedGames.
    , saves : Dict Int Bytes

    -- The frame as the picture shows it: Doom's frame number, its pixels row by row,
    -- and the palette (page and gamma) it was shown with.
    , shown : { frame : Int, pixels : Bytes }
    , palette : { page : Int, gamma : Int, bytes : Bytes }
    , audio : Audio
    , buttons : Int

    -- The Controls panel, if open: and the action waiting for its new key or button.
    , panel : Maybe { choosing : Maybe DoomControls.Action }

    -- For the frame rate it logs now and then.
    , counted : Counted

    -- What the player asked for that would end the game in progress, while the
    -- window asks whether to.
    , asking : Maybe Leaving
    }


{-| Ways to leave a game in progress, which the window asks about first.
-}
type Leaving
    = SwitchTo String
    | Close


{-| What the app knows of the data disk's WADs: the files in doom/ and doom/patches/
from the last look, and since then, the downloads, those on their way and those that
failed (by path), the patches being put into their WADs (by the patched WAD's path),
and the WAD a patch made last, which the game starts from rather than read it back.
-}
type alias Disk =
    { wads : List String
    , patches : List String
    , downloads : Dict String Download
    , patching : Dict String Patching
    , patched : Maybe ( String, Bytes )
    }


type Download
    = Downloading { bytes : Int, total : Maybe Int }
    | DownloadFailed String


{-| A patch on its way into its WAD: the two files, read so far.
-}
type alias Patching =
    { base : String, patch : String, baseBytes : Maybe Bytes, patchBytes : Maybe Bytes }


{-| For the frame rate it logs: since when it counts, Doom's frame count then, the
last frame count seen and when it changed, and the longest time between changes.
-}
type alias Counted =
    { since : Float, frames : Int, last : Int, changed : Float, longest : Float }


init : Model
init =
    { open = False
    , wad = Nothing
    , settings = fromDoomSettings Doom.Config.defaultSettings
    , bindings = DoomControls.classic
    , dataDir = Nothing
    , addresses = Dict.empty
    , ownWads = []
    , newAddress = ""
    , choosing = False
    , game = Transient.empty
    , disk = Transient.empty
    , captured = False
    }


fromDoomSettings : Doom.Config.Settings -> Settings
fromDoomSettings s =
    { mouseSensitivity = s.mouseSensitivity
    , showMessages = s.showMessages
    , detailLevel = s.detailLevel
    , screenblocks = s.screenblocks
    , sfxVolume = s.sfxVolume
    , musicVolume = s.musicVolume
    , usegamma = s.usegamma
    }


toDoomSettings : Settings -> Doom.Config.Settings
toDoomSettings s =
    { mouseSensitivity = s.mouseSensitivity
    , showMessages = s.showMessages
    , detailLevel = s.detailLevel
    , screenblocks = s.screenblocks
    , sfxVolume = s.sfxVolume
    , musicVolume = s.musicVolume
    , usegamma = s.usegamma
    }


running : Model -> Maybe Session
running model =
    case Transient.get model.game of
        Just (Running r) ->
            Just r

        _ ->
            Nothing


captured : Model -> Bool
captured model =
    model.captured


open : Model -> Bool
open model =
    model.open



-- STARTING


{-| The program started (Main's Screen): the pointer isn't captured, and an open
window's game, gone with the last program, starts again from the WAD.
-}
restarted : Model -> ( Model, List Effect )
restarted model =
    if model.open then
        load { model | captured = False }

    else
        ( { model | captured = False, game = Transient.empty }, [] )


{-| Starts the WAD the window plays: the one a patch has just made, or read from the
disk. Without one, the WADs panel shows.
-}
load : Model -> ( Model, List Effect )
load model =
    case model.wad of
        Just path ->
            case (disk model).patched of
                Just ( made, bytes ) ->
                    if made == path then
                        start bytes model

                    else
                        ( { model | game = Transient.wrap Loading }, [ Effect.ReadFile { path = path } ] )

                Nothing ->
                    ( { model | game = Transient.wrap Loading }, [ Effect.ReadFile { path = path } ] )

        Nothing ->
            ( { model | game = Transient.empty }, [] )


{-| Where the data disk is (Persist tells Main): look for WADs on it.
-}
dataDisk : Maybe String -> Model -> ( Model, List Effect )
dataDisk dir model =
    ( { model | dataDir = dir }
    , case dir of
        Just d ->
            [ Effect.ListDir (d ++ "/doom"), Effect.ListDir (d ++ "/doom/patches") ]

        Nothing ->
            []
    )


{-| A directory listing that `dataDisk` asked for, if `path` is one. A patch and its
WAD found there without the WAD it makes are put together (`patchAll`).
-}
directory : String -> Maybe (List String) -> Model -> Maybe ( Model, List Effect )
directory path entries model =
    let
        files suffix =
            Maybe.withDefault [] entries
                |> List.filter (\name -> String.endsWith suffix (String.toLower name) && not (String.startsWith "." name))
                |> List.map (\name -> path ++ "/" ++ name)
    in
    case model.dataDir of
        Just dir ->
            if path == dir ++ "/doom" then
                Just (patchAll (withDisk (\d -> { d | wads = files ".wad" }) model))

            else if path == dir ++ "/doom/patches" then
                Just (patchAll (withDisk (\d -> { d | patches = files "" }) model))

            else
                Nothing

        Nothing ->
            Nothing


disk : Model -> Disk
disk model =
    Transient.get model.disk
        |> Maybe.withDefault { wads = [], patches = [], downloads = Dict.empty, patching = Dict.empty, patched = Nothing }


withDisk : (Disk -> Disk) -> Model -> Model
withDisk f model =
    { model | disk = Transient.wrap (f (disk model)) }



-- WADS


{-| Where a WAD comes from. `file` is what it is saved as in the data disk's doom/,
`sha256` what it must be (the download's: the patch, for a patch), only at its own
address, and `unzip` the WAD's name in a zip. A patch (`patchOf`, the file of the WAD
it patches) is saved in doom/patches/, and put into its WAD to make `file`.
-}
type alias Source =
    { name : String
    , file : String
    , address : String
    , usual : Maybe String
    , sha256 : Maybe String
    , unzip : String
    , patchOf : Maybe String
    }


{-| The WADs the window offers. Shareware Doom is in the zip id Software put out in
1995, as the Internet Archive keeps it (its DOOM1.WAD is v1.9's); the Evan edition is
a patch of 46 of its lumps (elm-doom's mods-1 release); Freedoom is the release the
Freedoom project put out.
-}
builtins : List { name : String, file : String, address : String, sha256 : String, unzip : String, patchOf : Maybe String }
builtins =
    [ { name = "Doom (shareware)"
      , file = "doom1.wad"
      , address = "https://archive.org/download/DoomsharewareEpisode/doom.ZIP"
      , sha256 = "1d7d43be501e67d927e415e0b8f3e29c3bf33075e859721816f652a526cac771"
      , unzip = "doom1.wad"
      , patchOf = Nothing
      }
    , { name = "Doom, Evan's edition"
      , file = "doom1-evan.wad"
      , address = "https://github.com/sjalq/elm-doom/releases/download/mods-1/evan.wad"
      , sha256 = "248321b58da866ef333c6aa53f6296d53cc72b13cf199fa1c2012af694a32dce"
      , unzip = ".wad"
      , patchOf = Just "doom1.wad"
      }
    , { name = "Freedoom"
      , file = "freedoom1.wad"
      , address = "https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip"
      , sha256 = "7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d"
      , unzip = "freedoom1.wad"
      , patchOf = Nothing
      }
    ]


{-| The built-in WADs at the addresses the player left them, then the player's own.
-}
sources : Model -> List Source
sources model =
    List.map
        (\b ->
            let
                address =
                    Dict.get b.file model.addresses |> Maybe.withDefault b.address
            in
            { name = b.name
            , file = b.file
            , address = address
            , usual = Just b.address
            , sha256 =
                if address == b.address then
                    Just b.sha256

                else
                    Nothing
            , unzip = b.unzip
            , patchOf = b.patchOf
            }
        )
        builtins
        ++ List.map
            (\address ->
                { name = fileFor address
                , file = fileFor address
                , address = address
                , usual = Nothing
                , sha256 = Nothing
                , unzip = ".wad"
                , patchOf = Nothing
                }
            )
            model.ownWads


source : Int -> Model -> Maybe Source
source n model =
    List.drop n (sources model) |> List.head


{-| What a WAD from this address is saved as: the last part of its path, lower case,
in letters, digits, dots, dashes and underscores, as a .wad ("doom.zip": "doom.wad").
-}
fileFor : String -> String
fileFor address =
    let
        last =
            address
                |> String.split "?"
                |> List.head
                |> Maybe.withDefault address
                |> String.split "#"
                |> List.head
                |> Maybe.withDefault address
                |> String.split "/"
                |> List.reverse
                |> List.head
                |> Maybe.withDefault ""
                |> String.toLower
                |> String.filter (\c -> Char.isAlphaNum c || c == '.' || c == '-' || c == '_')
                |> dropLeadingDots

        stem =
            if String.endsWith ".zip" last || String.endsWith ".wad" last then
                String.dropRight 4 last

            else
                last
    in
    (if stem == "" then
        "download"

     else
        stem
    )
        ++ ".wad"


dropLeadingDots : String -> String
dropLeadingDots text =
    if String.startsWith "." text then
        dropLeadingDots (String.dropLeft 1 text)

    else
        text


{-| Where a WAD of this name is on the disk, in any case (DOOM1.WAD is doom1.wad).
-}
onDisk : String -> Model -> Maybe String
onDisk name model =
    (disk model).wads
        |> List.filter (\path -> String.toLower (lastPart path) == String.toLower name)
        |> List.head


lastPart : String -> String
lastPart path =
    String.split "/" path |> List.reverse |> List.head |> Maybe.withDefault path


wadPath : String -> String -> String
wadPath dir name =
    dir ++ "/doom/" ++ name


patchPath : String -> String -> String
patchPath dir name =
    dir ++ "/doom/patches/" ++ name


{-| How a WAD stands, for the panel.
-}
type Standing
    = OnDisk String
    | Getting String
    | GotStuck String
    | NotHere


standing : Source -> Model -> Standing
standing src model =
    case ( onDisk src.file model, model.dataDir ) of
        ( Just path, _ ) ->
            OnDisk path

        ( Nothing, Nothing ) ->
            NotHere

        ( Nothing, Just dir ) ->
            let
                d =
                    disk model

                pieces =
                    List.map (\( path, what ) -> ( Dict.get path d.downloads, what )) (piecePaths dir src model)

                megabytes n =
                    String.fromFloat (toFloat (round (toFloat n / 104857.6)) / 10)

                progress what p =
                    "Downloading "
                        ++ what
                        ++ ": "
                        ++ megabytes p.bytes
                        ++ (case p.total of
                                Just total ->
                                    " of " ++ megabytes total ++ " MB"

                                Nothing ->
                                    " MB"
                           )
            in
            case List.filterMap (\( dl, what ) -> Maybe.map (Tuple.pair what) dl) pieces of
                ( _, DownloadFailed problem ) :: _ ->
                    GotStuck problem

                ( what, Downloading p ) :: _ ->
                    Getting (progress what p)

                [] ->
                    case Dict.get (wadPath dir src.file) d.downloads of
                        Just (DownloadFailed problem) ->
                            GotStuck problem

                        _ ->
                            if Dict.member (wadPath dir src.file) d.patching then
                                Getting "Putting the patch in"

                            else
                                NotHere


{-| The downloads a WAD needs, with what each is (for the panel): the WAD, or for a
patch, the WAD it patches and the patch.
-}
piecePaths : String -> Source -> Model -> List ( String, String )
piecePaths dir src model =
    case src.patchOf of
        Nothing ->
            [ ( wadPath dir src.file, "the WAD" ) ]

        Just base ->
            [ ( Maybe.withDefault (wadPath dir base) (onDisk base model), "the WAD it patches" )
            , ( patchPath dir src.file, "the patch" )
            ]


{-| Downloads what a WAD needs that isn't on the disk or on its way.
-}
get : Source -> Model -> ( Model, List Effect )
get src model =
    case model.dataDir of
        Just dir ->
            let
                d =
                    disk model

                whole s =
                    { url = s.address, path = wadPath dir s.file, sha256 = s.sha256, unzip = Just s.unzip }

                wanted =
                    case src.patchOf of
                        Nothing ->
                            [ whole src ]

                        Just base ->
                            (case ( onDisk base model, List.filter (\s -> s.file == base) (sources model) ) of
                                ( Nothing, baseSource :: _ ) ->
                                    [ whole baseSource ]

                                _ ->
                                    []
                            )
                                ++ (if List.member (patchPath dir src.file) d.patches then
                                        []

                                    else
                                        [ { url = src.address, path = patchPath dir src.file, sha256 = src.sha256, unzip = Just src.unzip } ]
                                   )

                needed =
                    List.filter
                        (\w ->
                            case Dict.get w.path d.downloads of
                                Just (Downloading _) ->
                                    False

                                _ ->
                                    True
                        )
                        wanted
            in
            withDisk
                (\d2 ->
                    { d2
                        | downloads =
                            List.foldl (\w -> Dict.insert w.path (Downloading { bytes = 0, total = Nothing }))
                                (Dict.remove (wadPath dir src.file) d2.downloads)
                                needed
                    }
                )
                model
                |> patchAll
                |> Tuple.mapSecond (\effects -> List.map Effect.Download needed ++ effects)

        Nothing ->
            ( model, [] )


{-| How far a download has got (HostMessage.DownloadProgress), if it is one of the app's.
-}
downloadProgress : String -> Int -> Maybe Int -> Model -> Maybe Model
downloadProgress path bytes total model =
    if Dict.member path (disk model).downloads then
        Just (withDisk (\d -> { d | downloads = Dict.insert path (Downloading { bytes = bytes, total = total }) d.downloads }) model)

    else
        Nothing


{-| A download has ended (HostMessage.Downloaded), if it is in the app's directories:
the file is on the disk, or what went wrong stays on the panel. A patch whose pieces
are all there now goes into its WAD.
-}
downloaded : String -> Maybe String -> Model -> Maybe ( Model, List Effect )
downloaded path problem model =
    case model.dataDir of
        Just dir ->
            if String.startsWith (dir ++ "/doom/") path then
                Just
                    (withDisk
                        (\d ->
                            case problem of
                                Nothing ->
                                    { d
                                        | downloads = Dict.remove path d.downloads
                                        , wads =
                                            if String.startsWith (dir ++ "/doom/patches/") path || List.member path d.wads then
                                                d.wads

                                            else
                                                d.wads ++ [ path ]
                                        , patches =
                                            if String.startsWith (dir ++ "/doom/patches/") path && not (List.member path d.patches) then
                                                d.patches ++ [ path ]

                                            else
                                                d.patches
                                    }

                                Just why ->
                                    { d | downloads = Dict.insert path (DownloadFailed why) d.downloads }
                        )
                        model
                        |> patchAll
                    )

            else
                Nothing

        Nothing ->
            Nothing


{-| Every patch on the disk whose WAD is there too, without the WAD they make: read
both, to put them together (`patchPiece`).
-}
patchAll : Model -> ( Model, List Effect )
patchAll model =
    case model.dataDir of
        Just dir ->
            let
                d =
                    disk model

                ready =
                    sources model
                        |> List.filterMap
                            (\src ->
                                case ( src.patchOf, onDisk src.file model ) of
                                    ( Just base, Nothing ) ->
                                        Maybe.map
                                            (\basePath ->
                                                ( wadPath dir src.file, { base = basePath, patch = patchPath dir src.file, baseBytes = Nothing, patchBytes = Nothing } )
                                            )
                                            (onDisk base model)
                                            |> Maybe.andThen
                                                (\( target, p ) ->
                                                    if
                                                        List.member p.patch d.patches
                                                            && not (Dict.member target d.patching)
                                                            && not (Dict.member target d.downloads)
                                                    then
                                                        Just ( target, p )

                                                    else
                                                        Nothing
                                                )

                                    _ ->
                                        Nothing
                            )
            in
            ( withDisk (\d2 -> { d2 | patching = Dict.union (Dict.fromList ready) d2.patching }) model
            , List.concatMap (\( _, p ) -> [ Effect.ReadFile { path = p.base }, Effect.ReadFile { path = p.patch } ]) ready
            )

        Nothing ->
            ( model, [] )


{-| A file a patch needs has been read: once both are, the patch goes into its WAD
(Doom.Wad.patch), which is saved, and kept for the game to start from.
-}
patchPiece : String -> Maybe Bytes -> Model -> ( Model, List Effect )
patchPiece path maybeBytes model =
    let
        d =
            disk model

        step ( target, p ) ( dk, effects ) =
            if p.base /= path && p.patch /= path then
                ( dk, effects )

            else
                case maybeBytes of
                    Nothing ->
                        -- Unreadable, or a Msg replayed after a restart (its bytes are gone).
                        ( { dk | patching = Dict.remove target dk.patching, downloads = Dict.insert target (DownloadFailed ("Couldn't read " ++ path)) dk.downloads }, effects )

                    Just bytes ->
                        let
                            p2 =
                                if p.base == path then
                                    { p | baseBytes = Just bytes }

                                else
                                    { p | patchBytes = Just bytes }
                        in
                        case ( p2.baseBytes, p2.patchBytes ) of
                            ( Just baseBytes, Just patchBytes ) ->
                                case Result.map2 Wad.patch (Wad.fromBytes patchBytes) (Wad.fromBytes baseBytes) of
                                    Ok wad ->
                                        let
                                            made =
                                                Wad.toBytes wad
                                        in
                                        ( { dk
                                            | patching = Dict.remove target dk.patching
                                            , wads = dk.wads ++ [ target ]
                                            , patched = Just ( target, made )
                                          }
                                        , effects ++ [ Effect.WriteBytes { path = target, bytes = made }, Effect.Log ("doom: made " ++ target) ]
                                        )

                                    Err problem ->
                                        ( { dk | patching = Dict.remove target dk.patching, downloads = Dict.insert target (DownloadFailed problem) dk.downloads }, effects )

                            _ ->
                                ( { dk | patching = Dict.insert target p2 dk.patching }, effects )

        ( newDisk, out ) =
            List.foldl step ( d, [] ) (Dict.toList d.patching)
    in
    ( { model | disk = Transient.wrap newDisk }, out )



-- THE ADDRESS BOXES


{-| The WADs panel's text boxes (Main types into them, Ui.textInput).
-}
isTextInput : UiId -> Bool
isTextInput id =
    case id of
        AddressInput _ ->
            True

        NewAddressInput ->
            True

        _ ->
            False


inputText : UiId -> Model -> String
inputText id model =
    case id of
        AddressInput n ->
            source n model |> Maybe.map .address |> Maybe.withDefault ""

        NewAddressInput ->
            model.newAddress

        _ ->
            ""


{-| A text box's state: as Main keeps it (where the cursor is, what to undo), unless
its text isn't the box's any more (another address went in its place), then the
box's text with the cursor at its end.
-}
inputState : UiId -> Maybe TextInput.Model -> Model -> TextInput.Model
inputState id kept model =
    let
        text =
            inputText id model
    in
    case kept of
        Just state ->
            if state.current.text == text then
                state

            else
                fresh text

        Nothing ->
            fresh text


fresh : String -> TextInput.Model
fresh text =
    { current = { cursorPosition = String.length text, cursorSize = 0, text = text }, undoHistory = [], redoHistory = [] }


{-| The player typed in a text box: a WAD's address is its new one at once.
-}
edited : UiId -> String -> Model -> Model
edited id text model =
    case id of
        AddressInput n ->
            let
                builtinCount =
                    List.length builtins
            in
            if n < builtinCount then
                case List.drop n builtins |> List.head of
                    Just b ->
                        { model
                            | addresses =
                                if text == b.address then
                                    Dict.remove b.file model.addresses

                                else
                                    Dict.insert b.file text model.addresses
                        }

                    Nothing ->
                        model

            else
                { model
                    | ownWads =
                        List.indexedMap
                            (\i a ->
                                if i == n - builtinCount then
                                    text

                                else
                                    a
                            )
                            model.ownWads
                }

        NewAddressInput ->
            { model | newAddress = text }

        _ ->
            model


{-| Enter in a text box: a new address is added.
-}
entered : UiId -> Model -> ( Model, List Effect )
entered id model =
    case id of
        NewAddressInput ->
            click AddButton model

        _ ->
            ( model, [] )


{-| A file Effect.ReadFile asked for: the WAD, or a saved game. Nothing if it is
neither. A replayed Msg's bytes are gone (Transient), and so it does nothing.
-}
file : String -> Maybe (Transient Bytes) -> Model -> Maybe ( Model, List Effect )
file path maybeBytes model =
    if List.any (\p -> p.base == path || p.patch == path) (Dict.values (disk model).patching) then
        Just (patchPiece path (Maybe.andThen Transient.get maybeBytes) model)

    else
        wadOrSave path maybeBytes model


wadOrSave : String -> Maybe (Transient Bytes) -> Model -> Maybe ( Model, List Effect )
wadOrSave path maybeBytes model =
    case Transient.get model.game of
        Just Loading ->
            if Just path == model.wad then
                case maybeBytes of
                    Just transient ->
                        case Transient.get transient of
                            Just bytes ->
                                Just (start bytes model)

                            Nothing ->
                                Just ( model, [] )

                    Nothing ->
                        Just ( { model | game = Transient.wrap (Failed ("Couldn't read " ++ path)) }, [] )

            else
                Nothing

        Just (Running r) ->
            case saveSlot model path of
                Just slot ->
                    let
                        saves =
                            case Maybe.andThen Transient.get maybeBytes of
                                Just bytes ->
                                    Dict.insert slot bytes r.saves

                                Nothing ->
                                    r.saves

                        ( doom, commands ) =
                            Doom.update (Doom.SavedGames saves) r.doom
                    in
                    Just (withSounds commands { r | doom = doom, saves = saves } model)

                Nothing ->
                    Nothing

        _ ->
            Nothing


start : Bytes -> Model -> ( Model, List Effect )
start bytes model =
    let
        options =
            Doom.defaultOptions
    in
    -- The menu's Quit ends the game, as I_Quit did, and that closes the window.
    case Doom.start { options | settings = toDoomSettings model.settings, bindings = model.bindings, quitToTitle = False } bytes of
        Ok ( doom, commands ) ->
            let
                r =
                    { doom = doom
                    , lastFrame = Nothing
                    , saveCount = Doom.saveCount doom
                    , saves = Dict.empty
                    , shown = { frame = -1, pixels = emptyBytes }
                    , palette = { page = -1, gamma = -1, bytes = emptyBytes }
                    , audio = initAudio
                    , buttons = 0
                    , panel = Nothing
                    , counted = { since = 0, frames = 0, last = 0, changed = 0, longest = 0 }
                    , asking = Nothing
                    }
                        |> showFrame

                ( next, effects ) =
                    withSounds commands r model
            in
            ( next
            , effects
                ++ List.filterMap (\slot -> savePath model slot |> Maybe.map (\path -> Effect.ReadFile { path = path })) (List.range 0 5)
                ++ [ Effect.Log ("doom: started " ++ Maybe.withDefault "" model.wad) ]
            )

        Err problem ->
            ( { model | game = Transient.wrap (Failed problem) }, [ Effect.Log ("doom: " ++ Maybe.withDefault "" model.wad ++ ": " ++ problem) ] )


emptyBytes : Bytes
emptyBytes =
    BE.encode (BE.sequence [])


{-| The WAD's name without its directory or ".wad", lower case: "freedoom1".
-}
wadName : String -> String
wadName path =
    String.split "/" path
        |> List.reverse
        |> List.head
        |> Maybe.withDefault path
        |> String.toLower
        |> (\name ->
                if String.endsWith ".wad" name then
                    String.dropRight 4 name

                else
                    name
           )


{-| Where a saved game goes: on the data disk, by WAD (Nothing without a data disk).
-}
savePath : Model -> Int -> Maybe String
savePath model slot =
    Maybe.map2 (\dir wad -> dir ++ "/doom/saves/" ++ wadName wad ++ "/doomsav" ++ String.fromInt slot ++ ".dsg")
        model.dataDir
        model.wad


saveSlot : Model -> String -> Maybe Int
saveSlot model path =
    List.range 0 5 |> List.filter (\slot -> savePath model slot == Just path) |> List.head



-- RUNNING


{-| A frame: the time since the last one goes to Doom, which runs the tics that are due.
-}
frame : Float -> Model -> ( Model, List Effect )
frame time model =
    case running model of
        Just r ->
            let
                ( doom, commands ) =
                    case ( r.lastFrame, r.panel, model.choosing ) of
                        ( Just last, Nothing, False ) ->
                            Doom.update (Doom.Tick (time - last)) r.doom

                        _ ->
                            -- The game waits while the Controls or the WADs panel is open.
                            ( r.doom, [] )

                ( counted, logs ) =
                    countFrames time r.counted (Doom.frames doom)

                ( next, effects ) =
                    withSounds commands { r | doom = doom, lastFrame = Just time, counted = counted } model
            in
            if Doom.finished doom then
                close next |> Tuple.mapSecond (\closing -> effects ++ logs ++ closing)

            else
                -- Doom's menu (Esc), a message or Pause came up: the mouse goes back.
                releaseUnlessPlaying next |> Tuple.mapSecond (\releasing -> effects ++ logs ++ releasing)

        Nothing ->
            ( model, [] )


{-| Every 10 seconds, how many frames Doom showed (35 a second when all is well), and
the longest time the picture went without a new one, for the serial console.
-}
countFrames : Float -> Counted -> Int -> ( Counted, List Effect )
countFrames time counted frames =
    let
        ( changed, longest ) =
            if frames /= counted.last then
                ( time, max counted.longest (time - counted.changed) )

            else
                ( counted.changed, counted.longest )
    in
    if counted.since == 0 then
        ( { since = time, frames = frames, last = frames, changed = time, longest = 0 }, [] )

    else if time - counted.since >= 10000 then
        ( { since = time, frames = frames, last = frames, changed = changed, longest = 0 }
        , [ Effect.Log
                ("doom: "
                    ++ String.fromInt (frames - counted.frames)
                    ++ " frames in "
                    ++ String.fromInt (round (time - counted.since))
                    ++ " ms, longest gap "
                    ++ String.fromInt (round longest)
                    ++ " ms"
                )
          ]
        )

    else
        ( { counted | last = frames, changed = changed, longest = longest }, [] )


{-| After Doom ran: keep the frame's pixels if it showed a new one, its settings and
saved games if they changed, and play its sounds.
-}
withSounds : List Audio.Command -> Session -> Model -> ( Model, List Effect )
withSounds commands r model =
    let
        r2 =
            showFrame r

        settings =
            fromDoomSettings (Doom.settings r2.doom)

        saveEffects =
            if Doom.saveCount r2.doom /= r2.saveCount then
                Doom.savedGames r2.doom
                    |> Dict.toList
                    |> List.filterMap (\( slot, bytes ) -> savePath model slot |> Maybe.map (\path -> Effect.WriteBytes { path = path, bytes = bytes }))

            else
                []

        ( audio, soundEffects ) =
            sounds r2.audio r2.doom commands
    in
    ( { model
        | game = Transient.wrap (Running { r2 | saveCount = Doom.saveCount r2.doom, audio = audio })
        , settings = settings
      }
    , saveEffects ++ soundEffects
    )


{-| The picture's pixels and palette, made again only when Doom shows a new frame or
another palette.
-}
showFrame : Session -> Session
showFrame r =
    let
        screen =
            Doom.view r.doom

        frames =
            Doom.frames r.doom
    in
    { r
        | shown =
            if frames /= r.shown.frame then
                { frame = frames, pixels = rows screen.pixels }

            else
                r.shown
        , palette =
            if screen.palette /= r.palette.page || screen.gamma /= r.palette.gamma then
                { page = screen.palette, gamma = screen.gamma, bytes = palette (Doom.wad r.doom) screen.palette screen.gamma }

            else
                r.palette
    }


{-| The screen's pixels row by row from the top left, as Doom.Video.toBytes gives
them, but a few times quicker (about 1.4 ms rather than 8 natively, where a frame has
28.6 ms): each word of four pixels straight from the columns Doom keeps.
-}
rows : Video.Framebuffer -> Bytes
rows framebuffer =
    let
        columns =
            Video.columns framebuffer

        at x y =
            case Array.get x columns of
                Just column ->
                    case Array.get y column of
                        Just index ->
                            index

                        Nothing ->
                            0

                Nothing ->
                    0

        -- From the end, so the list comes out in order.
        go x y words =
            if y < 0 then
                words

            else if x < 0 then
                go (Video.width - 4) (y - 1) words

            else
                go (x - 4) y (BE.unsignedInt32 Bytes.BE (((at x y * 256 + at (x + 1) y) * 256 + at (x + 2) y) * 256 + at (x + 3) y) :: words)
    in
    BE.encode (BE.sequence (go (Video.width - 4) (Video.height - 1) []))


{-| PLAYPAL's palette `page` (768 bytes), through v\_video.c's gammatable row `gamma`.
-}
palette : Wad.Wad -> Int -> Int -> Bytes
palette wad page gamma =
    let
        table =
            Array.get (clamp 0 4 gamma) gammaTable |> Maybe.withDefault Array.empty

        bytes =
            Wad.lump "PLAYPAL" wad |> Maybe.withDefault emptyBytes

        skip =
            modBy 14 page * 768
    in
    BD.decode
        (BD.bytes skip
            |> BD.andThen
                (\_ ->
                    BD.loop ( 768, [] )
                        (\( left, out ) ->
                            if left <= 0 then
                                BD.succeed (BD.Done (List.reverse out))

                            else
                                BD.unsignedInt8 |> BD.map (\v -> BD.Loop ( left - 1, (Array.get v table |> Maybe.withDefault v) :: out ))
                        )
                )
        )
        bytes
        |> Maybe.withDefault (List.repeat 768 0)
        |> List.map BE.unsignedInt8
        |> BE.sequence
        |> BE.encode


{-| A key, while the window has the keyboard: Doom's, or the Controls panel's while
it is open.
-}
key : Int -> Bool -> Model -> ( Model, List Effect )
key code down model =
    case running model of
        Just _ ->
            if model.choosing then
                -- Esc closes the WADs panel; the game doesn't see keys while it is open.
                ( if down && code == keyEscape then
                    { model | choosing = False }

                  else
                    model
                , []
                )

            else
                gameKey code down model

        Nothing ->
            ( model, [] )


gameKey : Int -> Bool -> Model -> ( Model, List Effect )
gameKey code down model =
    case running model of
        Just r ->
            case r.panel of
                Just panel ->
                    if down then
                        ( panelKey code panel r model, [] )

                    else
                        ( model, [] )

                Nothing ->
                    let
                        event =
                            doomKey code
                                |> Maybe.map
                                    (\k ->
                                        if down then
                                            Event.KeyDown k

                                        else
                                            Event.KeyUp k
                                    )
                    in
                    ( send (Maybe.withDefault [] (Maybe.map List.singleton event)) r model, [] )

        Nothing ->
            ( model, [] )


{-| A key in the Controls panel: the new key of the action waiting for one (Backspace
for none, Esc to leave it as it was), or with none waiting, Esc closes the panel.
-}
panelKey : Int -> { choosing : Maybe DoomControls.Action } -> Session -> Model -> Model
panelKey code panel r model =
    case panel.choosing of
        Just action ->
            if code == keyEscape then
                withSession (\r2 -> { r2 | panel = Just { choosing = Nothing } }) model

            else if code == keyBackspace then
                setBindings (DoomControls.unbind action model.bindings) model

            else
                case ( DoomControls.input action, doomKey code ) of
                    ( DoomControls.Key, Just k ) ->
                        setBindings (DoomControls.bind action k model.bindings) model

                    _ ->
                        model

        Nothing ->
            if code == keyEscape then
                { model | game = Transient.wrap (Running { r | panel = Nothing }) }

            else
                model


{-| New bindings: saved, and the game's from its next tic; no action waits any more.
-}
setBindings : DoomControls.Bindings -> Model -> Model
setBindings bindings model =
    withSession (\r -> { r | doom = Doom.setBindings bindings r.doom, panel = Just { choosing = Nothing } })
        { model | bindings = bindings }


keyEscape : Int
keyEscape =
    1


keyBackspace : Int
keyBackspace =
    14


send : List Event.Event -> Session -> Model -> Model
send events r model =
    { model
        | game =
            Transient.wrap
                (Running { r | doom = List.foldl (\e doom -> Doom.update (Doom.Event e) doom |> Tuple.first) r.doom events })
    }


{-| Mouse motion while the pointer is captured: i\_video.c's, times 4, forwards up.
-}
mouseMotion : Int -> Int -> Model -> Model
mouseMotion dx dy model =
    case running model of
        Just r ->
            if model.captured then
                send [ Event.Mouse r.buttons (dx * 4) (-dy * 4) ] r model

            else
                model

        Nothing ->
            model


{-| The mouse's buttons are the app's: the pointer is captured, or the Controls panel
waits for a mouse button.
-}
takesButtons : Model -> Bool
takesButtons model =
    model.captured || choosingButton model


choosingButton : Model -> Bool
choosingButton model =
    case running model |> Maybe.andThen .panel |> Maybe.andThen .choosing of
        Just action ->
            DoomControls.input action == DoomControls.Button

        Nothing ->
            False


{-| A mouse button (0 left, 1 right, 2 middle) while `takesButtons`: Doom's, or the
new button of the panel's action waiting for one.
-}
button : Int -> Bool -> Model -> Model
button b down model =
    case running model of
        Just r ->
            if choosingButton model then
                case ( down, Maybe.andThen .choosing r.panel ) of
                    ( True, Just action ) ->
                        if b >= 0 && b <= 2 then
                            setBindings (DoomControls.bind action b model.bindings) model

                        else
                            model

                    _ ->
                        model

            else
                doomButton b down r model

        Nothing ->
            model


doomButton : Int -> Bool -> Session -> Model -> Model
doomButton b down r model =
    if not model.captured then
        model

    else
        let
            bit =
                case b of
                    0 ->
                        1

                    1 ->
                        2

                    2 ->
                        4

                    _ ->
                        0

            buttons =
                if down then
                    Bitwise.or r.buttons bit

                else
                    Bitwise.and r.buttons (Bitwise.complement bit)
        in
        send [ Event.Mouse buttons 0 0 ] { r | buttons = buttons } model


{-| The player is playing: in a game they started, with nothing of Doom's or the
window's on top of it (`Doom.menuActive` covers the menu and its messages, the
"are you sure?" ones too). Only then is the pointer the game's.
-}
playing : Session -> Bool
playing r =
    inGame r
        && not (Doom.menuActive r.doom)
        && not (Doom.paused r.doom)
        && r.asking
        == Nothing
        && r.panel
        == Nothing


{-| Lets the pointer go when the player stops playing (`playing`).
-}
releaseUnlessPlaying : Model -> ( Model, List Effect )
releaseUnlessPlaying model =
    case running model of
        Just r ->
            if playing r then
                ( model, [] )

            else
                release model

        Nothing ->
            release model


{-| Lets the pointer go, with Doom's mouse buttons up.
-}
release : Model -> ( Model, List Effect )
release model =
    if model.captured then
        ( case running model of
            Just r ->
                send [ Event.Mouse 0 0 0 ] { r | buttons = 0 } { model | captured = False }

            Nothing ->
                { model | captured = False }
        , [ Effect.CapturePointer False ]
        )

    else
        ( model, [] )


{-| i\_video.c's xlatekey for a Linux key code (linux/input-event-codes.h): arrows,
Escape, Enter, Tab, Backspace (and Delete), the F keys, Pause, -, =, Shift, Ctrl and
Alt (either side) as Doom's own codes; what types a character as its lower-case ASCII
(Shift doesn't change it: Doom's menu shifts it itself); the number pad as the keys
it types.
-}
doomKey : Int -> Maybe Int
doomKey code =
    case code of
        1 ->
            Just Event.keyEscape

        14 ->
            Just Event.keyBackspace

        111 ->
            Just Event.keyBackspace

        15 ->
            Just Event.keyTab

        28 ->
            Just Event.keyEnter

        96 ->
            Just Event.keyEnter

        103 ->
            Just Event.keyUpArrow

        108 ->
            Just Event.keyDownArrow

        105 ->
            Just Event.keyLeftArrow

        106 ->
            Just Event.keyRightArrow

        42 ->
            Just Event.keyRShift

        54 ->
            Just Event.keyRShift

        29 ->
            Just Event.keyRCtrl

        97 ->
            Just Event.keyRCtrl

        56 ->
            Just Event.keyRAlt

        100 ->
            Just Event.keyRAlt

        87 ->
            Just Event.keyF11

        88 ->
            Just Event.keyF12

        119 ->
            Just Event.keyPause

        58 ->
            Just Event.keyCapsLock

        70 ->
            Just Event.keyScrollLock

        69 ->
            Just Event.keyNumLock

        57 ->
            Just 32

        _ ->
            if code >= 59 && code <= 68 then
                -- F1 to F10
                Just (Event.keyF1 + code - 59)

            else
                case Keyboard.fromCode False code of
                    Keyboard.Character text ->
                        String.toList (String.toLower text) |> List.head |> Maybe.map Char.toCode

                    _ ->
                        Nothing



-- SOUND


{-| What playing sounds needs to remember: Chocolate Doom's mus2mid state (a song's
MIDI can depend on the songs before it, see Doom.Audio.Midi), and the sound lumps
already cut out of the WAD.
-}
type alias Audio =
    { converter : Midi.Converter
    , cut : Dict String (Maybe Effect.Sound)
    }


initAudio : Audio
initAudio =
    { converter = Midi.fresh, cut = Dict.empty }


{-| Doom's sound commands as the host's, as Chocolate Doom plays them
(i\_sdlsound.c, and elm-doom's hosts/browser/host.js): a channel is a voice; volume (0 to 127, the
sfx volume already in it) and separation (0 left, 255 right) give the left and right
gains `(254 - sep) * vol / 127` and `sep * vol / 127` out of 255; DOS v1.9 ignored the
pitch, so the speed is 1. Music: the music lump as MIDI (`toMidi`; one Converter
for the whole game, as Chocolate converts each song in turn), played with the WAD's
GENMIDI instruments.
-}
sounds : Audio -> Doom.Model -> List Audio.Command -> ( Audio, List Effect )
sounds audio doom commands =
    List.foldl
        (\command ( a, out ) ->
            let
                ( a2, effects ) =
                    soundEffect (Doom.wad doom) command a
            in
            ( a2, out ++ effects )
        )
        ( audio, [] )
        commands


soundEffect : Wad.Wad -> Audio.Command -> Audio -> ( Audio, List Effect )
soundEffect wad command audio =
    case command of
        Audio.StartSound c ->
            let
                ( sound, cut ) =
                    case Dict.get c.lump audio.cut of
                        Just s ->
                            ( s, audio.cut )

                        Nothing ->
                            let
                                s =
                                    Wad.lump c.lump wad |> Maybe.andThen dmxSound
                            in
                            ( s, Dict.insert c.lump s audio.cut )

                ( left, right ) =
                    gains c.volume c.separation
            in
            ( { audio | cut = cut }
            , case sound of
                Just s ->
                    [ Effect.PlaySound { voice = c.channel, sound = s, left = left, right = right, speed = 1 } ]

                Nothing ->
                    [ Effect.StopSound c.channel ]
            )

        Audio.UpdateSound c ->
            let
                ( left, right ) =
                    gains c.volume c.separation
            in
            ( audio, [ Effect.SetSound { voice = c.channel, left = left, right = right, speed = 1 } ] )

        Audio.StopSound channel ->
            ( audio, [ Effect.StopSound channel ] )

        Audio.PlayMusic m ->
            case ( Wad.lump m.lump wad, Wad.lump "GENMIDI" wad ) of
                ( Just lump, Just genmidi ) ->
                    let
                        ( midi, converter ) =
                            toMidi audio.converter lump
                    in
                    ( { audio | converter = converter }
                    , case midi of
                        Just song ->
                            -- GENMIDI's lump starts with "#OPL_II#", then the DMX OP2 bank.
                            [ Effect.PlayMidi { song = song, instruments = genmidi, looping = m.looping } ]

                        Nothing ->
                            [ Effect.StopMidi ]
                    )

                _ ->
                    ( audio, [ Effect.StopMidi ] )

        Audio.StopMusic ->
            ( audio, [ Effect.StopMidi ] )

        Audio.PauseMusic ->
            ( audio, [ Effect.PauseMidi True ] )

        Audio.ResumeMusic ->
            ( audio, [ Effect.PauseMidi False ] )

        Audio.MusicVolume v ->
            ( audio, [ Effect.MidiVolume (clamp 0 127 v) ] )

        Audio.SfxVolume _ ->
            -- Already in each sound's volume.
            ( audio, [] )


{-| A music lump as MIDI, as Chocolate Doom's I\_OPL\_RegisterSong reads it: a lump
that is a MIDI file already ("MThd", under 96 KiB; Freedoom's are) as it is, any other
converted from MUS.
-}
toMidi : Midi.Converter -> Bytes -> ( Maybe Bytes, Midi.Converter )
toMidi converter lump =
    if BD.decode (BD.string 4) lump == Just "MThd" && Bytes.width lump < 96 * 1024 then
        ( Just lump, converter )

    else
        Midi.convert converter lump


{-| Chocolate Doom's I\_SDL\_UpdateSoundParams: 0 to 1.
-}
gains : Int -> Int -> ( Float, Float )
gains volume separation =
    let
        vol =
            clamp 0 127 volume

        side v =
            toFloat (clamp 0 255 v) / 255
    in
    ( side (((254 - separation) * vol) // 127), side ((separation * vol) // 127) )


{-| A DMX sound lump as Chocolate Doom's i\_sdlsound.c reads it: format 3, the rate,
the sample count, then unsigned 8-bit samples, of which DMX skips the first and last

1.  Nothing for a lump that isn't like that.

-}
dmxSound : Bytes -> Maybe Effect.Sound
dmxSound lump =
    BD.decode
        (BD.map3 (\format rate length -> ( format, rate, length ))
            (BD.unsignedInt16 Bytes.LE)
            (BD.unsignedInt16 Bytes.LE)
            (BD.unsignedInt32 Bytes.LE)
            |> BD.andThen
                (\( format, rate, length ) ->
                    if format == 3 && rate > 0 && length > 48 && length <= Bytes.width lump - 8 then
                        BD.map2 (\_ samples -> { rate = rate, format = Effect.U8, samples = samples })
                            (BD.bytes 16)
                            (BD.bytes (length - 32))

                    else
                        BD.fail
                )
        )
        lump



-- UI


type UiId
    = Panel
    | Screen
    | CloseButton
    | WadButton String
    | LeaveButton
    | StayButton
    | ControlsButton
    | ActionButton DoomControls.Action
    | ClassicButton
    | ModernButton
    | DoneButton
    | WadsButton
      -- In the WADs panel, by the WAD's place in `sources`.
    | AddressInput Int
    | GetButton Int
    | UsualButton Int
    | RemoveButton Int
    | NewAddressInput
    | AddButton


idToString : UiId -> String
idToString id =
    case id of
        WadsButton ->
            "WadsButton"

        AddressInput n ->
            "AddressInput_" ++ String.fromInt n

        GetButton n ->
            "GetButton_" ++ String.fromInt n

        UsualButton n ->
            "UsualButton_" ++ String.fromInt n

        RemoveButton n ->
            "RemoveButton_" ++ String.fromInt n

        NewAddressInput ->
            "NewAddressInput"

        AddButton ->
            "AddButton"

        ControlsButton ->
            "ControlsButton"

        ActionButton action ->
            "ActionButton_" ++ DoomControls.actionName action

        ClassicButton ->
            "ClassicButton"

        ModernButton ->
            "ModernButton"

        DoneButton ->
            "DoneButton"

        Panel ->
            "Panel"

        Screen ->
            "Screen"

        CloseButton ->
            "CloseButton"

        WadButton path ->
            "WadButton_" ++ path

        LeaveButton ->
            "LeaveButton"

        StayButton ->
            "StayButton"


{-| The toolbar's button: opens the window (and loads the WAD), or closes it.
-}
click : UiId -> Model -> ( Model, List Effect )
click id model =
    case id of
        Panel ->
            ( model, [] )

        Screen ->
            -- The click only captures the pointer: Doom doesn't see it (its button is
            -- up again before the game has the mouse), so it doesn't fire.
            case running model of
                Just r ->
                    if model.captured || not (playing r) then
                        ( model, [] )

                    else
                        ( { model | captured = True }, [ Effect.CapturePointer True ] )

                Nothing ->
                    ( model, [] )

        ControlsButton ->
            withSession
                (\r ->
                    { r
                        | panel =
                            case r.panel of
                                Just _ ->
                                    Nothing

                                Nothing ->
                                    Just { choosing = Nothing }
                    }
                )
                model
                |> release

        ActionButton action ->
            ( withSession (\r -> { r | panel = Just { choosing = Just action } }) model, [] )

        ClassicButton ->
            ( setBindings DoomControls.classic model, [] )

        ModernButton ->
            ( setBindings DoomControls.modern model, [] )

        DoneButton ->
            ( withSession (\r -> { r | panel = Nothing }) model, [] )

        WadsButton ->
            { model | choosing = not model.choosing } |> withSession (\r -> { r | panel = Nothing }) |> release

        AddressInput _ ->
            ( model, [] )

        NewAddressInput ->
            ( model, [] )

        GetButton n ->
            case source n model of
                Just src ->
                    case standing src model of
                        OnDisk path ->
                            if Just path == model.wad && running model /= Nothing then
                                ( { model | choosing = False }, [] )

                            else
                                leave (SwitchTo path) model

                        Getting _ ->
                            ( model, [] )

                        _ ->
                            get src model

                Nothing ->
                    ( model, [] )

        UsualButton n ->
            case List.drop n builtins |> List.head of
                Just b ->
                    ( { model | addresses = Dict.remove b.file model.addresses }, [] )

                Nothing ->
                    ( model, [] )

        RemoveButton n ->
            ( { model | ownWads = List.take (n - List.length builtins) model.ownWads ++ List.drop (n - List.length builtins + 1) model.ownWads }, [] )

        AddButton ->
            let
                address =
                    String.trim model.newAddress
            in
            if address == "" || List.member address (List.map .address (sources model)) then
                ( model, [] )

            else
                ( { model | ownWads = model.ownWads ++ [ address ], newAddress = "" }, [] )

        CloseButton ->
            leave Close model

        WadButton path ->
            if Just path == model.wad && running model /= Nothing then
                ( model, [] )

            else
                leave (SwitchTo path) model

        LeaveButton ->
            case Maybe.andThen .asking (running model) of
                Just leaving ->
                    leaveNow leaving model

                Nothing ->
                    ( model, [] )

        StayButton ->
            ( withSession (\r -> { r | asking = Nothing }) model, [] )


{-| Leaving goes ahead at once on the title pages and demos; a game the player
started is asked about first (and the mouse let go, to answer with).
-}
leave : Leaving -> Model -> ( Model, List Effect )
leave leaving model =
    case running model of
        Just r ->
            if inGame r then
                release (withSession (\r2 -> { r2 | asking = Just leaving }) model)

            else
                leaveNow leaving model

        Nothing ->
            leaveNow leaving model


leaveNow : Leaving -> Model -> ( Model, List Effect )
leaveNow leaving model =
    case leaving of
        SwitchTo path ->
            load { model | wad = Just path, choosing = False }

        Close ->
            close model


{-| The player is in a game they started: not the title pages or a demo.
-}
inGame : Session -> Bool
inGame r =
    Doom.inGame r.doom


withSession : (Session -> Session) -> Model -> Model
withSession f model =
    case running model of
        Just r ->
            { model | game = Transient.wrap (Running (f r)) }

        Nothing ->
            model


{-| The toolbar's button.
-}
focusOn : Model -> ( Model, List Effect )
focusOn model =
    if model.open then
        leave Close model

    else
        load { model | open = True }


close : Model -> ( Model, List Effect )
close model =
    release model
        |> Tuple.mapFirst (\m -> { m | open = False, game = Transient.empty })
        |> Tuple.mapSecond (\effects -> effects ++ Effect.StopMidi :: List.map Effect.StopSound (List.range 0 7))


{-| The window: a title with the WADs to choose from and a close button, and the
game's screen, the biggest whole multiple of 320 x 240 (x by k, y by 1.2 k) that fits
under the toolbar (`top`, UI pixels).
-}
view : UiScale -> Coord DevicePixels -> Int -> Bool -> (UiId -> Maybe TextInput.Model) -> Model -> Ui.Element UiId
view scale screen top focused inputs model =
    let
        font =
            Sprite.Sans Sprite.Regular Sprite.Small

        s =
            Units.scaleInt scale

        ( screenW, screenH ) =
            Coord.toTuple screen

        -- The window's border, padding, title and hint, in device pixels.
        chrome =
            s * (2 * 8 + 2 * 6 + 2 * Quantity.unwrap (Sprite.lineHeight font) + 6)

        k =
            max 1 (min ((screenW - 16 * s) // 320) ((screenH - top * s - 8 * s - chrome) // 240))

        size =
            Coord.xy (320 * k // s) (240 * k // s)

        width =
            Coord.x size

        t =
            Ui.text font

        wads =
            (disk model).wads

        title =
            Ui.leftAndRight width
                (Ui.row { spacing = 6, padding = Ui.noPadding }
                    (t "Doom"
                        :: (if List.length wads > 1 then
                                List.map
                                    (\path -> Ui.selectableButton { id = WadButton path, padding = Ui.paddingXY 6 0 } (Just path == model.wad) (t (wadName path)))
                                    wads

                            else
                                []
                           )
                    )
                )
                (Ui.row { spacing = 6, padding = Ui.noPadding }
                    [ Ui.selectableButton { id = WadsButton, padding = Ui.paddingXY 6 0 } (showsWads model) (t "WADs")
                    , case running model of
                        Just r ->
                            Ui.selectableButton { id = ControlsButton, padding = Ui.paddingXY 6 0 } (r.panel /= Nothing) (t "Controls")

                        Nothing ->
                            Ui.none
                    , Ui.button { id = CloseButton, padding = Ui.paddingXY 6 0 } (t "×")
                    ]
                )

        message text =
            Ui.el { padding = Ui.noPadding, inFront = [], borderAndFill = Ui.FillOnly Color.black }
                (Ui.center { size = size } (Ui.colorText Color.white font text))

        picture =
            if showsWads model then
                wadsPanel font size inputs model

            else
                gamePicture

        gamePicture =
            case Transient.get model.game of
                Just (Running { panel }) ->
                    case panel of
                        Just { choosing } ->
                            controlsPanel font size choosing model.bindings

                        Nothing ->
                            screenPicture

                Just (Failed problem) ->
                    message problem

                Just Loading ->
                    message ("Loading " ++ maybeWadName model ++ "…")

                Nothing ->
                    message ""

        screenPicture =
            case Transient.get model.game of
                Just (Running r) ->
                    -- A button, so a click on it captures the pointer (`click`).
                    Ui.customButton
                        { id = Screen
                        , padding = Ui.noPadding
                        , inFront = []
                        , borderAndFill = Ui.NoBorderOrFill
                        , borderAndFillFocus = Ui.NoBorderOrFill
                        }
                        (Ui.picture
                            { size = size
                            , width = Video.width
                            , height = Video.height
                            , format = Scene.Indexed r.palette.bytes
                            , pixels = r.shown.pixels
                            }
                        )

                Just (Failed problem) ->
                    message problem

                Just Loading ->
                    message ("Loading " ++ maybeWadName model ++ "…")

                Nothing ->
                    message ""

        asking =
            Maybe.andThen .asking (running model)

        question leaving =
            Ui.leftAndRight width
                (t
                    (case leaving of
                        SwitchTo path ->
                            "Switch to " ++ wadName path ++ "? The game in progress will be lost."

                        Close ->
                            "Close Doom? The game in progress will be lost."
                    )
                )
                (Ui.row { spacing = 6, padding = Ui.noPadding }
                    [ Ui.button { id = LeaveButton, padding = Ui.paddingXY 6 0 }
                        (t
                            (case leaving of
                                SwitchTo _ ->
                                    "Switch"

                                Close ->
                                    "Close"
                            )
                        )
                    , Ui.button { id = StayButton, padding = Ui.paddingXY 6 0 } (t "Keep playing")
                    ]
                )

        hint =
            Ui.leftAndRight width
                (Ui.colorText Color.outlineColor
                    font
                    (case ( showsWads model, running model ) of
                        ( True, _ ) ->
                            if model.dataDir == Nothing then
                                "Downloads need a data disk"

                            else
                                "Downloads go to the data disk's doom/ folder"

                        ( False, Just r ) ->
                            case Maybe.map .choosing r.panel of
                                Just (Just action) ->
                                    case DoomControls.input action of
                                        DoomControls.Key ->
                                            "Press a key (Esc: cancel, Backspace: none)"

                                        DoomControls.Button ->
                                            "Click a mouse button (Esc: cancel)"

                                Just Nothing ->
                                    "Click an action, then its new key"

                                Nothing ->
                                    if model.captured then
                                        "Esc lets the mouse go"

                                    else if not focused then
                                        "Click the game to play"

                                    else if playing r then
                                        "Click the game for the mouse"

                                    else
                                        "Esc: Doom's menu"

                        ( False, Nothing ) ->
                            "Click the game to play"
                    )
                )
                (Ui.colorText Color.outlineColor
                    font
                    (case model.wad of
                        Just path ->
                            lastPart path

                        Nothing ->
                            ""
                    )
                )
    in
    Ui.elWithId Panel
        { padding = Ui.paddingXY 8 8
        , inFront = []
        , borderAndFill =
            Ui.BorderAndFill
                { borderWidth = 2
                , borderColor =
                    if focused then
                        Color.focusedUiColor

                    else
                        Color.outlineColor
                , fillColor = Color.fillColor
                }
        }
        (Ui.column { spacing = 6, padding = Ui.noPadding }
            [ title
            , picture
            , case asking of
                Just leaving ->
                    question leaving

                Nothing ->
                    hint
            ]
        )


{-| The WADs panel shows when the player opens it, while there's no WAD to play, and
when the WAD couldn't be started (it says why).
-}
showsWads : Model -> Bool
showsWads model =
    model.choosing
        || model.wad
        == Nothing
        || (case Transient.get model.game of
                Just (Failed _) ->
                    True

                _ ->
                    False
           )


maybeWadName : Model -> String
maybeWadName model =
    Maybe.map wadName model.wad |> Maybe.withDefault ""


{-| The WADs panel, in the picture's place (`size`): each WAD with what it is, a
button to download or play it, and its address, which the player can change; then a
box for an address of their own.
-}
wadsPanel : Sprite.Font -> Coord Units.UiPixels -> (UiId -> Maybe TextInput.Model) -> Model -> Ui.Element UiId
wadsPanel font size inputs model =
    let
        t =
            Ui.text font

        dim =
            Ui.colorText Color.outlineColor font

        gap =
            10

        width =
            Quantity.unwrap (Coord.x size) - 2 * gap

        box id =
            Ui.textInput
                { id = id
                , style = { font = font, width = Quantity.unsafe width, masked = False }
                , isValid = True
                , state = inputState id (inputs id) model
                }

        small id label =
            Ui.button { id = id, padding = Ui.paddingXY 6 0 } (t label)

        row n src =
            let
                ( note, action ) =
                    case standing src model of
                        OnDisk path ->
                            ( "On the disk"
                            , if Just path == model.wad && running model /= Nothing then
                                Ui.selectableButton { id = GetButton n, padding = Ui.paddingXY 6 0 } True (t "Playing")

                              else
                                small (GetButton n) "Play"
                            )

                        Getting what ->
                            ( what, Ui.none )

                        GotStuck why ->
                            ( "Failed: " ++ why, small (GetButton n) "Try again" )

                        NotHere ->
                            ( if src.sha256 == Nothing then
                                "Not checked: from an address of your own"

                              else
                                ""
                            , if model.dataDir == Nothing then
                                Ui.none

                              else
                                small (GetButton n) "Download"
                            )

                extra =
                    if src.usual == Nothing then
                        small (RemoveButton n) "Remove"

                    else if src.sha256 == Nothing then
                        small (UsualButton n) "Usual address"

                    else
                        Ui.none
            in
            Ui.column { spacing = 2, padding = Ui.noPadding }
                [ Ui.leftAndRight (Quantity.unsafe width)
                    (Ui.row { spacing = 8, padding = Ui.noPadding } [ t src.name, dim note ])
                    (Ui.row { spacing = 6, padding = Ui.noPadding } [ extra, action ])
                , box (AddressInput n)
                ]

        problem =
            case Transient.get model.game of
                Just (Failed why) ->
                    [ Ui.colorText Color.errorColor font (maybeWadName model ++ ": " ++ why) ]

                _ ->
                    []
    in
    Ui.el { padding = Ui.noPadding, inFront = [], borderAndFill = Ui.FillOnly Color.fillColor2 }
        (Ui.topLeft { size = size }
            (Ui.column { spacing = 8, padding = Ui.paddingXY gap gap }
                (problem
                    ++ List.indexedMap row (sources model)
                    ++ [ Ui.column { spacing = 2, padding = Ui.noPadding }
                            [ Ui.leftAndRight (Quantity.unsafe width) (t "A WAD (or a zip with one) from an address of your own") (small AddButton "Add")
                            , box NewAddressInput
                            ]
                       ]
                )
            )
        )


{-| The Controls panel, in the picture's place (`size`): the keyboard's actions on
the left, the mouse's and the presets on the right, each action a button with its
key, highlighted while it waits for a new one.
-}
controlsPanel : Sprite.Font -> Coord Units.UiPixels -> Maybe DoomControls.Action -> DoomControls.Bindings -> Ui.Element UiId
controlsPanel font size choosing bindings =
    let
        t =
            Ui.text font

        gap =
            12

        columnWidth =
            (Quantity.unwrap (Coord.x size) - 2 * gap - gap) // 2

        actionButton action =
            Ui.selectableButton { id = ActionButton action, padding = Ui.paddingXY 6 0 }
                (choosing == Just action)
                (Ui.leftAndRight (Quantity.unsafe (columnWidth - 2 * 6 - 2 * 2))
                    (t (DoomControls.actionName action))
                    (t (DoomControls.bindingName action bindings))
                )

        ( keys, buttons ) =
            List.partition (\action -> DoomControls.input action == DoomControls.Key) DoomControls.actions

        preset id label selected =
            Ui.selectableButton { id = id, padding = Ui.paddingXY 6 0 } selected (t label)
    in
    Ui.el { padding = Ui.noPadding, inFront = [], borderAndFill = Ui.FillOnly Color.fillColor2 }
        (Ui.topLeft { size = size }
            (Ui.row { spacing = gap, padding = Ui.paddingXY gap gap }
                [ Ui.column { spacing = 2, padding = Ui.noPadding } (List.map actionButton keys)
                , Ui.column { spacing = 2, padding = Ui.noPadding }
                    (List.map actionButton buttons
                        ++ [ Ui.el { padding = Ui.paddingXY 0 6, inFront = [], borderAndFill = Ui.NoBorderOrFill } (t "Presets")
                           , Ui.row { spacing = 6, padding = Ui.noPadding }
                                [ preset ClassicButton "Classic (DOS)" (bindings == DoomControls.classic)
                                , preset ModernButton "Modern (WASD)" (bindings == DoomControls.modern)
                                ]
                           , Ui.el { padding = Ui.paddingXY 0 6, inFront = [], borderAndFill = Ui.NoBorderOrFill } Ui.none
                           , Ui.button { id = DoneButton, padding = Ui.paddingXY 6 0 } (t "Done")
                           ]
                    )
                ]
            )
        )


{-| v\_video.c's gammatable: the five levels of gamma correction (F11).
-}
gammaTable : Array (Array Int)
gammaTable =
    [ [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255 ]
    , [ 2, 4, 5, 7, 8, 10, 11, 12, 14, 15, 16, 18, 19, 20, 21, 23, 24, 25, 26, 27, 29, 30, 31, 32, 33, 34, 36, 37, 38, 39, 40, 41, 42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 214, 215, 216, 217, 218, 219, 220, 221, 222, 222, 223, 224, 225, 226, 227, 228, 229, 230, 230, 231, 232, 233, 234, 235, 236, 237, 237, 238, 239, 240, 241, 242, 243, 244, 245, 245, 246, 247, 248, 249, 250, 251, 252, 252, 253, 254, 255 ]
    , [ 4, 7, 9, 11, 13, 15, 17, 19, 21, 22, 24, 26, 27, 29, 30, 32, 33, 35, 36, 38, 39, 40, 42, 43, 45, 46, 47, 48, 50, 51, 52, 54, 55, 56, 57, 59, 60, 61, 62, 63, 65, 66, 67, 68, 69, 70, 72, 73, 74, 75, 76, 77, 78, 79, 80, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 153, 154, 155, 156, 157, 158, 159, 160, 160, 161, 162, 163, 164, 165, 166, 166, 167, 168, 169, 170, 171, 172, 172, 173, 174, 175, 176, 177, 178, 178, 179, 180, 181, 182, 183, 183, 184, 185, 186, 187, 188, 188, 189, 190, 191, 192, 193, 193, 194, 195, 196, 197, 197, 198, 199, 200, 201, 201, 202, 203, 204, 205, 206, 206, 207, 208, 209, 210, 210, 211, 212, 213, 213, 214, 215, 216, 217, 217, 218, 219, 220, 221, 221, 222, 223, 224, 224, 225, 226, 227, 228, 228, 229, 230, 231, 231, 232, 233, 234, 235, 235, 236, 237, 238, 238, 239, 240, 241, 241, 242, 243, 244, 244, 245, 246, 247, 247, 248, 249, 250, 251, 251, 252, 253, 254, 254, 255 ]
    , [ 8, 12, 16, 19, 22, 24, 27, 29, 31, 34, 36, 38, 40, 41, 43, 45, 47, 49, 50, 52, 53, 55, 57, 58, 60, 61, 63, 64, 65, 67, 68, 70, 71, 72, 74, 75, 76, 77, 79, 80, 81, 82, 84, 85, 86, 87, 88, 90, 91, 92, 93, 94, 95, 96, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 135, 136, 137, 138, 139, 140, 141, 142, 143, 143, 144, 145, 146, 147, 148, 149, 150, 150, 151, 152, 153, 154, 155, 155, 156, 157, 158, 159, 160, 160, 161, 162, 163, 164, 165, 165, 166, 167, 168, 169, 169, 170, 171, 172, 173, 173, 174, 175, 176, 176, 177, 178, 179, 180, 180, 181, 182, 183, 183, 184, 185, 186, 186, 187, 188, 189, 189, 190, 191, 192, 192, 193, 194, 195, 195, 196, 197, 197, 198, 199, 200, 200, 201, 202, 202, 203, 204, 205, 205, 206, 207, 207, 208, 209, 210, 210, 211, 212, 212, 213, 214, 214, 215, 216, 216, 217, 218, 219, 219, 220, 221, 221, 222, 223, 223, 224, 225, 225, 226, 227, 227, 228, 229, 229, 230, 231, 231, 232, 233, 233, 234, 235, 235, 236, 237, 237, 238, 238, 239, 240, 240, 241, 242, 242, 243, 244, 244, 245, 246, 246, 247, 247, 248, 249, 249, 250, 251, 251, 252, 253, 253, 254, 254, 255 ]
    , [ 16, 23, 28, 32, 36, 39, 42, 45, 48, 50, 53, 55, 57, 60, 62, 64, 66, 68, 69, 71, 73, 75, 76, 78, 80, 81, 83, 84, 86, 87, 89, 90, 92, 93, 94, 96, 97, 98, 100, 101, 102, 103, 105, 106, 107, 108, 109, 110, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 128, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 143, 144, 145, 146, 147, 148, 149, 150, 150, 151, 152, 153, 154, 155, 155, 156, 157, 158, 159, 159, 160, 161, 162, 163, 163, 164, 165, 166, 166, 167, 168, 169, 169, 170, 171, 172, 172, 173, 174, 175, 175, 176, 177, 177, 178, 179, 180, 180, 181, 182, 182, 183, 184, 184, 185, 186, 187, 187, 188, 189, 189, 190, 191, 191, 192, 193, 193, 194, 195, 195, 196, 196, 197, 198, 198, 199, 200, 200, 201, 202, 202, 203, 203, 204, 205, 205, 206, 207, 207, 208, 208, 209, 210, 210, 211, 211, 212, 213, 213, 214, 214, 215, 216, 216, 217, 217, 218, 219, 219, 220, 220, 221, 221, 222, 223, 223, 224, 224, 225, 225, 226, 227, 227, 228, 228, 229, 229, 230, 230, 231, 232, 232, 233, 233, 234, 234, 235, 235, 236, 236, 237, 237, 238, 239, 239, 240, 240, 241, 241, 242, 242, 243, 243, 244, 244, 245, 245, 246, 246, 247, 247, 248, 248, 249, 249, 250, 250, 251, 251, 252, 252, 253, 254, 254, 255, 255 ]
    ]
        |> List.map Array.fromList
        |> Array.fromList
