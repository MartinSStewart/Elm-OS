module LinkTest exposing (tests)

import Color
import Coord
import Expect
import Sprite
import Test exposing (Test)
import Ui


segment : String -> Maybe String -> Sprite.Segment
segment text link =
    { text = text, color = Color.textColor, font = Sprite.Sans Sprite.Regular, decorations = [], link = link }


tests : Test
tests =
    Test.describe "links in text"
        [ Test.test "linkAt finds the link under a point"
            (\_ ->
                let
                    segments =
                        [ segment "plain " Nothing, segment "linked" (Just "https://a.example"), segment " after" Nothing ]
                in
                ( Sprite.linkAt Sprite.Small segments (Coord.xy 2 5)
                , Sprite.linkAt Sprite.Small segments (Coord.xy 60 5)
                , Sprite.linkAt Sprite.Small segments (Coord.xy 400 5)
                )
                    |> Expect.equal ( Nothing, Just "https://a.example", Nothing )
            )
        , Test.test "Ui.hover finds a text with links only over a link"
            (\_ ->
                let
                    element =
                        Ui.customText Sprite.Small [ segment "plain " Nothing, segment "linked" (Just "https://a.example") ]
                            |> Ui.links 7
                in
                ( Ui.hoverIdOnly Ui.init (Coord.xy 2 5) element |> List.map Tuple.first
                , Ui.hoverIdOnly Ui.init (Coord.xy 60 5) element |> List.map Tuple.first
                )
                    |> Expect.equal ( [], [ 7 ] )
            )
        ]
