module SimplifyUiTest exposing (all)

import Expect exposing (Expectation)
import Review.Test
import SimplifyUi exposing (rule)
import Test exposing (Test, describe, test)


uiModule : String
uiModule =
    """module Ui exposing (BorderAndFill(..), Element, Padding, button, column, selectableButton, el, elWithId, noPadding, paddingXY, row, text)
type Element = Element
type BorderAndFill = NoBorderOrFill | FillOnly Int
type alias Padding = { top : Int, bottom : Int, left : Int, right : Int }
noPadding : Padding
noPadding = { top = 0, bottom = 0, left = 0, right = 0 }
paddingXY : Int -> Int -> Padding
paddingXY x y = { top = y, bottom = y, left = x, right = x }
el : { padding : Padding, inFront : List Element, borderAndFill : BorderAndFill } -> Element -> Element
el _ e = e
elWithId : Int -> { padding : Padding, inFront : List Element, borderAndFill : BorderAndFill } -> Element -> Element
elWithId _ _ e = e
row : Int -> List Element -> Element
row _ _ = Element
column : Int -> List Element -> Element
column _ _ = Element
text : String -> Element
text _ = Element
button : { id : Int, padding : Padding } -> Element -> Element
button _ e = e
selectableButton : { id : Int, padding : Padding } -> Bool -> Element -> Element
selectableButton _ _ e = e
"""


run : String -> Review.Test.ReviewResult
run source =
    Review.Test.runOnModules rule [ source, uiModule ]


expect : List Review.Test.ExpectedError -> Review.Test.ReviewResult -> Expectation
expect errors =
    Review.Test.expectErrorsForModules [ ( "A", errors ) ]


uselessMessage : { message : String, details : List String, under : String }
uselessMessage =
    { message = "This Ui.el does nothing"
    , details =
        [ "It has no padding, no border or fill and nothing inFront, so it draws its child exactly as the child would draw itself."
        , "Use the child directly instead."
        ]
    , under = "Ui.el"
    }


nestedMessage : { message : String, details : List String, under : String }
nestedMessage =
    { message = "This Ui.el only adds padding to the Ui.el around it"
    , details =
        [ "It has no border or fill and nothing inFront, so its padding can be added to the outer one's and it can be removed."
        ]
    , under = "Ui.el"
    }


