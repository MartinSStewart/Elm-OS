module CodeIndexTest exposing (suite)

import Code.Index
import Expect
import SeqDict
import SourceCode
import Test exposing (Test)


{-| Two small modules: `Shapes` defines things and `Main` uses them.
-}
shapes : String
shapes =
    String.join "\n"
        [ "module Shapes exposing (Shape(..), area, side)"
        , ""
        , "{-| area is not a use of `side` in a comment. -}"
        , ""
        , ""
        , "type Shape"
        , "    = Square Int"
        , "    | Circle (List Int)"
        , ""
        , ""
        , "type alias Box ="
        , "    { width : Int }"
        , ""
        , ""
        , "port out : String -> Cmd msg"
        , ""
        , ""
        , "area : Shape -> Int"
        , "area shape ="
        , "    case shape of"
        , "        Square n ->"
        , "            side n * n"
        , ""
        , "        Circle _ ->"
        , "            \"side\" |> String.length"
        , ""
        , ""
        , "side : Int -> Int"
        , "side n ="
        , "    n + (side n) + box.side"
        , ""
        ]


app : String
app =
    String.join "\n"
        [ "module Main exposing (main)"
        , ""
        , "import Dict exposing (Dict)"
        , "import Shapes as S exposing (Shape(..), area)"
        , "import Shapes.Other"
        , ""
        , ""
        , "main ="
        , "    area (Square 1) + S.side 2 + Shapes.Other.side 3"
        , ""
        , ""
        , "side ="
        , "    -- S.side in a comment"
        , "    'x' |> always (S.area (Circle [ 1 ]))"
        ]


declared : String -> List ( String, Int )
declared text =
    Code.Index.declarations text
        |> List.map (\declaration -> ( declaration.name, declaration.start ))


suite : Test
suite =
    Test.describe "Code.Index"
        [ Test.test "declarations are the top level names, types and constructors"
            (\_ ->
                declared shapes
                    |> List.map Tuple.first
                    |> Expect.equal [ "Shape", "Square", "Circle", "Box", "out", "area", "area", "side", "side" ]
            )
        , Test.test "imports have aliases and what they expose"
            (\_ ->
                Code.Index.imports app
                    |> Expect.equal
                        [ { module_ = "Dict", alias_ = Nothing, exposing_ = Code.Index.ExposesSome [ "Dict" ] False }
                        , { module_ = "Shapes", alias_ = Just "S", exposing_ = Code.Index.ExposesSome [ "area", "Shape" ] True }
                        , { module_ = "Shapes.Other", alias_ = Nothing, exposing_ = Code.Index.ExposesNone }
                        ]
            )
        , Test.test "exposing everything"
            (\_ ->
                Code.Index.imports "import A exposing (..)\nimport B exposing ((|=), b)\n"
                    |> List.map .exposing_
                    |> Expect.equal [ Code.Index.ExposesAll, Code.Index.ExposesSome [ "b" ] False ]
            )
        , Test.test "names resolve through aliases and exposing lists"
            (\_ ->
                let
                    context =
                        { thisModule = "Main"
                        , imports = Code.Index.imports app
                        , declarationsOf =
                            \name ->
                                if name == "Shapes" then
                                    Code.Index.declarations shapes

                                else if name == "Main" then
                                    Code.Index.declarations app

                                else
                                    []
                        }

                    resolved position =
                        Code.Index.wordAt position app
                            |> Maybe.andThen (Code.Index.resolve context)
                            |> Maybe.map (\target -> ( target.module_, target.name ))

                    at needle =
                        String.indexes needle app |> List.head |> Maybe.withDefault -1
                in
                [ resolved (at "area (Square" + 1)
                , resolved (at "Square 1" + 1)
                , resolved (at "S.side" + 3)
                , resolved (at "Shapes.Other.side" + 14)
                , resolved (at "side =" + 1)
                , resolved (at "Dict")
                ]
                    |> Expect.equal
                        [ Just ( "Shapes", "area" )
                        , Just ( "Shapes", "Square" )
                        , Just ( "Shapes", "side" )
                        , Nothing
                        , Just ( "Main", "side" )
                        , Nothing
                        ]
            )
        , Test.test "usages are in the module and the ones importing it, not in comments, strings or fields"
            (\_ ->
                Code.Index.usages
                    { module_ = "Shapes", name = "side", position = 0 }
                    [ { name = "Shapes", text = shapes }, { name = "Main", text = app } ]
                    |> List.map (\usage -> ( usage.module_, usage.line ))
                    |> Expect.equal [ ( "Shapes", 21 ), ( "Shapes", 29 ), ( "Main", 8 ) ]
            )
        , Test.test "usages of a constructor come with its line's text"
            (\_ ->
                Code.Index.usages
                    { module_ = "Shapes", name = "Square", position = 0 }
                    [ { name = "Shapes", text = shapes }, { name = "Main", text = app } ]
                    |> List.map (\usage -> ( usage.module_, usage.text ))
                    |> Expect.equal
                        [ ( "Shapes", "Square n ->" )
                        , ( "Main", "area (Square 1) + S.side 2 + Shapes.Other.side 3" )
                        ]
            )
        , Test.test "on the real code: Scrollbar.marks is used where the editor draws it"
            (\_ ->
                let
                    texts =
                        SeqDict.toList SourceCode.sourceCode
                            |> List.filter (\( name, _ ) -> not (String.startsWith "Evergreen." name))
                            |> List.map (\( name, text ) -> { name = name, text = text })
                in
                case SeqDict.get "Scrollbar" SourceCode.sourceCode of
                    Just text ->
                        case List.filter (\declaration -> declaration.name == "marks") (Code.Index.declarations text) of
                            declaration :: _ ->
                                Code.Index.usages { module_ = "Scrollbar", name = "marks", position = declaration.start } texts
                                    |> List.map .module_
                                    |> Expect.equal [ "TextInputMultiline" ]

                            [] ->
                                Expect.fail "Scrollbar doesn't declare marks"

                    Nothing ->
                        Expect.fail "no Scrollbar module"
            )
        ]
