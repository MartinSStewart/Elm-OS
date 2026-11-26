module History exposing
    ( Context
    , Head
    , Model
    , Request
    , appSize
    , gotResponse
    , init
    , onClick
    , parseTime
    , relativeTime
    , requestId
    , testFact
    , view
    )

{-| The History app: Elm OS's commits drawn as a graph, like a git GUI does, to see which
version this computer runs and whether newer ones are waiting.

The computer has no git history, only the commit its build was made from
(BuildInfo.commit). The commits come from GitHub's API (the repository is public, so no
token), for each branch that matters: `main`, `deployed` (the newest build CI has tested
and published, which computers follow, see host/init/src/update.rs) and `dev`, and the
branch the Code app pushed its edits to, if any. The edits it has saved but not pushed
are drawn as a commit on top, "Uncommitted changes".

History.Graph lays the commits out in lanes.

-}

import App
import Bytes exposing (Bytes)
import Color exposing (Color)
import Coord
import Date
import Duration
import Effect exposing (Effect)
import History.Graph as Graph exposing (Row)
import History.Types exposing (Commit, UiId(..))
import Json.Decode as D
import Json.Encode as E
import Quantity
import SeqDict exposing (SeqDict)
import Set exposing (Set)
import Sprite exposing (Triangle)
import Time
import Ui
import UiId
import Units exposing (UiPixels)


type alias Model =
    { isOpen : Bool

    -- Which refresh the answers being waited for belong to.
    , generation : Int

    -- The branches of the refresh that haven't answered yet, by their place in the list.
    , waiting : List ( Int, String )

    -- Where each branch was at its last answer.
    , heads : List Head

    -- Every commit seen so far, by hash. A commit never changes, so these are kept
    -- when a refresh fails or finds fewer.
    , commits : SeqDict String Commit

    -- What went wrong with the last refresh, if something did.
    , error : Maybe String
    }


type alias Head =
    { name : String, sha : String }


init : Model
init =
    { isOpen = False
    , generation = 0
    , waiting = []
    , heads = []
    , commits = SeqDict.empty
    , error = Nothing
    }


