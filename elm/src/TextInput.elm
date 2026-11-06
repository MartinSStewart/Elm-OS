module TextInput exposing
    ( Model
    , OutMsg(..)
    , State
    , init
    , keyMsg
    , mouseDown
    , mouseDownMove
    , padding
    , paste
    , replaceState
    , size
    , view
    )

{-| town-collab's single-line text input (src/TextInput.elm in
github.com/MartinSStewart/town-collab), ported to Elm OS: Coord is a plain (Int, Int),
widths are plain Ints, it draws triangles for the render port, Home and End move to the
ends, and text wider than the box scrolls to keep the cursor in view.
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


mouseDown : Int -> Int -> Coord -> Coord -> Model -> Model
mouseDown textScale width mousePosition position model =
    replaceState
        (\state ->
            { state
                | cursorPosition = cursorPosition textScale width mousePosition position state
                , cursorSize = 0
            }
        )
        model


cursorPosition : Int -> Int -> Coord -> Coord -> State -> Int
cursorPosition textScale width mousePosition position state =
    let
        mouseX : Int
        mouseX =
            Coord.x mousePosition

        paddingX : Int
        paddingX =
            Coord.x padding

        positionX : Int
        positionX =
            Coord.x position
    in
    toFloat (mouseX - (positionX + paddingX + textScale))
        / toFloat (Coord.x Sprite.charSize * textScale)
        |> round
        |> (+) (scroll textScale width state)
        |> clamp 0 (String.length state.text)


mouseDownMove : Int -> Int -> Coord -> Coord -> Model -> Model
mouseDownMove textScale width mousePosition position model =
    replaceState
        (\state ->
            let
                cursorPosition2 =
                    cursorPosition textScale width mousePosition position state
            in
            { state | cursorPosition = cursorPosition2 }
                |> setCursorSize (state.cursorSize + (state.cursorPosition - cursorPosition2))
        )
        model


padding : Coord
padding =
    Coord.xy 4 4


size : Int -> Int -> Coord
size textScale width =
    ( width, Coord.y Sprite.charSize * textScale + Coord.y padding * 2 )


{-| How many characters fit in the box.
-}
visibleChars : Int -> Int -> Int
visibleChars textScale width =
    (width - 2 * Coord.x padding - 2 * textScale) // (Coord.x Sprite.charSize * textScale) |> max 1


{-| The first character shown: 0 unless the text is wider than the box, and then far
enough along that the cursor is in view. (town-collab's boxes are wide enough not to
need this.)
-}
scroll : Int -> Int -> State -> Int
scroll textScale width state =
    let
        visible =
            visibleChars textScale width
    in
    if String.length state.text < visible then
        0

    else
        clamp 0 (String.length state.text - visible + 1) (state.cursorPosition - visible + 1)


view : Int -> Coord -> Int -> Bool -> Bool -> State -> List Triangle
view textScale offset width hasFocus isValid current0 =
    let
        first =
            scroll textScale width current0

        visible =
            visibleChars textScale width

        -- The part of the text in view, with the cursor and selection moved to match.
        current =
            { text = String.slice first (first + visible) current0.text
            , cursorPosition = current0.cursorPosition - first
            , cursorSize =
                clamp (first - current0.cursorPosition)
                    (first + visible - current0.cursorPosition)
                    current0.cursorSize
            }
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
        (size textScale width)
        ++ Sprite.rectangle
            (if hasFocus then
                Color.highlightColor

             else
                Color.fillColor3
            )
            (offset |> Coord.plus padding)
            (size textScale width |> Coord.minus (Coord.scalar 2 padding))
        ++ (if current.cursorSize == 0 || not hasFocus then
                []

            else
                Sprite.rectangle
                    (Color.rgb255 170 210 255)
                    (offset
                        |> Coord.plus
                            (Coord.xy
                                (min current.cursorPosition (current.cursorPosition + current.cursorSize)
                                    * Coord.x Sprite.charSize
                                    * textScale
                                    + Coord.x padding
                                )
                                (Coord.y padding)
                            )
                    )
                    (Coord.xy
                        (Coord.x Sprite.charSize * textScale * abs current.cursorSize)
                        (Coord.y Sprite.charSize * textScale)
                    )
           )
        ++ Sprite.text Color.black textScale current.text (offset |> Coord.plus padding |> Coord.plus (Coord.xy textScale 0))
        ++ (if hasFocus then
                Sprite.rectangle Color.black
                    (offset
                        |> Coord.plus
                            (Coord.xy (current.cursorPosition * Coord.x Sprite.charSize * textScale + Coord.x padding) (Coord.y padding))
                    )
                    (Coord.xy
                        textScale
                        (Coord.y Sprite.charSize * textScale)
                    )

            else
                []
           )
