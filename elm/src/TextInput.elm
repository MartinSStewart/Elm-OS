module TextInput exposing
    ( Model
    , OutMsg(..)
    , State
    , Style
    , init
    , keyMsg
    , mouseDown
    , mouseDownMove
    , paste
    , replaceState
    , size
    , view
    )

{-| town-collab's single-line text input (src/TextInput.elm in
github.com/MartinSStewart/town-collab), ported to Elm OS: it is laid out in UI pixels
(Units.elm) and draws triangles for the render port in either font (Noto Sans
is proportional, so the cursor goes between measured characters), Home and End move to
the ends, text wider than the box scrolls to keep the cursor in view, and a password
shows dots.
-}

import Color
import Coord exposing (Coord)
import Keyboard
import Quantity exposing (Quantity)
import Sprite exposing (Triangle)
import Units exposing (DevicePixels, UiPixels, UiScale)


type alias Model =
    { current : State
    , undoHistory : List State
    , redoHistory : List State
    }


type alias State =
    { cursorPosition : Int
    , cursorSize : Int
    , text : String
    }


init : Model
init =
    { current = { cursorPosition = 0, cursorSize = 0, text = "" }, undoHistory = [], redoHistory = [] }


pushState : (State -> State) -> Model -> Model
pushState changeFunc model =
    { redoHistory = [], undoHistory = model.current :: model.undoHistory, current = changeFunc model.current }


replaceState : (State -> State) -> Model -> Model
replaceState changeFunc model =
    { model | current = changeFunc model.current }


undo : Model -> Model
undo model =
    case model.undoHistory of
        head :: rest ->
            { undoHistory = rest
            , current = head
            , redoHistory = model.current :: model.redoHistory
            }

        [] ->
            model


redo : Model -> Model
redo model =
    case model.redoHistory of
        head :: rest ->
            { redoHistory = rest
            , current = head
            , undoHistory = model.current :: model.undoHistory
            }

        [] ->
            model


selectionMin : State -> Int
selectionMin model =
    min model.cursorPosition (model.cursorPosition + model.cursorSize)


selectionMax : State -> Int
selectionMax model =
    max model.cursorPosition (model.cursorPosition + model.cursorSize)


type OutMsg
    = CopyText String
    | NoOutMsg


