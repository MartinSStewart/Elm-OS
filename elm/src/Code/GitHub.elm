module Code.GitHub exposing
    ( Answer(..)
    , containsCheck
    , containsCheckId
    , init
    , requestId
    , respond
    , start
    , startingPoint
    )

{-| Commits the Code app's saved modules to Elm OS's repository on GitHub and pushes
them, with GitHub's REST API (its "Git database" part), so no git is needed here:

1.  GET the commit to build on, for its tree;
2.  POST a tree: that tree with the modules' new text in it;
3.  POST a commit of the new tree, on top of that commit;
4.  PATCH the branch to the new commit, as a fast-forward only. If the branch has moved
    on meanwhile, GitHub refuses, and
5.  POST a new branch, elmos-edits-<commit>, for the commit instead.

Each step is one request with the token in it; its answer gives the next.

-}

import BuildInfo
import Bytes.Encode as BE
import Code.Types exposing (Git, GitStatus(..), GitStep(..), GitWork)
import Duration
import Effect exposing (HttpRequest)
import Json.Decode as D
import Json.Encode as E
import SeqDict exposing (SeqDict)


{-| Elm OS's repository.
-}
repository : String
repository =
    "MartinSStewart/Elm-OS"


init : Git
init =
    { base = "", branch = "", from = "", pushed = SeqDict.empty, status = GitIdle, requests = 0 }


{-| The commit the next one goes on top of, and its branch: the last push's while Elm
OS runs a build of the same commit as then, otherwise the one this build was made from.
"" for the commit when there is none (the build was made from code that wasn't
committed).
-}
startingPoint : Git -> ( String, String )
startingPoint git =
    if git.base /= "" && git.from == BuildInfo.commit then
        ( git.base, git.branch )

    else
        ( BuildInfo.commit, BuildInfo.branch )


{-| The request id of the check whether `deployed` has got to `commit`.
-}
containsCheckId : String
containsCheckId =
    "codecheck"


