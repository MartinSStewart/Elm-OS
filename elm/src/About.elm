module About exposing (Info, limits, view)

{-| The About app: what Elm OS is, and what it is running on.
-}

import About.Types
import App
import Sprite
import Ui
import UiId exposing (UiId)


{-| What the host says about this computer, where it has said.
-}
type alias Info =
    { commit : Maybe String
    , kernel : Maybe String
    , cpu : Maybe String
    , memTotalMb : Maybe Int
    , graphics : Maybe String
    }


{-| The app's window size, from a view with nothing known, once.
-}
limits : App.Limits
limits =
    App.fixed (Ui.size (view { commit = Nothing, kernel = Nothing, cpu = Nothing, memTotalMb = Nothing, graphics = Nothing }))


view : Info -> Ui.Element UiId
view info =
    let
        valueWidth =
            App.em 26

        line label value =
            Ui.row
                0
                [ Ui.left (App.em 5) (Ui.text label), Ui.text (Sprite.ellipsis App.bodySize App.sans valueWidth value) ]

        orUnknown =
            Maybe.withDefault "?"
    in
    Ui.el
        { padding = Ui.paddingXY 12 10
        , style = Ui.windowBorderAndFill
        }
        (Ui.column
            4
            [ App.heading "Elm OS"
            , Ui.text "A Linux kernel that boots straight into one Elm program."
            , Ui.text ""
            , line "Version" (orUnknown info.commit)
            , line "Kernel" (orUnknown info.kernel)
            , line "CPU" (orUnknown info.cpu)
            , line "Memory"
                (case info.memTotalMb of
                    Just mb ->
                        String.fromInt mb ++ " MB"

                    Nothing ->
                        "?"
                )
            , line "Graphics"
                (orUnknown info.graphics)
            , Ui.text ""
            , Ui.text
                (Sprite.wrap App.bodySize
                    App.sans
                    (App.em 31)
                    ("The Elm program is compiled to native code by eco (github.com/eco-lang/eco-compiler). "
                        ++ "The UI framework and the debug app's pixel font are from town-collab. "
                        ++ "Text is in Noto Sans (SIL Open Font License). "
                        ++ "Weather: open-meteo.com, location: geojs.io."
                    )
                )
            , Ui.text ""
            , Ui.button { id = UiId.About About.Types.CloseButton, padding = Ui.paddingXY 6 3 } (Ui.text "Close")
            ]
        )
