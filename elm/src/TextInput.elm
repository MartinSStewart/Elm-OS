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
github.com/MartinSStewart/town-collab), ported to Elm OS: Coord is a plain (Int, Int),
widths are plain Ints, it draws triangles for the render port in either font (Noto Sans
is proportional, so the cursor goes between measured characters), Home and End move to
the ends, text wider than the box scrolls to keep the cursor in view, and a password
shows dots.
-}

import Color
import Coord exposing (Coord)
import Keyboard
import Sprite exposing (Triangle)


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


{-| How a text input looks: its font, its width in pixels, and whether it shows a dot
for each character instead of the text (for passwords).
-}
type alias Style =
    { font : Sprite.Font, width : Int, masked : Bool }


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


{-| Where the cursor goes before each character and after the last, in pixels from the
start of the text.
-}
carets : Int -> Style -> State -> List Int
carets pixelScale style state =
    Sprite.caretPositions pixelScale style.font (shownText style state.text)


caretX : List Int -> Int -> Int
caretX positions index =
    List.drop index positions |> List.head |> Maybe.withDefault 0


caretWidth : Int -> Style -> Int
caretWidth pixelScale style =
    max 1 (Sprite.lineHeight pixelScale style.font // 20)


mouseDown : Int -> Style -> Coord -> Coord -> Model -> Model
mouseDown pixelScale style mousePosition position model =
    replaceState
        (\state ->
            { state
                | cursorPosition = cursorPosition pixelScale style mousePosition position state
                , cursorSize = 0
            }
        )
        model


{-| The caret nearest the mouse.
-}
cursorPosition : Int -> Style -> Coord -> Coord -> State -> Int
cursorPosition pixelScale style mousePosition position state =
    let
        x =
            Coord.x mousePosition - (Coord.x position + Coord.x padding + caretWidth pixelScale style) + scroll pixelScale style state
    in
    carets pixelScale style state
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


mouseDownMove : Int -> Style -> Coord -> Coord -> Model -> Model
mouseDownMove pixelScale style mousePosition position model =
    replaceState
        (\state ->
            let
                cursorPosition2 =
                    cursorPosition pixelScale style mousePosition position state
            in
            { state | cursorPosition = cursorPosition2 }
                |> setCursorSize (state.cursorSize + (state.cursorPosition - cursorPosition2))
        )
        model


padding : Coord
padding =
    Coord.xy 4 4


size : Int -> Style -> Coord
size pixelScale style =
    ( style.width, Sprite.lineHeight pixelScale style.font + Coord.y padding * 2 )


{-| The pixels between the box's padding that text shows in.
-}
innerWidth : Int -> Style -> Int
innerWidth pixelScale style =
    style.width - 2 * Coord.x padding - 2 * caretWidth pixelScale style


{-| How far the text is scrolled left, in pixels: 0 unless the cursor would be past the
right edge, and then just enough to show it. (town-collab's boxes are wide enough not to
need this.)
-}
scroll : Int -> Style -> State -> Int
scroll pixelScale style state =
    max 0 (caretX (carets pixelScale style state) state.cursorPosition - innerWidth pixelScale style)


view : Int -> Style -> Coord -> Bool -> Bool -> State -> List Triangle
view pixelScale style offset hasFocus isValid current =
    let
        positions =
            carets pixelScale style current

        ( x, y ) =
            offset

        textLeft =
            x + Coord.x padding + caretWidth pixelScale style - scroll pixelScale style current

        clip =
            { left = x + Coord.x padding, right = x + style.width - Coord.x padding }

        lineHeight =
            Sprite.lineHeight pixelScale style.font

        selectionStart =
            textLeft + caretX positions (min current.cursorPosition (current.cursorPosition + current.cursorSize))

        selectionEnd =
            textLeft + caretX positions (max current.cursorPosition (current.cursorPosition + current.cursorSize))
    in
    Sprite.rectangle
        (if not isValid then
            Color.errorColor

         else if hasFocus then
            Color.highlightColor

         else
            Color.outlineColor
        )
        offset
        (size pixelScale style)
        ++ Sprite.rectangle
            (if hasFocus then
                Color.highlightColor

             else
                Color.fillColor3
            )
            (offset |> Coord.plus padding)
            (size pixelScale style |> Coord.minus (Coord.scalar 2 padding))
        ++ (if current.cursorSize == 0 || not hasFocus then
                []

            else
                Sprite.rectangle
                    (Color.rgb255 170 210 255)
                    ( max clip.left selectionStart, y + Coord.y padding )
                    ( min clip.right selectionEnd - max clip.left selectionStart, lineHeight )
           )
        ++ Sprite.clippedText pixelScale Color.black style.font (Just clip) (shownText style current.text) ( textLeft, y + Coord.y padding )
        ++ (if hasFocus then
                Sprite.rectangle Color.black
                    ( textLeft + caretX positions current.cursorPosition - caretWidth pixelScale style, y + Coord.y padding )
                    ( caretWidth pixelScale style, lineHeight )

            else
                []
           )
