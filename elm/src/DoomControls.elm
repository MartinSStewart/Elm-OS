module DoomControls exposing
    ( Action(..)
    , Bindings
    , Input(..)
    , actionName
    , actions
    , bind
    , bindingName
    , buttonName
    , classic
    , get
    , input
    , keyName
    , modern
    , none
    , unbind
    )

{-| Doom's controls as the Doom app's Controls panel changes them: which key or mouse
button does what. DOS Doom had no way to change them in the game (its setup program
did, outside it), so the panel is the app's, around the game, which keeps Doom's own
menus and frames the original's.

The bindings are `Doom.Config.Bindings`, by Doom's key codes (Doom.Event) and mouse
buttons (0 left, 1 right, 2 middle); `none` (-1) is no key or button: Doom reads
nothing for it.

Binding a key (or button) that another action has swaps the two: the other action
gets this one's old key. So every action keeps a key it had, and two actions never
share one, which would make one key do both.

-}

import Doom.Event as Event



-- The same record as Doom.Config.Bindings (tools/wire saves only Elm OS's own types;
-- Elm's records are the same type when their fields are, so it goes to Doom as it is).


type alias Bindings =
    { right : Int
    , left : Int
    , up : Int
    , down : Int
    , strafeLeft : Int
    , strafeRight : Int
    , fire : Int
    , use : Int
    , strafe : Int
    , speed : Int
    , mouseFire : Int
    , mouseStrafe : Int
    , mouseForward : Int
    }


{-| What can be bound: the keyboard's actions, and the mouse buttons'.
-}
type Action
    = Forward
    | Back
    | TurnLeft
    | TurnRight
    | StrafeLeft
    | StrafeRight
    | Fire
    | Use
    | Run
    | StrafeOn
    | MouseFire
    | MouseStrafe
    | MouseForward


{-| Whether an action takes a key or a mouse button.
-}
type Input
    = Key
    | Button


actions : List Action
actions =
    [ Forward, Back, TurnLeft, TurnRight, StrafeLeft, StrafeRight, Fire, Use, Run, StrafeOn, MouseFire, MouseStrafe, MouseForward ]


input : Action -> Input
input action =
    case action of
        MouseFire ->
            Button

        MouseStrafe ->
            Button

        MouseForward ->
            Button

        _ ->
            Key


{-| No key or button.
-}
none : Int
none =
    -1


{-| DOS Doom's defaults (m\_misc.c, as Doom.Config.defaultBindings): the arrows move
and turn, ',' and '.' strafe, Ctrl fires, Space uses, Alt held makes the turning keys
and the mouse strafe, Shift runs; the left button fires, the right one strafes, the
middle one moves forward.
-}
classic : Bindings
classic =
    { right = Event.keyRightArrow
    , left = Event.keyLeftArrow
    , up = Event.keyUpArrow
    , down = Event.keyDownArrow
    , strafeLeft = Char.toCode ','
    , strafeRight = Char.toCode '.'
    , fire = Event.keyRCtrl
    , use = Char.toCode ' '
    , strafe = Event.keyRAlt
    , speed = Event.keyRShift
    , mouseFire = 0
    , mouseStrafe = 1
    , mouseForward = 2
    }


{-| As games have played since: W and S move, A and D strafe, the mouse turns and
its left button fires, E uses, Shift runs, the arrows still turn, Ctrl still fires.
Doom 1.9 has no mouse button for "use" (its ticcmd reads only fire, strafe and
forward buttons), so the right and middle buttons do nothing here, rather than
turning the mouse's turning into strafing.
-}
modern : Bindings
modern =
    { classic
        | up = Char.toCode 'w'
        , down = Char.toCode 's'
        , strafeLeft = Char.toCode 'a'
        , strafeRight = Char.toCode 'd'
        , use = Char.toCode 'e'
        , mouseStrafe = none
        , mouseForward = none
    }


get : Action -> Bindings -> Int
get action b =
    case action of
        Forward ->
            b.up

        Back ->
            b.down

        TurnLeft ->
            b.left

        TurnRight ->
            b.right

        StrafeLeft ->
            b.strafeLeft

        StrafeRight ->
            b.strafeRight

        Fire ->
            b.fire

        Use ->
            b.use

        Run ->
            b.speed

        StrafeOn ->
            b.strafe

        MouseFire ->
            b.mouseFire

        MouseStrafe ->
            b.mouseStrafe

        MouseForward ->
            b.mouseForward


set : Action -> Int -> Bindings -> Bindings
set action code b =
    case action of
        Forward ->
            { b | up = code }

        Back ->
            { b | down = code }

        TurnLeft ->
            { b | left = code }

        TurnRight ->
            { b | right = code }

        StrafeLeft ->
            { b | strafeLeft = code }

        StrafeRight ->
            { b | strafeRight = code }

        Fire ->
            { b | fire = code }

        Use ->
            { b | use = code }

        Run ->
            { b | speed = code }

        StrafeOn ->
            { b | strafe = code }

        MouseFire ->
            { b | mouseFire = code }

        MouseStrafe ->
            { b | mouseStrafe = code }

        MouseForward ->
            { b | mouseForward = code }


{-| Bind a key (a key action) or a mouse button (a button action) to an action. An
action of the same kind that had it gets this action's old one instead (a swap).
-}
bind : Action -> Int -> Bindings -> Bindings
bind action code b =
    let
        old =
            get action b
    in
    List.foldl
        (\other acc ->
            if other /= action && input other == input action && get other b == code then
                set other old acc

            else
                acc
        )
        (set action code b)
        actions


{-| No key or button for the action.
-}
unbind : Action -> Bindings -> Bindings
unbind action =
    set action none


actionName : Action -> String
actionName action =
    case action of
        Forward ->
            "Forward"

        Back ->
            "Back"

        TurnLeft ->
            "Turn left"

        TurnRight ->
            "Turn right"

        StrafeLeft ->
            "Strafe left"

        StrafeRight ->
            "Strafe right"

        Fire ->
            "Fire"

        Use ->
            "Use"

        Run ->
            "Run"

        StrafeOn ->
            "Strafe on (hold)"

        MouseFire ->
            "Fire (mouse)"

        MouseStrafe ->
            "Strafe on (mouse)"

        MouseForward ->
            "Forward (mouse)"


{-| What the action is bound to, by name.
-}
bindingName : Action -> Bindings -> String
bindingName action b =
    case input action of
        Key ->
            keyName (get action b)

        Button ->
            buttonName (get action b)


{-| A Doom key code's name, as the keyboard says it.
-}
keyName : Int -> String
keyName code =
    if code == Event.keyRightArrow then
        "Right arrow"

    else if code == Event.keyLeftArrow then
        "Left arrow"

    else if code == Event.keyUpArrow then
        "Up arrow"

    else if code == Event.keyDownArrow then
        "Down arrow"

    else if code == Event.keyRCtrl then
        "Ctrl"

    else if code == Event.keyRAlt then
        "Alt"

    else if code == Event.keyRShift then
        "Shift"

    else if code == Event.keyEscape then
        "Esc"

    else if code == Event.keyEnter then
        "Enter"

    else if code == Event.keyTab then
        "Tab"

    else if code == Event.keyBackspace then
        "Backspace"

    else if code == Event.keyPause then
        "Pause"

    else if code == Event.keyCapsLock then
        "Caps Lock"

    else if code == Event.keyScrollLock then
        "Scroll Lock"

    else if code == Event.keyNumLock then
        "Num Lock"

    else if code == Event.keyF11 then
        "F11"

    else if code == Event.keyF12 then
        "F12"

    else if code >= Event.keyF1 && code <= Event.keyF10 then
        "F" ++ String.fromInt (code - Event.keyF1 + 1)

    else if code == 32 then
        "Space"

    else if code > 32 && code < 127 then
        String.toUpper (String.fromChar (Char.fromCode code))

    else if code < 0 then
        "None"

    else
        "Key " ++ String.fromInt code


buttonName : Int -> String
buttonName b =
    case b of
        0 ->
            "Left button"

        1 ->
            "Right button"

        2 ->
            "Middle button"

        _ ->
            "None"
