module Evergreen.V8.DoomControls exposing (..)

{-| The types from DoomControls that the Model was made of in version 8, frozen by
tools/wire (`make migration`) so that a Model saved by version 8 can still be read
and migrated. Don't change them.

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
