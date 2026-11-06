module Calculator exposing (UiId(..), view)

import Sprite exposing (Font(..), FontSize(..))
import Ui exposing (Element)


spacing =
    4


type UiId
    = Button String


view : Element UiId
view =
    [ [ "7", "8", "9", "/" ]
    , [ "4", "5", "6", "*" ]
    , [ "1", "2", "3", "-" ]
    , [ "0", ".", "+" ]
    ]
        |> List.map
            (\row ->
                Ui.row
                    { spacing = spacing, padding = Ui.noPadding }
                    (List.map
                        (\button ->
                            Ui.button { id = Button button, padding = Ui.paddingXY 4 4 } (Ui.text (Mono Small) button)
                        )
                        row
                    )
            )
        |> Ui.column { spacing = spacing, padding = Ui.noPadding }
