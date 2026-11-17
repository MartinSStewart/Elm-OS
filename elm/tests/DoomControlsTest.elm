module DoomControlsTest exposing (suite)

import Doom.Event as Event
import Doom.Config
import DoomControls exposing (Action(..))
import Expect
import Fuzz
import Test exposing (Test, describe, fuzz2, test)


{-| The keys (or buttons) of the actions of `action`'s kind, with `action`'s as `f`
makes it.
-}
codes : Action -> (Int -> Int) -> DoomControls.Bindings -> List Int
codes action f bindings =
    DoomControls.actions
        |> List.filter (\a -> DoomControls.input a == DoomControls.input action)
        |> List.map
            (\a ->
                if a == action then
                    f (DoomControls.get a bindings)

                else
                    DoomControls.get a bindings
            )


{-| The codes of one kind (keys or buttons) that are bound, each once.
-}
noneShared : DoomControls.Bindings -> Bool
noneShared bindings =
    let
        bound kind =
            DoomControls.actions
                |> List.filter (\action -> DoomControls.input action == kind)
                |> List.map (\action -> DoomControls.get action bindings)
                |> List.filter (\code -> code /= DoomControls.none)

        unique list =
            List.length list
                == List.length
                    (List.foldl
                        (\x acc ->
                            if List.member x acc then
                                acc

                            else
                                x :: acc
                        )
                        []
                        list
                    )
    in
    unique (bound DoomControls.Key) && unique (bound DoomControls.Button)


suite : Test
suite =
    describe "DoomControls"
        [ test "Classic is DOS Doom's defaults (Doom.Config.defaultBindings)"
            (\_ -> DoomControls.classic |> Expect.equal Doom.Config.defaultBindings)
        , test "Modern: WASD, E uses, the left button fires, the other buttons do nothing"
            (\_ ->
                List.map (\action -> DoomControls.bindingName action DoomControls.modern)
                    [ Forward, Back, StrafeLeft, StrafeRight, TurnLeft, TurnRight, Use, Run, Fire, MouseFire, MouseStrafe, MouseForward ]
                    |> Expect.equal [ "W", "S", "A", "D", "Left arrow", "Right arrow", "E", "Shift", "Ctrl", "Left button", "None", "None" ]
            )
        , test "binding a free key changes only that action"
            (\_ ->
                DoomControls.bind StrafeLeft (Char.toCode 'a') DoomControls.classic
                    |> Expect.equal { classic | strafeLeft = Char.toCode 'a' }
            )
        , test "binding a key in use swaps: the other action gets the old key"
            (\_ ->
                DoomControls.bind StrafeLeft Event.keyLeftArrow DoomControls.classic
                    |> Expect.equal { classic | strafeLeft = Event.keyLeftArrow, left = Char.toCode ',' }
            )
        , test "binding an action its own key changes nothing"
            (\_ -> DoomControls.bind Fire Event.keyRCtrl DoomControls.classic |> Expect.equal DoomControls.classic)
        , test "mouse buttons swap among the mouse's actions, not with keys"
            (\_ ->
                DoomControls.bind MouseFire 1 DoomControls.classic
                    |> Expect.equal { classic | mouseFire = 1, mouseStrafe = 0 }
            )
        , test "a button bound where none was leaves the other action with none"
            (\_ ->
                DoomControls.bind MouseStrafe 0 DoomControls.modern
                    |> Expect.equal { modern | mouseStrafe = 0, mouseFire = DoomControls.none }
            )
        , test "unbind"
            (\_ -> DoomControls.unbind Use DoomControls.classic |> DoomControls.bindingName Use |> Expect.equal "None")
        , fuzz2 (Fuzz.intRange 0 12)
            (Fuzz.intRange 0 255)
            "any binding keeps keys unshared and the other codes in place"
            (\i code ->
                let
                    action =
                        List.drop i DoomControls.actions |> List.head |> Maybe.withDefault Fire

                    c =
                        case DoomControls.input action of
                            DoomControls.Key ->
                                code

                            DoomControls.Button ->
                                modBy 3 code

                    before =
                        codes action identity DoomControls.modern
                in
                DoomControls.bind action c DoomControls.modern
                    |> Expect.all
                        [ \b -> Expect.equal True (noneShared b)
                        , \b -> DoomControls.get action b |> Expect.equal c
                        , \b ->
                            -- A code in use is swapped, so the same codes are all there;
                            -- a new one takes the place of the action's old one.
                            List.sort (codes action identity b)
                                |> Expect.equal
                                    (List.sort
                                        (if List.member c before then
                                            before

                                         else
                                            codes action (\_ -> c) DoomControls.modern
                                        )
                                    )
                        ]
            )
        , test "key names"
            (\_ ->
                List.map DoomControls.keyName
                    [ Event.keyUpArrow, Event.keyRCtrl, Event.keyRAlt, Event.keyRShift, 32, Char.toCode 'a', Char.toCode ',', Event.keyF1, Event.keyF10, Event.keyF12, Event.keyEnter, Event.keyTab, Event.keyPause, -1, 200 ]
                    |> Expect.equal [ "Up arrow", "Ctrl", "Alt", "Shift", "Space", "A", ",", "F1", "F10", "F12", "Enter", "Tab", "Pause", "None", "Key 200" ]
            )
        , test "button names"
            (\_ -> List.map DoomControls.buttonName [ 0, 1, 2, -1 ] |> Expect.equal [ "Left button", "Right button", "Middle button", "None" ])
        ]


classic : DoomControls.Bindings
classic =
    DoomControls.classic


modern : DoomControls.Bindings
modern =
    DoomControls.modern
