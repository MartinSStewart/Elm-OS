module Evergreen.V22.Code exposing (..)

{-| The Code app: Elm OS's own Elm modules, coloured as code (ElmSyntax.elm), to read
and change.

The modules as Elm OS was built from them are in SourceCode.elm. Saving a module keeps
its new text in `saved`, which is part of the Model, so it lasts across restarts.

Build sends every module (saved or as built) to the host, which compiles Elm OS on this
computer and switches to the new build, carrying the Model over (host/init/src/build.rs).
It refuses a build whose Model has other types: that would need a migration.

Commit and push sends the saved modules to GitHub as a commit (Code/GitHub.elm).

-}

import Evergreen.V21.Color
import Evergreen.V21.Coord exposing (Coord)
import Evergreen.V21.Effect
import Evergreen.V21.Sprite
import Evergreen.V21.TextInput
import Evergreen.V21.TextInputMultiline
import Evergreen.V21.Ui exposing (Element)
import Evergreen.V21.Units exposing (UiPixels)
import Evergreen.V22.Code.Index
import Evergreen.V22.Code.Types exposing (BuildStatus(..), Git, GitStatus(..), Place, UiId(..), UsageList)
import Evergreen.V22.UiId
import Json.Encode as E
import Quantity exposing (Quantity)
import SeqDict exposing (SeqDict)


type alias Model =
    { isOpen : Bool

    -- The module being edited, by name.
    , module_ : Maybe String

    -- Modules whose text was changed and saved, by name.
    , saved : SeqDict String String

    -- The last build asked for, as the host last said it was going.
    , build : Maybe BuildStatus

    -- The last build's errors show instead of the text.
    , showErrors : Bool

    -- What a commit would hold, the token, the message and Push show instead of the text.
    , committing : Bool
    , git : Git

    -- The find and replace bar shows over the code (what is typed in it is in the UI's
    -- state, under FindInput and ReplaceInput).
    , finding : Bool

    -- Where the cursor jumped from, newest first, and where it was before going back
    -- through them (Alt+Shift+Left and Right). `lastPlace` is where it was after the last
    -- event, to tell when it moves far.
    , back : List Place
    , forward : List Place
    , lastPlace : Maybe Place

    -- Where a definition is used, shown under the code after Ctrl+click on it.
    , usages : Maybe UsageList
    }



-- FIND AND REPLACE
-- CURSOR HISTORY
-- GO TO DEFINITION AND USAGES
-- VIEW
