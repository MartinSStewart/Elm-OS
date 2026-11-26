module Evergreen.V24.ModelViewer exposing (..)

{-| The Model viewer: the whole running Model as a tree, to look through and change.

Each row is a value: a record's field, a list's item, a variant's argument. Click a
record, list or custom type to open it; an open custom type also shows the variants
that hold nothing as buttons, which change it to that variant. Click a number, string
or character to change it: type the new value and press Enter.

The tree comes from elm/src/Generated/ModelTree.elm, which tools/wire writes from the
Model's types (see ModelTree.elm). An opaque type shows as its name, unless its module
says how to show it.

A change is made by a click or a key, which the host logs like any other, so it is
replayed after a restart like the rest of the Model. But nothing checks it: a value the
code never expected (a cursor past the end of its text, say) is saved all the same.

-}

import Evergreen.V21.Color exposing (Color)
import Evergreen.V21.Coord exposing (Coord)
import Evergreen.V21.Sprite
import Evergreen.V21.TextInput
import Evergreen.V21.Ui
import Evergreen.V21.Units exposing (UiPixels)
import Evergreen.V24.ModelViewer.Types exposing (UiId(..))
import Evergreen.V24.UiId
import Set exposing (Set)


type alias Model =
    { isOpen : Bool

    -- The values shown open, by their paths (see ModelTree.at).
    , expanded : Set (List Int)

    -- The value being edited, in the edit box (ModelViewer.Types.EditInput), and whether
    -- the text in it was refused.
    , editing : Maybe { path : List Int, refused : Bool }
    }


init : Model
init =
    { isOpen = False
    , expanded = Set.empty
    , editing = Nothing
    }