{-| What the app shows besides its own Model: the commit the running build was made from
("" if it wasn't from a commit), the commit the Code app's next commit goes on top of
("" if none), the modules it has saved but not committed, and the time.
-}
type alias Context =
    { running : String
    , base : String
    , uncommitted : List String
    , now : Maybe Time.Posix
    }


repository : String
repository =
    "MartinSStewart/Elm-OS"


{-| How many commits are asked for of each branch.
-}
perBranch : Int
perBranch =
    50


{-| The id of the request for the branch in place `i` of refresh `generation`, for Main's
HttpRequestId.
-}
requestId : Int -> Int -> String
requestId generation i =
    "history_" ++ String.fromInt generation ++ "_" ++ String.fromInt i


onClick : UiId -> Request -> Model -> ( Model, List Effect )
onClick id request model =
    case id of
        OpenButton ->
            if model.isOpen then
                ( { model | isOpen = False }, [] )

            else
                refresh request { model | isOpen = True }

        CloseButton ->
            ( { model | isOpen = False }, [] )

        RefreshButton ->
            refresh request model

        ListViewport ->
            ( model, [] )


{-| What a refresh needs: branches besides the usual three, and a GitHub token ("" if
none). Without one GitHub allows only 60 requests an hour per IP address, and each refresh
makes one request per branch; with one, 5000.
-}
type alias Request =
    { branches : List String, token : String }


{-| Asks GitHub for the newest commits of each branch. What is shown stays until the
answers come.
-}
refresh : Request -> Model -> ( Model, List Effect )
refresh { branches, token } model =
    let
        allBranches : List String
        allBranches =
            List.foldl
                (\branch sofar ->
                    if branch == "" || List.member branch sofar then
                        sofar

                    else
                        sofar ++ [ branch ]
                )
                [ "main", "deployed", "dev" ]
                branches

        generation : Int
        generation =
            model.generation + 1
    in
    ( { model
        | generation = generation
        , waiting = List.indexedMap (\i branch -> ( i, branch )) allBranches
        , error = Nothing
      }
    , List.indexedMap
        (\i branch ->
            Effect.Http
                { id = requestId generation i
                , method = "GET"
                , url = "https://api.github.com/repos/" ++ repository ++ "/commits?per_page=" ++ String.fromInt perBranch ++ "&sha=" ++ branch
                , headers =
                    ( "Accept", "application/vnd.github+json" )
                        :: (if token == "" then
                                []

                            else
                                [ ( "Authorization", "Bearer " ++ token ) ]
                           )
                , body = Effect.noBody
                , timeoutMs = Just (Duration.seconds 30)
                }
        )
        allBranches
    )


{-| GitHub's answer to request `i` of refresh `generation`. Answers to an older refresh
change nothing.
-}
gotResponse : Int -> Int -> Result Effect.HttpError { status : Int, body : Bytes } -> Model -> Model
gotResponse generation i result model =
    if generation /= model.generation then
        model

    else
        case List.filter (\( j, _ ) -> j == i) model.waiting of
            ( _, branch ) :: _ ->
                let
                    model2 : Model
                    model2 =
                        { model | waiting = List.filter (\( j, _ ) -> j /= i) model.waiting }
                in
                case answer result of
                    Ok commits ->
                        { model2
                            | heads =
                                case commits of
                                    newest :: _ ->
                                        List.filter (\head -> head.name /= branch) model2.heads
                                            ++ [ { name = branch, sha = newest.sha } ]

                                    [] ->
                                        model2.heads
                            , commits =
                                List.foldl (\commit all -> SeqDict.insert commit.sha commit all) model2.commits commits
                        }

                    Err why ->
                        { model2
                            | error =
                                case model2.error of
                                    Just earlier ->
                                        Just earlier

                                    Nothing ->
                                        Just ("Couldn't load " ++ branch ++ ": " ++ why)
                        }

            [] ->
                model


answer : Result Effect.HttpError { status : Int, body : Bytes } -> Result String (List Commit)
answer result =
    case result of
        Ok response ->
            if response.status >= 200 && response.status < 300 then
                case Effect.bodyToString response.body of
                    Just text ->
                        D.decodeString decodeCommits text |> Result.mapError D.errorToString

                    Nothing ->
                        Err "the answer isn't text"

            else if response.status == 403 || response.status == 429 then
                Err "GitHub's limit on requests was reached (60 an hour without a token, 5000 with one). Type a GitHub token in the Code app's commit view, or try again in up to an hour."

            else
                Err ("GitHub said " ++ String.fromInt response.status)

        Err (Effect.NetworkError why) ->
            -- What the host said, which tells a missing network from a refused one.
            Err ("couldn't reach GitHub (" ++ why ++ "). Is Elm OS online? The Network app connects it.")

        Err error ->
            Err (Effect.httpErrorToString error)


decodeCommits : D.Decoder (List Commit)
decodeCommits =
    D.list
        (D.map5
            (\sha parents message author date ->
                let
                    ( subject, description ) =
                        splitMessage message
                in
                { sha = sha
                , parents = parents
                , subject = subject
                , description = description
                , author = author
                , time = Maybe.withDefault 0 (parseTime date)
                }
            )
            (D.field "sha" D.string)
            (D.field "parents" (D.list (D.field "sha" D.string)))
            (D.at [ "commit", "message" ] D.string)
            (D.at [ "commit", "author", "name" ] D.string)
            (D.at [ "commit", "committer", "date" ] D.string)
        )


{-| A commit message's first line, and the rest of it on one line.
-}
splitMessage : String -> ( String, String )
splitMessage message =
    case String.lines (String.trim message) of
        [] ->
            ( "", "" )

        first :: rest ->
            ( first
            , rest
                |> List.map String.trim
                |> List.filter (\text -> text /= "")
                |> String.join " | "
                |> String.left 300
            )


{-| Seconds since 1970 of a time as GitHub writes it: "2026-11-26T13:54:33Z".
-}
parseTime : String -> Maybe Int
parseTime text =
    case Date.fromIsoString (String.left 10 text) of
        Ok date ->
            Maybe.map3
                (\hours minutes seconds ->
                    (Date.toRataDie date - 719163) * 86400 + hours * 3600 + minutes * 60 + seconds
                )
                (String.toInt (String.slice 11 13 text))
                (String.toInt (String.slice 14 16 text))
                (String.toInt (String.slice 17 19 text))

        Err _ ->
            Nothing


{-| How long before `now` (in seconds since 1970) a time was, in words.
-}
relativeTime : Int -> Int -> String
relativeTime now then_ =
    let
        seconds : Int
        seconds =
            max 0 (now - then_)

        unit : Int -> String -> String
        unit count name =
            String.fromInt count
                ++ " "
                ++ name
                ++ (if count == 1 then
                        ""

                    else
                        "s"
                   )
                ++ " ago"
    in
    if seconds < 60 then
        "just now"

    else if seconds < 3600 then
        unit (seconds // 60) "minute"

    else if seconds < 86400 then
        unit (seconds // 3600) "hour"

    else if seconds < 30 * 86400 then
        unit (seconds // 86400) "day"

    else if seconds < 365 * 86400 then
        unit (seconds // (30 * 86400)) "month"

    else
        unit (seconds // (365 * 86400)) "year"



-- WHAT THE COMMITS SAY


{-| The hashes of a commit and everything before it, among the commits known.
-}
ancestors : SeqDict String Commit -> String -> Set String
ancestors commits start =
    collect commits [ start ] Set.empty


collect : SeqDict String Commit -> List String -> Set String -> Set String
collect commits todo seen =
    case todo of
        [] ->
            seen

        sha :: rest ->
            if Set.member sha seen then
                collect commits rest seen

            else
                case SeqDict.get sha commits of
                    Just commit ->
                        collect commits (commit.parents ++ rest) (Set.insert sha seen)

                    Nothing ->
                        collect commits rest seen


{-| Where the running version stands against a branch.
-}
standing : SeqDict String Commit -> String -> Head -> String
standing commits running head =
    let
        fromHead : Set String
        fromHead =
            ancestors commits head.sha

        fromRunning : Set String
        fromRunning =
            ancestors commits running
    in
    if head.sha == running then
        head.name ++ ": this is the newest"

    else if Set.member running fromHead then
        let
            newer : Int
            newer =
                Set.size (Set.diff fromHead fromRunning)
        in
        head.name ++ ": " ++ String.fromInt newer ++ " newer commit" ++ plural newer ++ " waiting"

    else if Set.member head.sha fromRunning then
        head.name ++ ": older than this version"

    else
        head.name ++ ": on another line of commits than this version"


plural : Int -> String
plural count =
    if count == 1 then
        ""

    else
        "s"


short : String -> String
short sha =
    String.left 7 sha


summary : Context -> Model -> List ( String, Color )
summary context model =
    let
        nowSeconds : Maybe Int
        nowSeconds =
            Maybe.map (\now -> Time.posixToMillis now // 1000) context.now

        running : List ( String, Color )
        running =
            if context.running == "" then
                [ ( "This build was made from code that isn't committed, so its version isn't known.", Color.dimTextColor ) ]

            else
                case SeqDict.get context.running model.commits of
                    Just commit ->
                        ( "Running " ++ short commit.sha ++ ": " ++ commit.subject ++ ", " ++ timeText nowSeconds commit.time
                        , Color.textColor
                        )
                            :: List.filterMap
                                (\name ->
                                    List.filter (\head -> head.name == name) model.heads
                                        |> List.head
                                        |> Maybe.map (\head -> ( standing model.commits context.running head, Color.dimTextColor ))
                                )
                                [ "deployed", "main" ]

                    Nothing ->
                        [ ( "Running " ++ short context.running
                          , Color.textColor
                          )
                        , ( if SeqDict.isEmpty model.commits then
                                ""

                            else
                                "That commit isn't among the newest " ++ String.fromInt perBranch ++ " of each branch."
                          , Color.dimTextColor
                          )
                        ]

        status : List ( String, Color )
        status =
            case model.error of
                Just error ->
                    [ ( error, Color.errorColor ) ]

                Nothing ->
                    if List.isEmpty model.waiting then
                        []

                    else
                        [ ( "Loading from GitHub…", Color.dimTextColor ) ]
    in
    List.filter (\( text, _ ) -> text /= "") (running ++ status)


timeText : Maybe Int -> Int -> String
timeText nowSeconds then_ =
    case nowSeconds of
        Just now ->
            relativeTime now then_

        Nothing ->
            ""



-- VIEW


appSize : App.Limits
appSize =
    { min = ( App.em 40, Units.ui 260 )
    , preferred = ( App.em 72, Units.ui 520 )
    , max = ( App.em 120, Units.ui 900 )
    }


view : Context -> Model -> Coord.Coord UiPixels -> Ui.Element UiId.UiId
view context model size =
    App.smallWindow2
        { title = "Git History", close = UiId.History CloseButton }
        (body context model)
        { width = Just (Coord.xRaw size), height = Just (Coord.yRaw size) }


small : Ui.Padding
small =
    Ui.paddingXY 6 3


body : Context -> Model -> Ui.TargetSize -> Ui.Element UiId.UiId
body context model =
    Ui.column2 8
        [ ( Ui.Shrink2
          , Ui.row2 8
                [ ( Ui.Fill2
                  , Ui.column2 2
                        (List.map
                            (\( text, color ) -> ( Ui.Shrink2, Ui.ellipsisText2 { color = color, font = App.sans } text ))
                            (summary context model)
                        )
                  )
                , ( Ui.Shrink2, Ui.button2 { id = UiId.History RefreshButton, pad = small } (Ui.text2 "Refresh") )
                ]
          )
        , ( Ui.Fill2
          , if SeqDict.isEmpty model.commits && List.isEmpty context.uncommitted then
                Ui.text2 "No commits yet."

            else
                Ui.viewport2 (UiId.History ListViewport) (graph context model)
          )
        ]


{-| The commits at the top of the list: uncommitted changes, as a commit nothing is on
top of.
-}
uncommittedSha : String
uncommittedSha =
    "uncommitted"


graph : Context -> Model -> Ui.TargetSize -> Ui.Element UiId.UiId
graph context model target =
    let
        uncommitted : List Commit
        uncommitted =
            if List.isEmpty context.uncommitted then
                []

            else
                [ { sha = uncommittedSha
                  , parents =
                        if context.base /= "" then
                            [ context.base ]

                        else if context.running /= "" then
                            [ context.running ]

                        else
                            []
                  , subject = "Uncommitted changes"
                  , description = String.join ", " context.uncommitted
                  , author = ""
                  , time = 9999999999
                  }
                ]

        rows : List Row
        rows =
            Graph.layout (uncommitted ++ SeqDict.values model.commits)

        lanes : Int
        lanes =
            Graph.laneCount rows

        nowSeconds : Maybe Int
        nowSeconds =
            Maybe.map (\now -> Time.posixToMillis now // 1000) context.now
    in
    Ui.column2 0
        (List.map (\row -> ( Ui.Shrink2, rowView context model nowSeconds lanes row )) rows)
        target


rowHeight : Int
rowHeight =
    26


laneWidth : Int
laneWidth =
    16


refsWidth : Int
refsWidth =
    150


timeWidth : Int
timeWidth =
    96


rowView : Context -> Model -> Maybe Int -> Int -> Row -> Ui.TargetSize -> Ui.Element UiId.UiId
rowView context model nowSeconds lanes row =
    let
        commit : Commit
        commit =
            row.commit

        isRunning : Bool
        isRunning =
            commit.sha == context.running

        textTop : Int
        textTop =
            (rowHeight - Quantity.unwrap (Sprite.lineHeight Sprite.Small)) // 2

        padded : Ui.Element UiId.UiId -> Ui.Element UiId.UiId
        padded =
            Ui.el { pad = { top = textTop, bottom = 0, left = 0, right = 0 }, style = Ui.NoBorderOrFill }
    in
    Ui.el2
        { pad = Ui.noPadding
        , style =
            if isRunning then
                Ui.FillOnly Color.historyRunningRowColor

            else
                Ui.NoBorderOrFill
        }
        (Ui.row2 8
            [ ( Ui.Shrink2
              , \_ -> Ui.left (Units.ui refsWidth) (padded (tags context model row))
              )
            , ( Ui.Shrink2, \_ -> graphCell lanes row )
            , ( Ui.Fill2, \target -> Ui.fixed2 (padded (messageCell commit target)) target )
            , ( Ui.Shrink2
              , \_ ->
                    Ui.right { width = Units.ui timeWidth }
                        (padded
                            (Ui.colorText Color.dimTextColor
                                (if commit.sha == uncommittedSha then
                                    ""

                                 else
                                    timeText nowSeconds commit.time
                                )
                            )
                        )
              )
            ]
        )


{-| The branch names at a commit, and "running" and "uncommitted".
-}
tags : Context -> Model -> Row -> Ui.Element UiId.UiId
tags context model row =
    let
        sha : String
        sha =
            row.commit.sha

        laneColor : Color
        laneColor =
            Color.historyLaneColor row.lane

        tag : Color -> String -> Ui.Element UiId.UiId
        tag color name =
            Ui.el
                { pad = Ui.paddingXY 4 0
                , style = Ui.BorderAndFill { borderWidth = 1, borderColor = color, fillColor = Color.fillColor }
                }
                (Ui.colorText color (Sprite.ellipsis Sprite.Small App.sans (Units.ui 90) name))
    in
    Ui.row 3
        (List.filterMap
            (\head ->
                if head.sha == sha then
                    Just (tag laneColor head.name)

                else
                    Nothing
            )
            model.heads
            ++ (if sha == context.running then
                    [ tag Color.successColor "running" ]

                else
                    []
               )
            ++ (if sha == uncommittedSha then
                    [ tag Color.errorColor "uncommitted" ]

                else
                    []
               )
        )


{-| The subject, and the rest of the message dimmer after it, cut to fit.
-}
messageCell : Commit -> Ui.TargetSize -> Ui.Element UiId.UiId
messageCell commit target =
    let
        width : Int
        width =
            Maybe.withDefault 400 target.width

        subject : String
        subject =
            Sprite.ellipsis Sprite.Small App.sans (Units.ui width) commit.subject

        left : Int
        left =
            width - Coord.xRaw (Sprite.textSize Sprite.Small App.sans subject) - 10

        description : String
        description =
            if subject /= commit.subject || commit.description == "" || left < 40 then
                ""

            else
                Sprite.ellipsis Sprite.Small App.sans (Units.ui left) commit.description
    in
    Ui.customText
        Sprite.Small
        [ { text = subject, color = Color.textColor, font = App.sans, decorations = [], link = Nothing }
        , { text = "   " ++ description, color = Color.dimTextColor, font = App.sans, decorations = [], link = Nothing }
        ]


{-| This row's piece of the graph: lines through, into and out of the commit, and its dot.
-}
graphCell : Int -> Row -> Ui.Element UiId.UiId
graphCell lanes row =
    let
        x : Int -> Float
        x n =
            toFloat (n * laneWidth + laneWidth // 2)

        height : Float
        height =
            toFloat rowHeight

        middle : Float
        middle =
            height / 2

        isUncommitted : Bool
        isUncommitted =
            row.commit.sha == uncommittedSha

        dot : List (Triangle UiPixels)
        dot =
            Sprite.circle (Color.historyLaneColor row.lane) 1 ( x row.lane, middle ) 5
                ++ (if isUncommitted || List.length row.commit.parents > 1 then
                        -- A hole: nothing was committed, or this commit merges lines.
                        Sprite.circle Color.fillColor 1 ( x row.lane, middle ) 2.5

                    else
                        []
                   )
    in
    Ui.quads
        { size = Coord.xy (lanes * laneWidth) rowHeight
        , triangles =
            List.concatMap (\through -> segment (Color.historyLaneColor through) ( x through, 0 ) ( x through, height )) row.through
                ++ List.concatMap (\from -> segment (Color.historyLaneColor from) ( x from, 0 ) ( x row.lane, middle )) row.incoming
                ++ List.concatMap (\to -> segment (Color.historyLaneColor to) ( x row.lane, middle ) ( x to, height )) row.outgoing
                ++ dot
        }


{-| A line two pixels thick, as two triangles.
-}
segment : Color -> ( Float, Float ) -> ( Float, Float ) -> List (Triangle UiPixels)
segment color ( startX, startY ) ( endX, endY ) =
    let
        dx : Float
        dx =
            endX - startX

        dy : Float
        dy =
            endY - startY

        length : Float
        length =
            sqrt (dx * dx + dy * dy)

        -- Half the thickness along the line's normal.
        nx : Float
        nx =
            -dy / length

        ny : Float
        ny =
            dx / length
    in
    if length == 0 then
        []

    else
        [ Sprite.triangle color ( startX + nx, startY + ny ) ( startX - nx, startY - ny ) ( endX - nx, endY - ny )
        , Sprite.triangle color ( startX + nx, startY + ny ) ( endX - nx, endY - ny ) ( endX + nx, endY + ny )
        ]


testFact : Model -> E.Value
testFact model =
    E.object
        [ ( "commits", E.int (SeqDict.size model.commits) )
        , ( "heads", E.list (\head -> E.string (head.name ++ " " ++ head.sha)) model.heads )
        , ( "loading", E.bool (not (List.isEmpty model.waiting)) )
        , ( "error", E.string (Maybe.withDefault "" model.error) )
        ]