all : Test
all =
    describe "SimplifyUi"
        [ test "leaves an el with a border alone" <|
            \() ->
                """module A exposing (a)
import Ui
a = Ui.el { padding = Ui.noPadding, inFront = [], borderAndFill = Ui.FillOnly 1 } (Ui.text "x")
"""
                    |> run
                    |> Review.Test.expectNoErrors
        , test "leaves an el with padding alone" <|
            \() ->
                """module A exposing (a)
import Ui
a = Ui.el { padding = Ui.paddingXY 2 0, inFront = [], borderAndFill = Ui.NoBorderOrFill } (Ui.text "x")
"""
                    |> run
                    |> Review.Test.expectNoErrors
        , test "leaves a padding in a variable alone" <|
            \() ->
                """module A exposing (a)
import Ui
a p = Ui.el { padding = p, inFront = [], borderAndFill = Ui.NoBorderOrFill } (Ui.text "x")
"""
                    |> run
                    |> Review.Test.expectNoErrors
        , test "removes an el that does nothing" <|
            \() ->
                """module A exposing (a)
import Ui
a = Ui.el { padding = Ui.noPadding, inFront = [], borderAndFill = Ui.NoBorderOrFill } (Ui.text "x")
"""
                    |> run
                    |> expect
                        [ Review.Test.error uselessMessage
                            |> Review.Test.whenFixed """module A exposing (a)
import Ui
a = Ui.text "x"
"""
                        ]
        , test "removes a piped el with a zero padding record" <|
            \() ->
                """module A exposing (a)
import Ui
a = Ui.text "x" |> Ui.el { padding = { top = 0, bottom = 0, left = 0, right = 0 }, inFront = [], borderAndFill = Ui.NoBorderOrFill }
"""
                    |> run
                    |> expect
                        [ Review.Test.error uselessMessage
                            |> Review.Test.whenFixed """module A exposing (a)
import Ui
a = Ui.text "x"
"""
                        ]
        , test "works with an exposed el and a module alias" <|
            \() ->
                """module A exposing (a)
import Ui as U exposing (el)
a = el { padding = U.paddingXY 0 0, inFront = [], borderAndFill = U.NoBorderOrFill } (U.text "x")
"""
                    |> run
                    |> expect
                        [ Review.Test.error { uselessMessage | under = "el" }
                            |> Review.Test.atExactly { start = { row = 3, column = 5 }, end = { row = 3, column = 7 } }
                            |> Review.Test.whenFixed """module A exposing (a)
import Ui as U exposing (el)
a = U.text "x"
"""
                        ]
        , test "merges a padding-only el into the el around it" <|
            \() ->
                """module A exposing (a)
import Ui
a =
    Ui.el { padding = Ui.paddingXY 8 8, inFront = [], borderAndFill = Ui.FillOnly 1 }
        (Ui.el { padding = Ui.paddingXY 4 0, inFront = [], borderAndFill = Ui.NoBorderOrFill } (Ui.text "x"))
"""
                    |> run
                    |> expect
                        [ Review.Test.error nestedMessage
                            |> Review.Test.atExactly { start = { row = 5, column = 10 }, end = { row = 5, column = 15 } }
                            |> Review.Test.whenFixed """module A exposing (a)
import Ui
a =
    Ui.el { padding = Ui.paddingXY 12 8, inFront = [], borderAndFill = Ui.FillOnly 1 }
        (Ui.text "x")
"""
                        ]
        , test "merges piped els, adding padding records side by side" <|
            \() ->
                """module A exposing (a)
import Ui
a n =
    Ui.text "x"
        |> Ui.el { padding = { top = n, bottom = 0, left = 2, right = 0 }, inFront = [], borderAndFill = Ui.NoBorderOrFill }
        |> Ui.elWithId 1 { padding = Ui.paddingXY 3 3, inFront = [ Ui.text "y" ], borderAndFill = Ui.FillOnly 1 }
"""
                    |> run
                    |> expect
                        [ Review.Test.error { nestedMessage | message = "This Ui.el only adds padding to the Ui.elWithId around it" }
                            |> Review.Test.atExactly { start = { row = 5, column = 12 }, end = { row = 5, column = 17 } }
                            |> Review.Test.whenFixed """module A exposing (a)
import Ui
a n =
    Ui.text "x"
        |> Ui.elWithId 1 { padding = { top = 3 + n, bottom = 3, left = 5, right = 3 }, inFront = [ Ui.text "y" ], borderAndFill = Ui.FillOnly 1 }
"""
                        ]
        , test "adds paddingXY arguments that are expressions" <|
            \() ->
                """module A exposing (a)
import Ui
a n =
    Ui.el { padding = Ui.paddingXY n n, inFront = [], borderAndFill = Ui.FillOnly 1 }
        (Ui.el { padding = Ui.paddingXY (n * 2) 1, inFront = [], borderAndFill = Ui.NoBorderOrFill } (Ui.text "x"))
"""
                    |> run
                    |> expect
                        [ Review.Test.error nestedMessage
                            |> Review.Test.atExactly { start = { row = 5, column = 10 }, end = { row = 5, column = 15 } }
                            |> Review.Test.whenFixed """module A exposing (a)
import Ui
a n =
    Ui.el { padding = Ui.paddingXY (n + (n * 2)) (n + 1), inFront = [], borderAndFill = Ui.FillOnly 1 }
        (Ui.text "x")
"""
                        ]
        , test "merges a padding-only el into a button" <|
            \() ->
                """module A exposing (a)
import Ui
a selected =
    Ui.selectableButton { id = 1, padding = Ui.paddingXY 8 8 } selected
        (Ui.el { padding = { top = 1, bottom = 2, left = 3, right = 4 }, inFront = [], borderAndFill = Ui.NoBorderOrFill } x)
"""
                    |> run
                    |> expect
                        [ Review.Test.error
                            { message = "This Ui.el only adds padding to the Ui.selectableButton around it"
                            , details = nestedMessage.details
                            , under = "Ui.el"
                            }
                            |> Review.Test.whenFixed """module A exposing (a)
import Ui
a selected =
    Ui.selectableButton { id = 1, padding = { top = 9, bottom = 10, left = 11, right = 12 } } selected
        x
"""
                        ]
        , test "keeps an inner el with a border" <|
            \() ->
                """module A exposing (a)
import Ui
a =
    Ui.el { padding = Ui.paddingXY 8 8, inFront = [], borderAndFill = Ui.NoBorderOrFill }
        (Ui.el { padding = Ui.paddingXY 4 0, inFront = [], borderAndFill = Ui.FillOnly 1 } (Ui.text "x"))
"""
                    |> run
                    |> Review.Test.expectNoErrors
        , test "keeps an inner el with inFront" <|
            \() ->
                """module A exposing (a)
import Ui
a =
    Ui.el { padding = Ui.paddingXY 8 8, inFront = [], borderAndFill = Ui.FillOnly 1 }
        (Ui.el { padding = Ui.paddingXY 4 0, inFront = [ Ui.text "y" ], borderAndFill = Ui.NoBorderOrFill } (Ui.text "x"))
"""
                    |> run
                    |> Review.Test.expectNoErrors
        , test "keeps an inner elWithId" <|
            \() ->
                """module A exposing (a)
import Ui
a =
    Ui.el { padding = Ui.paddingXY 8 8, inFront = [], borderAndFill = Ui.FillOnly 1 }
        (Ui.elWithId 1 { padding = Ui.paddingXY 4 0, inFront = [], borderAndFill = Ui.NoBorderOrFill } (Ui.text "x"))
"""
                    |> run
                    |> Review.Test.expectNoErrors
        , test "replaces a row with one child by the child" <|
            \() ->
                """module A exposing (a)
import Ui
a = Ui.column 4 [ Ui.row 8 [ Ui.text "x" ], Ui.text "y" ]
"""
                    |> run
                    |> expect
                        [ Review.Test.error
                            { message = "This Ui.row has only one child"
                            , details = [ "A row with one child is laid out and drawn just like the child on its own, so use the child directly instead." ]
                            , under = "Ui.row"
                            }
                            |> Review.Test.whenFixed """module A exposing (a)
import Ui
a = Ui.column 4 [ Ui.text "x", Ui.text "y" ]
"""
                        ]
        , test "ignores other modules' el" <|
            \() ->
                """module A exposing (a)
import Ui
el r x = x
a = el { padding = Ui.noPadding, inFront = [], borderAndFill = Ui.NoBorderOrFill } (Ui.text "x")
"""
                    |> run
                    |> Review.Test.expectNoErrors
        ]
