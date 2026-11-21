module Evergreen.V19.Code exposing (..)

{-| The Code app: Elm OS's own Elm modules, coloured as code (ElmSyntax.elm), to read
and change.

The modules as Elm OS was built from them are in SourceCode.elm. Saving a module keeps
its new text in `saved`, which is part of the Model, so it lasts across restarts.

Build sends every module (saved or as built) to the host, which compiles Elm OS on this
computer and switches to the new build, carrying the Model over (host/init/src/build.rs).
It refuses a build whose Model has other types: that would need a migration.

Commit and push sends the saved modules to GitHub as a commit (Code/GitHub.elm).

-}

import Evergreen.V19.Code.Types exposing (BuildStatus(..), Git, GitStatus(..), UiId(..))
import Evergreen.V19.Color
import Evergreen.V19.Coord exposing (Coord)
import Evergreen.V19.Effect
import Evergreen.V19.Sprite
import Evergreen.V19.TextInputMultiline
import Evergreen.V19.Ui exposing (Element)
import Evergreen.V19.UiId
import Evergreen.V19.Units exposing (UiPixels)
import Json.Encode as E
import Quantity exposing (Quantity)
import SeqDict exposing (SeqDict)


type alias Model =
    { isOpen : Bool

    -- The list of modules shows instead of the text.
    , picking : Bool

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
    }



-- VIEW
