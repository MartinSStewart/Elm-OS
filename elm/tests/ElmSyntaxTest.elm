module ElmSyntaxTest exposing (suite)

import ElmSyntax exposing (Kind(..))
import Expect
import Test exposing (Test)


{-| Lexes lines one after another, as the Code app does, and gives each line's runs.
-}
runs : List String -> List (List ( Kind, String ))
runs lines =
    List.foldl
        (\line ( state, acc ) ->
            let
                ( lineRuns, next ) =
                    ElmSyntax.highlightLine state line
            in
            ( next, lineRuns :: acc )
        )
        ( ElmSyntax.stateAt 0 [], [] )
        lines
        |> Tuple.second
        |> List.reverse


suite : Test
suite =
    Test.describe "ElmSyntax"
        [ Test.test "keywords, names, types and operators"
            (\_ ->
                runs [ "type alias Model = Maybe Int -> a" ]
                    |> Expect.equal
                        [ [ ( Keyword, "type" ), ( Plain, " " ), ( Keyword, "alias" ), ( Plain, " " ), ( TypeName, "Model" ), ( Plain, " " ), ( Operator, "=" ), ( Plain, " " ), ( TypeName, "Maybe" ), ( Plain, " " ), ( TypeName, "Int" ), ( Plain, " " ), ( Operator, "->" ), ( Plain, " a" ) ] ]
            )
        , Test.test "strings, characters, numbers and line comments"
            (\_ ->
                runs [ "f \"a \\\" b\" 'c' 12 -- done" ]
                    |> Expect.equal
                        [ [ ( Plain, "f " ), ( StringLiteral, "\"a \\\" b\"" ), ( Plain, " " ), ( StringLiteral, "'c'" ), ( Plain, " " ), ( NumberLiteral, "12" ), ( Plain, " " ), ( Comment, "-- done" ) ] ]
            )
        , Test.test "a nested block comment over several lines"
            (\_ ->
                runs [ "x {- a {- b -}", "still -} y" ]
                    |> Expect.equal
                        [ [ ( Plain, "x " ), ( Comment, "{- a {- b -}" ) ]
                        , [ ( Comment, "still -}" ), ( Plain, " y" ) ]
                        ]
            )
        , Test.test "a triple-quoted string over several lines"
            (\_ ->
                runs [ "s = \"\"\"one", "two\"\"\" ++ t" ]
                    |> Expect.equal
                        [ [ ( Plain, "s " ), ( Operator, "=" ), ( Plain, " " ), ( StringLiteral, "\"\"\"one" ) ]
                        , [ ( StringLiteral, "two\"\"\"" ), ( Plain, " " ), ( Operator, "++" ), ( Plain, " t" ) ]
                        ]
            )
        , Test.test "stateAt skips to a line inside a comment"
            (\_ ->
                ElmSyntax.highlightLine (ElmSyntax.stateAt 1 [ "{- open", "inside" ]) "inside"
                    |> Tuple.first
                    |> Expect.equal [ ( Comment, "inside" ) ]
            )
        ]
