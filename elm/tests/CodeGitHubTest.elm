module CodeGitHubTest exposing (suite)

import BuildInfo
import Code.GitHub exposing (Answer(..))
import Code.Types exposing (Git, GitStatus(..))
import Effect exposing (HttpRequest)
import Expect
import Json.Decode as D
import SeqDict
import Test exposing (Test, describe, test)


{-| A commit of the Code app's saved modules, step by step, with GitHub's answers made
up here: what each request asks for, and what happens after each answer.
-}
suite : Test
suite =
    describe "Committing to GitHub"
        [ test "the first request gets the commit to build on, with the token"
            (\_ ->
                case started of
                    Just ( _, request ) ->
                        Expect.equal
                            ( request.method, request.url, List.member ( "Authorization", "Bearer secret" ) request.headers )
                            ( "GET", api ++ "/git/commits/base1", True )

                    Nothing ->
                        Expect.fail "didn't start"
            )
        , test "without a commit to build on, it doesn't start"
            (\_ ->
                Code.GitHub.start { token = "secret", message = "m", modules = modules } { git | base = "", from = "not this build" }
                    |> Maybe.map Tuple.second
                    |> (if BuildInfo.commit == "" then
                            Expect.equal Nothing

                        else
                            \_ -> Expect.pass
                       )
            )
        , test "the tree has the modules under elm/src, on the base's tree"
            (\_ ->
                case answers [ ok """{"sha":"base1","tree":{"sha":"tree1"}}""" ] of
                    ( _, Just request ) ->
                        Expect.equal ( request.method, request.url, bodyOf request )
                            ( "POST"
                            , api ++ "/git/trees"
                            , Just """{"base_tree":"tree1","tree":[{"path":"elm/src/Code/Types.elm","mode":"100644","type":"blob","content":"module Code.Types\\n"}]}"""
                            )

                    _ ->
                        Expect.fail "no request"
            )
        , test "the commit is on top of the base, with the message"
            (\_ ->
                case answers [ ok baseAnswer, ok """{"sha":"tree2"}""" ] of
                    ( _, Just request ) ->
                        Expect.equal ( request.method, request.url, bodyOf request )
                            ( "POST", api ++ "/git/commits", Just """{"message":"Change it","tree":"tree2","parents":["base1"]}""" )

                    _ ->
                        Expect.fail "no request"
            )
        , test "the branch is moved on to the commit, never forced"
            (\_ ->
                case answers [ ok baseAnswer, ok """{"sha":"tree2"}""", ok """{"sha":"commit2"}""" ] of
                    ( _, Just request ) ->
                        Expect.equal ( request.method, request.url, bodyOf request )
                            ( "PATCH", api ++ "/git/refs/heads/dev", Just """{"sha":"commit2","force":false}""" )

                    _ ->
                        Expect.fail "no request"
            )
        , test "once pushed, the next commit goes on top of this one"
            (\_ ->
                case answers [ ok baseAnswer, ok """{"sha":"tree2"}""", ok """{"sha":"commit2"}""", ok "{}" ] of
                    ( git2, Nothing ) ->
                        Expect.equal ( git2.status, Code.GitHub.startingPoint git2, git2.pushed ) ( GitPushed "commit2" "dev", ( "commit2", "dev" ), modules )

                    _ ->
                        Expect.fail "another request"
            )
        , test "if the branch moved on, a new branch gets the commit"
            (\_ ->
                case answers [ ok baseAnswer, ok """{"sha":"tree2"}""", ok """{"sha":"commit2"}""", answer 422 """{"message":"Update is not a fast forward"}""" ] of
                    ( _, Just request ) ->
                        Expect.equal ( request.method, request.url, bodyOf request )
                            ( "POST", api ++ "/git/refs", Just """{"ref":"refs/heads/elmos-edits-commit2","sha":"commit2"}""" )

                    _ ->
                        Expect.fail "no request"
            )
        , test "and further commits go to that branch"
            (\_ ->
                answers [ ok baseAnswer, ok """{"sha":"tree2"}""", ok """{"sha":"commit2"}""", answer 422 "{}", answer 201 "{}" ]
                    |> Tuple.first
                    |> .status
                    |> Expect.equal (GitPushed "commit2" "elmos-edits-commit2")
            )
        , test "a refusal says why"
            (\_ ->
                answers [ answer 401 """{"message":"Bad credentials"}""" ]
                    |> Tuple.first
                    |> .status
                    |> Expect.equal (GitFailed "Getting the commit to build on" "GitHub answered 401: Bad credentials (the token is wrong or has expired)")
            )
        , test "an answer to an older request changes nothing"
            (\_ ->
                case started of
                    Just ( waiting, _ ) ->
                        case Code.GitHub.respond (waiting.requests - 1) (Ok { status = 200, body = baseAnswer }) waiting of
                            Finished after ->
                                Expect.equal after waiting

                            Next _ _ ->
                                Expect.fail "it went on"

                    Nothing ->
                        Expect.fail "didn't start"
            )
        ]


api : String
api =
    "https://api.github.com/repos/MartinSStewart/Elm-OS"


baseAnswer : String
baseAnswer =
    """{"sha":"base1","tree":{"sha":"tree1"}}"""


modules : SeqDict.SeqDict String String
modules =
    SeqDict.fromList [ ( "Code.Types", "module Code.Types\n" ) ]


{-| Pushes before, to dev, while running a build of the commit those were made from.
-}
git : Git
git =
    { base = "base1", branch = "dev", from = BuildInfo.commit, pushed = SeqDict.empty, status = GitIdle, requests = 5 }


started : Maybe ( Git, HttpRequest )
started =
    Code.GitHub.start { token = "secret", message = "Change it", modules = modules } git


ok : String -> { status : Int, body : String }
ok =
    answer 200


answer : Int -> String -> { status : Int, body : String }
answer status body =
    { status = status, body = body }


{-| The state after these answers, one per request, and the request waiting for one.
-}
answers : List { status : Int, body : String } -> ( Git, Maybe HttpRequest )
answers list =
    case started of
        Just ( git2, request ) ->
            List.foldl
                (\response ( g, _ ) ->
                    case Code.GitHub.respond g.requests (Ok response) g of
                        Next g2 next ->
                            ( g2, Just next )

                        Finished g2 ->
                            ( g2, Nothing )
                )
                ( git2, Just request )
                list

        Nothing ->
            ( git, Nothing )


bodyOf : HttpRequest -> Maybe String
bodyOf request =
    Effect.bodyToString request.body
        |> Maybe.andThen (\text -> D.decodeString D.value text |> Result.toMaybe |> Maybe.map (\_ -> text))