{-| A request for how the `deployed` branch stands against `commit` (the compare API): its
"status" says "ahead" or "identical" when deployed has that commit.
-}
containsCheck : String -> String -> HttpRequest
containsCheck token commit =
    { id = containsCheckId
    , method = "GET"
    , url = "https://api.github.com/repos/" ++ repository ++ "/compare/" ++ commit ++ "...deployed"
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


{-| The id of request number `n`, for Main's HttpRequestId.
-}
requestId : Int -> String
requestId n =
    "code_" ++ String.fromInt n


{-| Starts committing `modules` (names and texts) with this message and token: the first
request. Nothing if there's no commit to start from.
-}
start : { token : String, message : String, modules : SeqDict String String } -> Git -> Maybe ( Git, HttpRequest )
start { token, message, modules } git =
    case startingPoint git of
        ( "", _ ) ->
            Nothing

        ( base, branch ) ->
            let
                work : GitWork
                work =
                    { request = git.requests + 1
                    , step = GettingBase
                    , token = token
                    , message = message
                    , base = base
                    , branch = branch
                    , modules = modules
                    }
            in
            Just
                ( { git | status = GitWorking work, requests = work.request }
                , request work "GET" ("/git/commits/" ++ base) Nothing
                )


{-| What happens after an answer.
-}
type Answer
    = Next Git HttpRequest
    | Finished Git


{-| GitHub's answer (status and body) to request number `n`. Answers to requests that
are no longer waited for change nothing.
-}
respond : Int -> Result String { status : Int, body : String } -> Git -> Answer
respond n result git =
    case git.status of
        GitWorking work ->
            if work.request /= n then
                Finished git

            else
                case result of
                    Ok response ->
                        answer work response git

                    Err error ->
                        Finished { git | status = GitFailed (stepName work.step) error }

        GitIdle ->
            Finished git

        GitPushed _ _ ->
            Finished git

        GitFailed _ _ ->
            Finished git


answer : GitWork -> { status : Int, body : String } -> Git -> Answer
answer work response git =
    let
        ok : Bool
        ok =
            response.status >= 200 && response.status < 300

        failed : String -> Answer
        failed why =
            Finished { git | status = GitFailed (stepName work.step) why }

        next : GitStep -> String -> String -> Maybe E.Value -> Answer
        next step method path body =
            let
                work2 : GitWork
                work2 =
                    { work | request = git.requests + 1, step = step }
            in
            Next { git | status = GitWorking work2, requests = work2.request } (request work2 method path body)

        sha : D.Decoder String
        sha =
            D.field "sha" D.string

        decoded : D.Decoder a -> (a -> Answer) -> Answer
        decoded decoder continue =
            if ok then
                case D.decodeString decoder response.body of
                    Ok value ->
                        continue value

                    Err error ->
                        failed ("GitHub's answer didn't make sense: " ++ D.errorToString error)

            else
                failed (httpFailure response)

        pushed : String -> String -> Answer
        pushed commit branch =
            Finished
                { git
                    | base = commit
                    , branch = branch
                    , from = BuildInfo.commit
                    , pushed = work.modules
                    , status = GitPushed commit branch
                }

        newBranch : String -> Answer
        newBranch commit =
            let
                name : String
                name =
                    "elmos-edits-" ++ String.left 12 commit
            in
            next
                (MakingBranch commit name)
                "POST"
                "/git/refs"
                (Just (E.object [ ( "ref", E.string ("refs/heads/" ++ name) ), ( "sha", E.string commit ) ]))
    in
    case work.step of
        GettingBase ->
            decoded (D.at [ "tree", "sha" ] D.string)
                (\tree ->
                    next MakingTree
                        "POST"
                        "/git/trees"
                        (Just
                            (E.object
                                [ ( "base_tree", E.string tree )
                                , ( "tree", E.list treeEntry (SeqDict.toList work.modules) )
                                ]
                            )
                        )
                )

        MakingTree ->
            decoded sha
                (\tree ->
                    next MakingCommit
                        "POST"
                        "/git/commits"
                        (Just
                            (E.object
                                [ ( "message", E.string work.message )
                                , ( "tree", E.string tree )
                                , ( "parents", E.list E.string [ work.base ] )
                                ]
                            )
                        )
                )

        MakingCommit ->
            decoded sha
                (\commit ->
                    if work.branch == "" then
                        newBranch commit

                    else
                        next (Pushing commit)
                            "PATCH"
                            ("/git/refs/heads/" ++ work.branch)
                            (Just (E.object [ ( "sha", E.string commit ), ( "force", E.bool False ) ]))
                )

        Pushing commit ->
            if ok then
                pushed commit work.branch

            else if response.status == 422 || response.status == 409 then
                -- Not a fast-forward: someone pushed to the branch meanwhile.
                newBranch commit

            else
                failed (httpFailure response)

        MakingBranch commit name ->
            if ok then
                pushed commit name

            else
                failed (httpFailure response)


{-| A module in the new tree: its file under elm/src, with its text.
-}
treeEntry : ( String, String ) -> E.Value
treeEntry ( name, text ) =
    E.object
        [ ( "path", E.string ("elm/src/" ++ String.replace "." "/" name ++ ".elm") )
        , ( "mode", E.string "100644" )
        , ( "type", E.string "blob" )
        , ( "content", E.string text )
        ]


request : GitWork -> String -> String -> Maybe E.Value -> HttpRequest
request work method path body =
    { id = requestId work.request
    , method = method
    , url = "https://api.github.com/repos/" ++ repository ++ path
    , headers =
        [ ( "Authorization", "Bearer " ++ work.token )
        , ( "Accept", "application/vnd.github+json" )
        , ( "X-GitHub-Api-Version", "2022-11-28" )

        -- GitHub wants a User-Agent too: the host sends one ("ElmOS").
        ]
            ++ (case body of
                    Just _ ->
                        [ ( "Content-Type", "application/json" ) ]

                    Nothing ->
                        []
               )
    , body =
        case body of
            Just value ->
                BE.encode (BE.string (E.encode 0 value))

            Nothing ->
                Effect.noBody
    , timeoutMs = Just (Duration.seconds 30)
    }


{-| What GitHub said when it said no: its status and its message, if it gave one.
-}
httpFailure : { status : Int, body : String } -> String
httpFailure response =
    let
        message : String
        message =
            case D.decodeString (D.field "message" D.string) response.body of
                Ok text ->
                    text

                Err _ ->
                    String.left 300 response.body

        hint : String
        hint =
            case response.status of
                401 ->
                    " (the token is wrong or has expired)"

                403 ->
                    " (the token may not be allowed to write to " ++ repository ++ ")"

                404 ->
                    " (the token may not be allowed to see " ++ repository ++ ", or the commit isn't on GitHub)"

                _ ->
                    ""
    in
    "GitHub answered " ++ String.fromInt response.status ++ ": " ++ message ++ hint


stepName : GitStep -> String
stepName step =
    case step of
        GettingBase ->
            "Getting the commit to build on"

        MakingTree ->
            "Sending the modules"

        MakingCommit ->
            "Making the commit"

        Pushing _ ->
            "Pushing"

        MakingBranch _ _ ->
            "Making a new branch"