keyMsg : Bool -> Bool -> Keyboard.Key -> Model -> ( Model, OutMsg )
keyMsg ctrlDown shiftDown key model =
    case ( ctrlDown, shiftDown, key ) of
        ( True, False, Keyboard.Character "c" ) ->
            ( model
            , String.dropLeft (selectionMin model.current) model.current.text
                |> String.left (abs model.current.cursorSize)
                |> CopyText
            )

        ( True, False, Keyboard.Character "x" ) ->
            ( pushState deleteSelection model
            , String.dropLeft (selectionMin model.current) model.current.text
                |> String.left (abs model.current.cursorSize)
                |> CopyText
            )

        ( True, False, Keyboard.Character "z" ) ->
            ( undo model, NoOutMsg )

        ( True, False, Keyboard.Character "y" ) ->
            ( redo model, NoOutMsg )

        ( True, True, Keyboard.Character "Z" ) ->
            ( redo model, NoOutMsg )

        ( True, False, Keyboard.Character "a" ) ->
            ( replaceState
                (\state ->
                    { state
                        | cursorPosition = String.length state.text
                        , cursorSize = String.length state.text |> negate
                    }
                )
                model
            , NoOutMsg
            )

        ( False, _, Keyboard.Character string ) ->
            ( pushState (insertText string) model, NoOutMsg )

        ( False, _, Keyboard.Spacebar ) ->
            ( pushState (insertText " ") model, NoOutMsg )

        ( True, False, Keyboard.ArrowLeft ) ->
            ( replaceState
                (\state ->
                    { state
                        | cursorPosition =
                            if state.cursorSize == 0 then
                                0

                            else
                                selectionMin state
                        , cursorSize = 0
                    }
                )
                model
            , NoOutMsg
            )

        ( False, True, Keyboard.ArrowLeft ) ->
            ( replaceState
                (\state ->
                    { state
                        | cursorPosition = state.cursorPosition - 1 |> max 0
                    }
                        |> setCursorSize
                            (if state.cursorPosition > 0 then
                                state.cursorSize + 1

                             else
                                state.cursorSize
                            )
                )
                model
            , NoOutMsg
            )

        ( False, False, Keyboard.ArrowLeft ) ->
            ( replaceState
                (\state ->
                    { state
                        | cursorPosition =
                            if state.cursorSize == 0 then
                                state.cursorPosition - 1 |> max 0

                            else
                                selectionMin state
                        , cursorSize = 0
                    }
                )
                model
            , NoOutMsg
            )

        ( True, False, Keyboard.ArrowRight ) ->
            ( replaceState
                (\state ->
                    { state
                        | cursorPosition =
                            if state.cursorSize == 0 then
                                String.length state.text

                            else
                                selectionMax state
                        , cursorSize = 0
                    }
                )
                model
            , NoOutMsg
            )

        ( False, True, Keyboard.ArrowRight ) ->
            ( replaceState
                (\state ->
                    { state
                        | cursorPosition = state.cursorPosition + 1 |> min (String.length state.text)
                    }
                        |> setCursorSize
                            (if state.cursorPosition < String.length state.text then
                                state.cursorSize - 1

                             else
                                state.cursorSize
                            )
                )
                model
            , NoOutMsg
            )

        ( False, False, Keyboard.ArrowRight ) ->
            ( replaceState
                (\state ->
                    { state
                        | cursorPosition =
                            (if state.cursorSize == 0 then
                                state.cursorPosition + 1

                             else
                                selectionMax state
                            )
                                |> min (String.length state.text)
                        , cursorSize = 0
                    }
                )
                model
            , NoOutMsg
            )

        ( False, False, Keyboard.ArrowUp ) ->
            ( replaceState
                (\state -> { state | cursorPosition = 0, cursorSize = 0 })
                model
            , NoOutMsg
            )

        ( False, False, Keyboard.Home ) ->
            ( replaceState
                (\state -> { state | cursorPosition = 0, cursorSize = 0 })
                model
            , NoOutMsg
            )

        ( False, False, Keyboard.End ) ->
            ( replaceState
                (\state -> { state | cursorPosition = String.length state.text, cursorSize = 0 })
                model
            , NoOutMsg
            )

        ( False, False, Keyboard.ArrowDown ) ->
            ( replaceState
                (\state -> { state | cursorPosition = String.length state.text, cursorSize = 0 })
                model
            , NoOutMsg
            )

        ( True, False, Keyboard.Backspace ) ->
            ( pushState
                (\state ->
                    if state.cursorSize == 0 then
                        { state
                            | text = String.dropLeft state.cursorPosition state.text
                            , cursorPosition = 0
                            , cursorSize = 0
                        }

                    else
                        deleteSelection state
                )
                model
            , NoOutMsg
            )

        ( False, False, Keyboard.Backspace ) ->
            ( pushState
                (\state ->
                    if state.cursorSize == 0 then
                        { state
                            | text =
                                String.left (state.cursorPosition - 1) state.text
                                    ++ String.dropLeft state.cursorPosition state.text
                            , cursorPosition = state.cursorPosition - 1 |> max 0
                            , cursorSize = 0
                        }

                    else
                        deleteSelection state
                )
                model
            , NoOutMsg
            )

        ( False, False, Keyboard.Delete ) ->
            ( pushState
                (\state ->
                    if state.cursorSize == 0 then
                        { state
                            | text =
                                String.left state.cursorPosition state.text
                                    ++ String.dropLeft (state.cursorPosition + 1) state.text
                        }

                    else
                        deleteSelection state
                )
                model
            , NoOutMsg
            )

        _ ->
            ( model, NoOutMsg )


setCursorSize : Int -> State -> State
setCursorSize newCursorSize state =
    { state
        | cursorSize =
            if newCursorSize > 0 then
                min (String.length state.text - state.cursorPosition) newCursorSize

            else
                max -state.cursorPosition newCursorSize
    }


paste : String -> Model -> Model
paste text model =
    if text == "" then
        model

    else
        pushState (insertText text) model


insertText : String -> State -> State
insertText text state =
    { state
        | text =
            String.left (selectionMin state) state.text
                ++ text
                ++ String.dropLeft (selectionMax state) state.text
        , cursorPosition = selectionMin state + String.length text
        , cursorSize = 0
    }


deleteSelection : State -> State
deleteSelection state =
    { state
        | text = String.left (selectionMin state) state.text ++ String.dropLeft (selectionMax state) state.text
        , cursorPosition = selectionMin state
        , cursorSize = 0
    }


{-| How a text input looks: its font, its width, and whether it shows a dot for each
character instead of the text (for passwords).
-}
type alias Style =
    { font : Sprite.Font, width : Quantity Int UiPixels, masked : Bool }


shownText : Style -> String -> String
shownText style text =
    if style.masked then
        String.repeat (String.length text)
            (case style.font of
                Sprite.Mono _ ->
                    "*"

                Sprite.Sans _ ->
                    "•"
            )

    else
        text


{-| Where the cursor goes before each character and after the last, in UI pixels from
the start of the text.
-}
carets : Style -> State -> List Int
carets style state =
    Sprite.caretPositions style.font (shownText style state.text) |> List.map Quantity.unwrap


