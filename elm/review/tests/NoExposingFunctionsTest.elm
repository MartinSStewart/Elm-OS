module NoExposingFunctionsTest exposing (all)

import NoExposingFunctions exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "NoExposingFunctions"
        [ test "allows types, aliases and constructors" <|
            \() ->
                """module A exposing (a)
import Dict exposing (Dict)
import Maybe exposing (Maybe(..))
import Set
import Basics exposing (..)
a = 1
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        , test "reports a function" <|
            \() ->
                """module A exposing (a)
import Dict exposing (Dict, empty)
a = 1
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "Imported function `empty` is exposed"
                            , details =
                                [ "Importing functions unqualified makes it hard to see where they come from."
                                , "Remove it from the exposing list and qualify its uses with the module name (or an alias) instead. Types and `Type(..)` may stay."
                                ]
                            , under = "empty"
                            }
                        ]
        , test "reports an operator" <|
            \() ->
                """module A exposing (a)
import Parser exposing ((|.))
a = 1
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "Imported function `(|.)` is exposed"
                            , details =
                                [ "Importing functions unqualified makes it hard to see where they come from."
                                , "Remove it from the exposing list and qualify its uses with the module name (or an alias) instead. Types and `Type(..)` may stay."
                                ]
                            , under = "(|.)"
                            }
                        ]
        ]