caretX : List Int -> Int -> Int
caretX positions index =
    List.drop index positions |> List.head |> Maybe.withDefault 0


caretWidth : Style -> Int
caretWidth style =
    max 1 (lineHeight style // 20)


lineHeight : Style -> Int
lineHeight style =
    Sprite.lineHeight style.font |> Quantity.unwrap


width : Style -> Int
width style =
    Quantity.unwrap style.width


{-| The mouse went down at `mousePosition`, with the box at `position`.
-}
mouseDown : Style -> Coord UiPixels -> Coord UiPixels -> Model -> Model
mouseDown style mousePosition position model =
    replaceState
        (\state ->
            { state
                | cursorPosition = cursorPosition style mousePosition position state
                , cursorSize = 0
            }
        )
        model


{-| The caret nearest the mouse.
-}
cursorPosition : Style -> Coord UiPixels -> Coord UiPixels -> State -> Int
cursorPosition style mousePosition position state =
    let
        x =
            Coord.xRaw mousePosition - (Coord.xRaw position + padding + caretWidth style) + scroll style state
    in
    carets style state
        |> List.indexedMap Tuple.pair
        |> List.foldl
            (\( index, at ) ( best, bestDistance ) ->
                if abs (at - x) < bestDistance then
                    ( index, abs (at - x) )

                else
                    ( best, bestDistance )
            )
            ( 0, 1000000 )
        |> Tuple.first


mouseDownMove : Style -> Coord UiPixels -> Coord UiPixels -> Model -> Model
mouseDownMove style mousePosition position model =
    replaceState
        (\state ->
            let
                cursorPosition2 =
                    cursorPosition style mousePosition position state
            in
            { state | cursorPosition = cursorPosition2 }
                |> setCursorSize (state.cursorSize + (state.cursorPosition - cursorPosition2))
        )
        model


{-| Between the border and the text, on every side, in UI pixels.
-}
padding : Int
padding =
    4


size : Style -> Coord UiPixels
size style =
    Coord.xy (width style) (lineHeight style + padding * 2)


{-| The pixels between the box's padding that text shows in.
-}
innerWidth : Style -> Int
innerWidth style =
    width style - 2 * padding - 2 * caretWidth style


{-| How far the text is scrolled left, in UI pixels: 0 unless the cursor would be past
the right edge, and then just enough to show it. (town-collab's boxes are wide enough not
to need this.)
-}
scroll : Style -> State -> Int
scroll style state =
    max 0 (caretX (carets style state) state.cursorPosition - innerWidth style)


view : UiScale -> Style -> Coord UiPixels -> Bool -> Bool -> State -> List (Triangle DevicePixels)
view scale style offset hasFocus isValid current =
    let
        positions =
            carets style current

        ( x, y ) =
            Coord.toTuple offset

        textLeft =
            x + padding + caretWidth style - scroll style current

        clip =
            { left = x + padding, right = x + width style - padding }

        height =
            lineHeight style

        selectionStart =
            textLeft + caretX positions (min current.cursorPosition (current.cursorPosition + current.cursorSize))

        selectionEnd =
            textLeft + caretX positions (max current.cursorPosition (current.cursorPosition + current.cursorSize))

        ( boxWidth, boxHeight ) =
            Coord.toTuple (size style)

        box =
            Sprite.rectangle
                (if not isValid then
                    Color.errorColor

                 else if hasFocus then
                    Color.highlightColor

                 else
                    Color.outlineColor
                )
                offset
                (size style)
                ++ Sprite.rectangle
                    (if hasFocus then
                        Color.highlightColor

                     else
                        Color.fillColor3
                    )
                    (Coord.xy (x + padding) (y + padding))
                    (Coord.xy (boxWidth - 2 * padding) (boxHeight - 2 * padding))
                ++ (if current.cursorSize == 0 || not hasFocus then
                        []

                    else
                        Sprite.rectangle
                            (Color.rgb255 170 210 255)
                            (Coord.xy (max clip.left selectionStart) (y + padding))
                            (Coord.xy (min clip.right selectionEnd - max clip.left selectionStart) height)
                   )

        caret =
            if hasFocus then
                Sprite.rectangle Color.black
                    (Coord.xy (textLeft + caretX positions current.cursorPosition - caretWidth style) (y + padding))
                    (Coord.xy (caretWidth style) height)

            else
                []
    in
    Sprite.toDevice scale box
        ++ Sprite.clippedText scale
            Color.black
            style.font
            (Just { left = Units.uiPixels clip.left, right = Units.uiPixels clip.right })
            (shownText style current.text)
            (Coord.xy textLeft (y + padding))
        ++ Sprite.toDevice scale caret
