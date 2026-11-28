module Code exposing
    ( Model
    , afterEvent
    , appSize
    , awaitedCommit
    , buildUpdate
    , ctrlClick
    , cursorBack
    , cursorForward
    , findChanged
    , findKeyDown
    , findShown
    , findText
    , forgetPushed
    , githubToken
    , httpResponse
    , init
    , onClick
    , openFind
    , programStarted
    , save
    , saveShown
    , style
    , syncSearch
    , testFact
    , uncommittedChanges
    , uncommittedModules
    , view
    )

{-| The Code app: Elm OS's own Elm modules, coloured as code (ElmSyntax.elm), to read
and change.

The modules as Elm OS was built from them are in SourceCode.elm. Saving a module keeps
its new text in `saved`, which is part of the Model, so it lasts across restarts.

Build sends every module (saved or as built) to the host, which compiles Elm OS on this
computer and switches to the new build, carrying the Model over (host/init/src/build.rs).
It refuses a build whose Model has other types: that would need a migration.

Commit and push sends the saved modules to GitHub as a commit (Code/GitHub.elm).

-}

import App
import BuildInfo
import Code.GitHub
import Code.Index
import Code.Types exposing (BuildStatus(..), Git, GitStatus(..), Place, UiId(..), UsageList)
import CodeEditor
import Color
import Coord exposing (Coord)
import Effect exposing (Effect)
import Formatter
import Json.Encode as E
import Keyboard
import Quantity exposing (Quantity)
import SeqDict exposing (SeqDict)
import SourceCode
import Sprite
import TextInput
import Ui exposing (Element)
import UiId
import Units exposing (UiPixels)


type alias Model =
    { isOpen : Bool

    -- Elm OS runs a build made here (from the Code app's edits), as the host last said.
    , local : Bool

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


init : Model
init =
    { isOpen = False
    , local = False
    , module_ = Nothing
    , saved = SeqDict.empty
    , build = Nothing
    , showErrors = False
    , committing = False
    , git = Code.GitHub.init
    , finding = False
    , back = []
    , forward = []
    , lastPlace = Nothing
    , usages = Nothing
    }


{-| A module's text: as saved here, or as Elm OS was built.
-}
moduleText : String -> Model -> Maybe String
moduleText name model =
    case SeqDict.get name model.saved of
        Just text ->
            Just text

        Nothing ->
            SeqDict.get name SourceCode.sourceCode


{-| Whether the module was changed and saved here.
-}
isEdited : String -> SeqDict String String -> Bool
isEdited name saved =
    SeqDict.member name saved


{-| Whether a saved module differs from what the running build was made from
(SourceCode.elm, which a build made here has too): if none does, building would only
make the running program again.
-}
differsFromRunning : Model -> Bool
differsFromRunning model =
    SeqDict.foldl (\name text acc -> acc || SeqDict.get name SourceCode.sourceCode /= Just text) False model.saved


{-| The saved modules whose text isn't what the last push committed: changes no commit has.
(Even when the running build was made from them.)
-}
uncommittedModules : Model -> List String
uncommittedModules model =
    List.map Tuple.first (uncommittedChanges model)


{-| `uncommittedModules` with their texts.
-}
uncommittedChanges : Model -> List ( String, String )
uncommittedChanges model =
    SeqDict.foldr
        (\name text changes ->
            if SeqDict.get name model.git.pushed /= Just text then
                ( name, text ) :: changes

            else
                changes
        )
        []
        model.saved


{-| Saves the text box's text, formatted (Formatter) when it parses, and shows the
formatted text in the box (one change to undo).
-}
saveShown : CodeEditor.Style -> Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId )
saveShown boxStyle uiState model =
    let
        editor : CodeEditor.Model
        editor =
            Ui.getCodeEditor (UiId.Code Input) uiState

        text : String
        text =
            CodeEditor.text editor

        formatted : String
        formatted =
            Formatter.format text |> Maybe.withDefault text
    in
    ( saveText formatted model
    , Ui.insertElement (UiId.Code Input) (Ui.CodeEditorState (CodeEditor.replaceAll boxStyle formatted editor |> CodeEditor.markSaved)) uiState
    )


{-| Keeps `text`, formatted (Formatter) when it parses, as the module's new text, or
forgets the change if it is the text Elm OS was built from. Not while running a build made
here: its modules are the edits, and the saved ones are still changes to commit (the commit
goes on top of the commit it was made from).
-}
save : String -> Model -> Model
save text model =
    saveText (Formatter.format text |> Maybe.withDefault text) model


saveText : String -> Model -> Model
saveText text model =
    case model.module_ of
        Just name ->
            if SeqDict.get name SourceCode.sourceCode == Just text && not model.local then
                { model | saved = SeqDict.remove name model.saved }

            else
                { model | saved = SeqDict.insert name text model.saved }

        Nothing ->
            model


{-| A click on one of the app's elements. Opening a module puts its text in the text
box, so this takes and gives the UI's state too, and the text box's current text.
-}
onClick : UiId -> CodeEditor.Style -> Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId, List Effect )
onClick id boxStyle uiState model =
    case id of
        OpenButton ->
            ( { model | isOpen = not model.isOpen }
            , if model.isOpen || model.module_ == Nothing then
                uiState

              else
                Ui.setFocus (Just (UiId.Code Input)) uiState
            , []
            )

        Window ->
            -- A click around the text still types into it.
            if model.module_ == Nothing || model.showErrors || model.committing then
                ( model, uiState, [] )

            else
                ( model, Ui.setFocus (Just (UiId.Code Input)) uiState, [] )

        Input ->
            ( model, uiState, [] )

        CloseButton ->
            ( { model | isOpen = False }, uiState, [] )

        ModulesViewport ->
            ( model, uiState, [] )

        ModuleButton name ->
            openModule name (CodeEditor.text (Ui.getCodeEditor (UiId.Code Input) uiState)) uiState model

        SaveButton ->
            let
                ( saved, newUiState ) =
                    saveShown boxStyle uiState model
            in
            ( saved, newUiState, [] )

        RevertButton ->
            case model.module_ of
                Just name ->
                    load name uiState { model | saved = SeqDict.remove name model.saved }

                Nothing ->
                    ( model, uiState, [] )

        BuildButton ->
            -- What's in the text box is built, saved first. While a build is going the
            -- host refuses another.
            let
                ( saved, savedUiState ) =
                    if model.module_ == Nothing then
                        ( model, uiState )

                    else
                        saveShown boxStyle uiState model
            in
            if differsFromRunning saved then
                ( { saved | build = Just (BuildRunning "Starting"), showErrors = False }
                , savedUiState
                , [ Effect.Build (buildModules saved) ]
                )

            else
                -- Every module is as the running build was made from: building would
                -- make the same program again and switch to it, for nothing.
                ( { saved | build = Nothing, showErrors = False }, savedUiState, [] )

        DeployedButton ->
            ( { model | build = Just (BuildRunning goingBack), showErrors = False }, uiState, [ Effect.FollowDeployed ] )

        ErrorsCloseButton ->
            ( { model | showErrors = False }, uiState, [] )

        ErrorsViewport ->
            ( model, uiState, [] )

        CommitButton ->
            let
                ( saved, savedUiState ) =
                    if model.module_ == Nothing then
                        ( model, uiState )

                    else
                        saveShown boxStyle uiState model
            in
            ( { saved | committing = True, showErrors = False }
            , Ui.setFocus
                (Just
                    (UiId.Code
                        (if inputText TokenInput uiState == "" then
                            TokenInput

                         else
                            MessageInput
                        )
                    )
                )
                savedUiState
            , []
            )

        CommitCloseButton ->
            ( { model | committing = False }, Ui.setFocus Nothing uiState, [] )

        CommitViewport ->
            ( model, uiState, [] )

        TokenInput ->
            ( model, Ui.setFocus (Just (UiId.Code TokenInput)) uiState, [] )

        MessageInput ->
            ( model, Ui.setFocus (Just (UiId.Code MessageInput)) uiState, [] )

        PushButton ->
            push uiState model

        FindInput ->
            ( model, Ui.setFocus (Just (UiId.Code FindInput)) uiState, [] )

        ReplaceInput ->
            ( model, Ui.setFocus (Just (UiId.Code ReplaceInput)) uiState, [] )

        FindPreviousButton ->
            ( model, find boxStyle False uiState, [] )

        FindNextButton ->
            ( model, find boxStyle True uiState, [] )

        ReplaceButton ->
            ( model, replace boxStyle uiState, [] )

        ReplaceAllButton ->
            ( model, replaceAll boxStyle uiState, [] )

        FindCloseButton ->
            ( closeFind model, Ui.setFocus (Just (UiId.Code Input)) uiState, [] )

        UsagesViewport ->
            ( model, uiState, [] )

        UsageButton index ->
            case model.usages |> Maybe.andThen (\list -> List.drop index list.found |> List.head) of
                Just usage ->
                    let
                        ( model2, uiState2 ) =
                            jump boxStyle { module_ = usage.module_, position = usage.position, line = usage.line } uiState model
                    in
                    ( model2, uiState2, [] )

                Nothing ->
                    ( model, uiState, [] )

        UsagesCloseButton ->
            ( { model | usages = Nothing }, Ui.setFocus (Just (UiId.Code Input)) uiState, [] )



-- FIND AND REPLACE


{-| Whether the find and replace bar shows: only over the code of a module.
-}
findShown : Model -> Bool
findShown model =
    model.finding && not model.showErrors && not model.committing && model.module_ /= Nothing


{-| Ctrl+F: shows the bar (or goes back to it), with what is selected in the code, if it is
one line, as what to find, all selected so that typing replaces it.
-}
openFind : Coord UiPixels -> Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId )
openFind windowSize uiState model =
    let
        editor : CodeEditor.Model
        editor =
            Ui.getCodeEditor (UiId.Code Input) uiState

        selected : String
        selected =
            CodeEditor.selectedText editor

        needle : String
        needle =
            if selected /= "" && not (String.contains "\n" selected) then
                selected

            else
                inputText FindInput uiState

        -- The bar takes some of the code's lines, so the cursor may be hidden now.
        shown : CodeEditor.Style
        shown =
            style windowSize { model | finding = True }
    in
    ( { model | finding = True }
    , uiState
        |> Ui.insertElement
            (UiId.Code FindInput)
            (Ui.TextInputState
                { current = { text = needle, cursorPosition = String.length needle, cursorSize = -(String.length needle) }
                , undoHistory = []
                , redoHistory = []
                , lastClick = Nothing
                }
            )
        |> Ui.insertElement
            (UiId.Code Input)
            (Ui.CodeEditorState (CodeEditor.select shown (min editor.cursorPosition (editor.cursorPosition + editor.cursorSize)) (max editor.cursorPosition (editor.cursorPosition + editor.cursorSize)) (CodeEditor.search needle editor)))
        |> Ui.setFocus (Just (UiId.Code FindInput))
    )


closeFind : Model -> Model
closeFind model =
    { model | finding = False }


{-| A key pressed in the find or replace box (`focus`), before the box gets it: Escape
closes the bar, Enter in the find box goes to the next match (Shift+Enter the previous) and
in the replace box replaces the current one. Nothing for the other keys.
-}
findKeyDown : CodeEditor.Style -> Bool -> Bool -> Keyboard.Key -> Model -> Ui.Model UiId.UiId -> Maybe ( Model, Ui.Model UiId.UiId )
findKeyDown boxStyle inFindBox shift key model uiState =
    case key of
        Keyboard.Escape ->
            Just ( closeFind model, Ui.setFocus (Just (UiId.Code Input)) uiState )

        Keyboard.Enter ->
            if inFindBox then
                Just ( model, find boxStyle (not shift) uiState )

            else
                Just ( model, replace boxStyle uiState )

        _ ->
            Nothing


{-| The text box, searching for the find box's text.
-}
searched : Ui.Model UiId.UiId -> CodeEditor.Model
searched uiState =
    CodeEditor.search (inputText FindInput uiState) (Ui.getCodeEditor (UiId.Code Input) uiState)


{-| After every event: the text box marks the find box's text while the bar shows, and
nothing while it doesn't.
-}
syncSearch : Model -> Ui.Model UiId.UiId -> Ui.Model UiId.UiId
syncSearch model uiState =
    let
        editor : CodeEditor.Model
        editor =
            Ui.getCodeEditor (UiId.Code Input) uiState

        needle : String
        needle =
            if findShown model then
                inputText FindInput uiState

            else
                ""

        synced : CodeEditor.Model
        synced =
            CodeEditor.search needle editor
    in
    if CodeEditor.sameSearch synced editor then
        uiState

    else
        Ui.insertElement (UiId.Code Input) (Ui.CodeEditorState synced) uiState


{-| Selects the next (or previous) match after the selection, wrapping around.
-}
find : CodeEditor.Style -> Bool -> Ui.Model UiId.UiId -> Ui.Model UiId.UiId
find boxStyle forward uiState =
    let
        editor : CodeEditor.Model
        editor =
            searched uiState

        found : Maybe ( Int, Int )
        found =
            if forward then
                CodeEditor.nextMatch (max editor.cursorPosition (editor.cursorPosition + editor.cursorSize)) editor

            else
                CodeEditor.previousMatch (min editor.cursorPosition (editor.cursorPosition + editor.cursorSize)) editor
    in
    case found of
        Just ( start, end ) ->
            Ui.insertElement (UiId.Code Input) (Ui.CodeEditorState (CodeEditor.select boxStyle start end editor)) uiState

        Nothing ->
            Ui.insertElement (UiId.Code Input) (Ui.CodeEditorState editor) uiState


{-| After the find box's text changed: selects the first match from the start of the
selection, so the one already selected stays while it still matches.
-}
findChanged : CodeEditor.Style -> Ui.Model UiId.UiId -> Ui.Model UiId.UiId
findChanged boxStyle uiState =
    let
        editor : CodeEditor.Model
        editor =
            searched uiState
    in
    case CodeEditor.nextMatch (min editor.cursorPosition (editor.cursorPosition + editor.cursorSize)) editor of
        Just ( start, end ) ->
            Ui.insertElement (UiId.Code Input) (Ui.CodeEditorState (CodeEditor.select boxStyle start end editor)) uiState

        Nothing ->
            Ui.insertElement (UiId.Code Input) (Ui.CodeEditorState editor) uiState


{-| Replaces the selected match with the replace box's text and selects the next one.
When what is selected isn't a match, it just goes to the next.
-}
replace : CodeEditor.Style -> Ui.Model UiId.UiId -> Ui.Model UiId.UiId
replace boxStyle uiState =
    let
        editor : CodeEditor.Model
        editor =
            searched uiState

        selection : ( Int, Int )
        selection =
            ( min editor.cursorPosition (editor.cursorPosition + editor.cursorSize), max editor.cursorPosition (editor.cursorPosition + editor.cursorSize) )
    in
    if CodeEditor.matchNumber editor /= Nothing then
        Ui.insertElement
            (UiId.Code Input)
            (Ui.CodeEditorState (CodeEditor.replaceRanges boxStyle (inputText ReplaceInput uiState) [ selection ] editor))
            uiState
            |> find boxStyle True

    else
        find boxStyle True uiState


replaceAll : CodeEditor.Style -> Ui.Model UiId.UiId -> Ui.Model UiId.UiId
replaceAll boxStyle uiState =
    Ui.insertElement
        (UiId.Code Input)
        (Ui.CodeEditorState (CodeEditor.replaceMatches boxStyle (inputText ReplaceInput uiState) (searched uiState)))
        uiState


{-| Starts committing and pushing the saved modules, with the token and message typed.
-}
push : Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId, List Effect )
push uiState model =
    let
        git =
            model.git

        token =
            String.trim (inputText TokenInput uiState)

        message =
            String.trim (inputText MessageInput uiState)

        refuse why =
            ( { model | git = { git | status = GitFailed "Starting" why } }, uiState, [] )
    in
    if gitWorking model.git then
        ( model, uiState, [] )

    else if SeqDict.isEmpty model.saved then
        refuse "No module has saved changes."

    else if token == "" then
        refuse "Type a GitHub token first."

    else if message == "" then
        refuse "Type a commit message first."

    else
        case Code.GitHub.start { token = token, message = message, modules = model.saved } model.git of
            Just ( git2, request ) ->
                ( { model | git = git2 }, uiState, [ Effect.Http request ] )

            Nothing ->
                refuse noCommitToStartFrom


noCommitToStartFrom : String
noCommitToStartFrom =
    "This build of Elm OS was made from code with changes that weren't committed, so there's no commit on GitHub to put these on top of."


{-| For when Elm OS starts a program built from the commit `commit` (BuildInfo.commit).
If it isn't the commit the last push was made on top of, it's a build made since, such
as CI's of that push: the saved modules it has as they are, and those that are as the last
push had them (the push is on GitHub, and a build of newer code must not be mixed with the
older text of a module that was pushed), aren't changes any more, so they go, with the
last push's news. Modules saved since the push stay.

Not while a build made here runs (call `programStarted` first): its SourceCode is the
saved modules, so every one of them would look like it needs no commit, although none
was pushed. (It says the commit it was made on top of, which is the last push's only
when nothing was pulled since.)

-}
forgetPushed : String -> Model -> Model
forgetPushed commit model =
    let
        git =
            model.git

        saved =
            SeqDict.filter
                (\name text ->
                    SeqDict.get name SourceCode.sourceCode
                        /= Just text
                        && SeqDict.get name git.pushed
                        /= Just text
                )
                model.saved
    in
    if model.local || commit == "" || git.from == "" || commit == git.from || saved == model.saved then
        model

    else
        { model | saved = saved, git = { git | pushed = SeqDict.empty, status = GitIdle } }


{-| The commit to wait for in the deployed builds: while a build made here runs, the last
push, if every saved module is as it had it. Once the deployed branch has it, CI has built
what runs, and the host can follow the deployed builds again without dropping any change.
-}
awaitedCommit : Model -> Maybe String
awaitedCommit model =
    case model.git.status of
        GitPushed commit _ ->
            if model.local && List.isEmpty (uncommittedModules model) then
                Just commit

            else
                Nothing

        GitIdle ->
            Nothing

        GitWorking _ ->
            Nothing

        GitFailed _ _ ->
            Nothing


{-| GitHub's answer to the request with this number (Code.GitHub.requestId).
-}
httpResponse : Int -> Result String { status : Int, body : String } -> Model -> ( Model, List Effect )
httpResponse n result model =
    case Code.GitHub.respond n result model.git of
        Code.GitHub.Next git request ->
            ( { model | git = git }, [ Effect.Http request ] )

        Code.GitHub.Finished git ->
            ( { model | git = git }, [] )


gitWorking : Git -> Bool
gitWorking git =
    case git.status of
        GitWorking _ ->
            True

        GitIdle ->
            False

        GitPushed _ _ ->
            False

        GitFailed _ _ ->
            False


{-| What is typed in the find box.
-}
findText : Ui.Model UiId.UiId -> String
findText uiState =
    inputText FindInput uiState


{-| The GitHub token typed in the commit view, if any.
-}
githubToken : Ui.Model UiId.UiId -> String
githubToken uiState =
    String.trim (inputText TokenInput uiState)


inputText : UiId -> Ui.Model UiId.UiId -> String
inputText id uiState =
    (Ui.getTextInput (UiId.Code id) uiState).current.text


{-| Every module, saved or as built, as its path under elm/src and its text. BuildInfo
is this build's own, so the new build says the same commit and branch.
-}
buildModules : Model -> List ( String, String )
buildModules model =
    SeqDict.keys SourceCode.sourceCode
        |> List.filterMap
            (\name ->
                (if name == "BuildInfo" then
                    Just buildInfoModule

                 else
                    moduleText name model
                )
                    |> Maybe.map (\text -> ( String.replace "." "/" name ++ ".elm", text ))
            )


buildInfoModule : String
buildInfoModule =
    String.join "\n"
        [ "module BuildInfo exposing (branch, commit)"
        , ""
        , "{-| Written by the Code app (Code.elm), as it was in the build it ran on. -}"
        , ""
        , ""
        , "commit : String"
        , "commit ="
        , "    " ++ E.encode 0 (E.string BuildInfo.commit)
        , ""
        , ""
        , "branch : String"
        , "branch ="
        , "    " ++ E.encode 0 (E.string BuildInfo.branch)
        , ""
        ]


{-| For Main.testFacts (the QEMU tests): the module open, the modules saved with
changes, and how the last build went.
-}
testFact : Model -> E.Value
testFact model =
    E.object
        [ ( "module", E.string (Maybe.withDefault "" model.module_) )
        , ( "edited", E.list E.string (SeqDict.keys model.saved) )
        , ( "build"
          , E.string
                (case model.build of
                    Just (BuildRunning step) ->
                        "running " ++ step

                    Just (BuildFailed step _) ->
                        "failed " ++ step

                    Just (Built name) ->
                        "built " ++ name

                    Nothing ->
                        ""
                )
          )
        , ( "git"
          , E.string
                (case model.git.status of
                    GitIdle ->
                        ""

                    GitWorking _ ->
                        "working"

                    GitPushed commit branch ->
                        "pushed " ++ commit ++ " " ++ branch

                    GitFailed step why ->
                        "failed " ++ step ++ ": " ++ why
                )
          )
        ]


{-| The step the host names while going back to the deployed build, and if that fails
(host/init/src/update.rs).
-}
goingBack : String
goingBack =
    "Going back to the deployed build"


{-| A program has started, running `build` (About.Types.SystemInfo): what was said about
another build, or about going back to the deployed one, is over. (The Model outlives
builds, so without this the line under the code kept naming a build long gone.)
-}
programStarted : String -> Model -> Model
programStarted build model =
    programStartedHelp build { model | local = String.startsWith "local-" build }


programStartedHelp : String -> Model -> Model
programStartedHelp build model =
    case model.build of
        Just (Built name) ->
            if name == build then
                model

            else
                { model | build = Nothing }

        Just (BuildRunning step) ->
            if step == goingBack then
                { model | build = Nothing }

            else
                model

        Just (BuildFailed _ _) ->
            model

        Nothing ->
            model


buildRunning : Model -> Bool
buildRunning model =
    case model.build of
        Just (BuildRunning _) ->
            True

        Just (BuildFailed _ _) ->
            False

        Just (Built _) ->
            False

        Nothing ->
            False


{-| What the host said about the build. Errors show at once.
-}
buildUpdate : BuildStatus -> Model -> Model
buildUpdate status model =
    case status of
        BuildFailed _ _ ->
            { model | build = Just status, showErrors = True, isOpen = True }

        BuildRunning _ ->
            { model | build = Just status }

        Built _ ->
            { model | build = Just status }


{-| Shows the module in the text box (when it isn't already there). The text of the module
that was open is saved first, so changing module never loses a change.
-}
openModule : String -> String -> Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId, List Effect )
openModule name text uiState model =
    if model.module_ == Just name then
        ( { model | showErrors = False, committing = False }
        , Ui.setFocus (Just (UiId.Code Input)) uiState
        , []
        )

    else
        let
            saved : Model
            saved =
                if model.module_ == Nothing then
                    model

                else
                    save text model
        in
        load name uiState { saved | module_ = Just name, committing = False }



-- CURSOR HISTORY


{-| How many places the cursor can go back through.
-}
historyLimit : Int
historyLimit =
    200


{-| How many lines the cursor moves in one go for it to count as a jump (a click, Page
Up, a search match, a change of module) and not a step (an arrow key, Enter).
-}
jumpLines : Int
jumpLines =
    3


{-| The module's name and the cursor's position in the text box, with its line.
-}
currentPlace : Ui.Model UiId.UiId -> Model -> Maybe Place
currentPlace uiState model =
    case model.module_ of
        Just name ->
            let
                editor : CodeEditor.Model
                editor =
                    Ui.getCodeEditor (UiId.Code Input) uiState
            in
            Just
                { module_ = name
                , position = editor.cursorPosition
                , line = Tuple.first (CodeEditor.cursorLineAndColumn editor)
                }

        Nothing ->
            Nothing


{-| After every event Main handles: notes where the cursor is, and if it jumped (to another
module, or `jumpLines` lines or more) from where it was after the last event, keeps that
place to go back to. A jump forgets the places to go forward to.
-}
afterEvent : Ui.Model UiId.UiId -> Model -> Model
afterEvent uiState model =
    case ( model.module_, model.lastPlace ) of
        ( Just name, Just last ) ->
            if last.module_ == name && last.position == (Ui.getCodeEditor (UiId.Code Input) uiState).cursorPosition then
                -- Not moved (most events): nothing to work out.
                model

            else
                case currentPlace uiState model of
                    Just now ->
                        if last.module_ /= now.module_ || abs (last.line - now.line) >= jumpLines then
                            { model | back = remember last model.back, forward = [], lastPlace = Just now }

                        else
                            { model | lastPlace = Just now }

                    Nothing ->
                        model

        _ ->
            { model | lastPlace = currentPlace uiState model }


remember : Place -> List Place -> List Place
remember place places =
    place :: List.take (historyLimit - 1) places


{-| Alt+Shift+Left: puts the cursor where it was before it last jumped, in that module.
-}
cursorBack : CodeEditor.Style -> Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId )
cursorBack boxStyle uiState model =
    case ( model.back, currentPlace uiState model ) of
        ( target :: older, Just now ) ->
            goTo boxStyle target uiState { model | back = older, forward = now :: model.forward }

        _ ->
            ( model, uiState )


{-| Alt+Shift+Right: goes on again to where the cursor was when it went back.
-}
cursorForward : CodeEditor.Style -> Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId )
cursorForward boxStyle uiState model =
    case ( model.forward, currentPlace uiState model ) of
        ( target :: later, Just now ) ->
            goTo boxStyle target uiState { model | forward = later, back = remember now model.back }

        _ ->
            ( model, uiState )


{-| Moves the cursor to a place as a jump: where it was can be gone back to.
-}
jump : CodeEditor.Style -> Place -> Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId )
jump boxStyle target uiState model =
    case currentPlace uiState model of
        Just now ->
            goTo boxStyle target uiState { model | back = remember now model.back, forward = [] }

        Nothing ->
            goTo boxStyle target uiState model



-- GO TO DEFINITION AND USAGES


{-| Ctrl+click in the code, with the cursor where the mouse went down (so it is on the
name that was clicked):

  - on a name that is used: goes to where it is defined, in whichever module;
  - on a name where it is defined: shows where it is used (under the code);
  - on a module in a name (the `Ui` of `Ui.text`) or in an import: goes to the module.

Nothing if there is nothing to go to (a name from a package, or not a name), and then the
click is an ordinary one.

-}
ctrlClick : Coord UiPixels -> Ui.Model UiId.UiId -> Model -> Maybe ( Model, Ui.Model UiId.UiId )
ctrlClick windowSize uiState model =
    case model.module_ of
        Just thisModule ->
            let
                editor : CodeEditor.Model
                editor =
                    Ui.getCodeEditor (UiId.Code Input) uiState

                state : TextInput.State
                state =
                    { cursorPosition = editor.cursorPosition, cursorSize = editor.cursorSize, text = CodeEditor.text editor }
            in
            case Code.Index.wordAt state.cursorPosition state.text of
                Just word ->
                    ctrlClickWord windowSize thisModule state word uiState model

                Nothing ->
                    Nothing

        Nothing ->
            Nothing


ctrlClickWord : Coord UiPixels -> String -> TextInput.State -> Code.Index.Word -> Ui.Model UiId.UiId -> Model -> Maybe ( Model, Ui.Model UiId.UiId )
ctrlClickWord windowSize thisModule state word uiState model =
    let
        text : String
        text =
            state.text

        boxStyle : CodeEditor.Style
        boxStyle =
            style windowSize model

        imports : List Code.Index.Import
        imports =
            Code.Index.imports text

        -- What a module has: the open one as it is in the text box, the others as saved.
        textOf : String -> Maybe String
        textOf name =
            if name == thisModule then
                Just text

            else
                moduleText name model

        declarationsOf : String -> List Code.Index.Declaration
        declarationsOf name =
            textOf name |> Maybe.map Code.Index.declarations |> Maybe.withDefault []

        goToModule : String -> Maybe ( Model, Ui.Model UiId.UiId )
        goToModule name =
            if SeqDict.member name SourceCode.sourceCode then
                Just (jump boxStyle { module_ = name, position = 0, line = 0 } uiState model)

            else
                Nothing

        lineStart : Int
        lineStart =
            word.start - word.column
    in
    if word.column == 7 && String.slice lineStart (lineStart + 7) text == "import " then
        goToModule (String.join "." (word.qualifier ++ [ word.name ]))

    else
        case Code.Index.qualifierAt state.cursorPosition word of
            Just qualifier ->
                Code.Index.moduleOf imports qualifier |> Maybe.andThen goToModule

            Nothing ->
                if List.isEmpty word.qualifier && List.any (\declaration -> declaration.start == word.nameStart) (declarationsOf thisModule) then
                    -- A definition: where it is used.
                    let
                        target : Code.Index.Target
                        target =
                            { module_ = thisModule, name = word.name, position = word.nameStart }

                        sources : List { name : String, text : String }
                        sources =
                            SeqDict.keys SourceCode.sourceCode
                                |> List.filter shownModule
                                |> List.filterMap (\name -> textOf name |> Maybe.map (\moduleText_ -> { name = name, text = moduleText_ }))

                        withUsages : Model
                        withUsages =
                            { model | usages = Just { module_ = thisModule, name = word.name, found = Code.Index.usages target sources } }

                        editor : CodeEditor.Model
                        editor =
                            Ui.getCodeEditor (UiId.Code Input) uiState
                    in
                    -- The list takes some of the code's lines, so the cursor may be hidden now.
                    Just
                        ( withUsages
                        , Ui.insertElement
                            (UiId.Code Input)
                            (Ui.CodeEditorState
                                (CodeEditor.select (style windowSize withUsages) state.cursorPosition state.cursorPosition editor)
                            )
                            uiState
                        )

                else
                    Code.Index.resolve { thisModule = thisModule, imports = imports, declarationsOf = declarationsOf } word
                        |> Maybe.map
                            (\target ->
                                jump
                                    boxStyle
                                    { module_ = target.module_
                                    , position = target.position
                                    , line = lineOf (textOf target.module_ |> Maybe.withDefault "") target.position
                                    }
                                    uiState
                                    model
                            )


{-| The line (from 0) a position in the text is on.
-}
lineOf : String -> Int -> Int
lineOf text position =
    List.length (String.indexes "\n" (String.left position text))


{-| Puts the cursor at a place, in whichever module, and shows it. That is not a jump to
remember (the caller keeps the history).
-}
goTo : CodeEditor.Style -> Place -> Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId )
goTo boxStyle target uiState model =
    let
        text : String
        text =
            CodeEditor.text (Ui.getCodeEditor (UiId.Code Input) uiState)

        ( opened, uiState2, _ ) =
            openModule target.module_ text uiState model

        editor : CodeEditor.Model
        editor =
            Ui.getCodeEditor (UiId.Code Input) uiState2

        position : Int
        position =
            min target.position (String.length (CodeEditor.text editor))

        uiState3 : Ui.Model UiId.UiId
        uiState3 =
            Ui.insertElement
                (UiId.Code Input)
                (Ui.CodeEditorState (CodeEditor.selectCentered boxStyle position position editor))
                uiState2
    in
    ( { opened | lastPlace = currentPlace uiState3 opened }, Ui.setFocus (Just (UiId.Code Input)) uiState3 )


{-| Puts the module's text in the text box.
-}
load : String -> Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId, List Effect )
load name uiState model =
    case moduleText name model of
        Just text ->
            ( { model | showErrors = False }
            , Ui.insertElement (UiId.Code Input) (Ui.CodeEditorState (CodeEditor.withText text)) uiState
                |> Ui.setFocus (Just (UiId.Code Input))
            , []
            )

        Nothing ->
            ( model, uiState, [] )



-- VIEW


{-| How big the window can be.
-}
appSize : App.Limits
appSize =
    { min = Coord.xy (sidebarWidth + 400) 250
    , preferred = Coord.xy 900 (chrome + 30 * lineHeight)
    , max = Coord.xy 1600 100000
    }


lineHeight : Int
lineHeight =
    Quantity.unwrap (Sprite.lineHeight Sprite.Small)


{-| The window's height besides its lines of code: the pad, the title, the status
line, the gap between them and the text box's own pad.
-}
chrome : Int
chrome =
    2 * 8 + Quantity.unwrap (Sprite.lineHeight Sprite.Big) + lineHeight + 2 * 6 + 2 * 4 + 6


{-| The space between the list of modules and what is beside it, and between the parts
of the window above each other.
-}
gap : Int
gap =
    6


{-| The text box, as big as the window (of this size) lets it be: with the find bar over
it, it has fewer lines.
-}
style : Coord UiPixels -> Model -> CodeEditor.Style
style windowSize model =
    let
        width : Quantity Int UiPixels
        width =
            Units.ui (Coord.xRaw windowSize - 16 - sidebarWidth - gap)

        barHeight : Int
        barHeight =
            (if findShown model then
                Coord.yRaw (Ui.size (findBar width)) + gap

             else
                0
            )
                + (if usagesShown model then
                    usagesPanelHeight

                   else
                    0
                  )
    in
    { fontSize = Sprite.Small
    , width = width
    , lines = max 1 ((Coord.yRaw windowSize - chrome - barHeight) // lineHeight)
    }


{-| The window: the module's name and buttons, the code (or the list of modules, or the
last build's errors), where the cursor is, whether the text is saved, and how the last
build went. `input` is the text box's model.
-}
view : Ui.LazyCache UiId.UiId -> Coord UiPixels -> CodeEditor.Model -> String -> Maybe String -> Model -> Element UiId.UiId
view lazyCache windowSize input running switchingTo model =
    let
        boxStyle : CodeEditor.Style
        boxStyle =
            style windowSize model

        segment color text =
            { text = text, color = color, font = Sprite.Sans Sprite.Regular, decorations = [], link = Nothing }

        button id label =
            Ui.button { id = UiId.Code id, pad = Ui.paddingXY 6 3 } (Ui.text label)

        ( line, column ) =
            CodeEditor.cursorLineAndColumn input

        editing =
            if model.showErrors || model.committing then
                Nothing

            else
                model.module_

        title =
            case ( model.showErrors, editing ) of
                ( True, _ ) ->
                    "Build errors"

                ( False, Nothing ) ->
                    if model.committing then
                        "Commit and push"

                    else
                        "Code"

                ( False, Just name ) ->
                    name

        unsaved =
            case editing of
                Just _ ->
                    not (CodeEditor.isSaved input)

                Nothing ->
                    False

        fileStatus =
            case editing of
                Just name ->
                    [ segment Color.dimTextColor ("Line " ++ String.fromInt (line + 1) ++ ", column " ++ String.fromInt (column + 1) ++ "   ")
                    , if unsaved then
                        segment Color.textColor "Not saved (Ctrl+S saves)"

                      else if isEdited name model.saved then
                        segment Color.successColor "Saved, changed from the built-in code"

                      else
                        segment Color.dimTextColor "As built"
                    , segment Color.dimTextColor
                        ((if findShown model then
                            matchCount input

                          else
                            ""
                         )
                            ++ "   Ctrl+F finds and replaces"
                        )
                    ]

                Nothing ->
                    if model.showErrors || model.committing then
                        []

                    else
                        [ segment Color.dimTextColor "Pick a module to read or change" ]

        buildStatus =
            case model.build of
                Just (BuildRunning step) ->
                    if step == goingBack then
                        [ segment Color.textColor ("   " ++ goingBack ++ "...") ]

                    else
                        [ segment Color.textColor ("   Building: " ++ step ++ "...") ]

                Just (BuildFailed step _) ->
                    if step == goingBack then
                        [ segment Color.errorColor "   Couldn't go back to the deployed build" ]

                    else
                        [ segment Color.errorColor ("   The build failed: " ++ step) ]

                Just (Built name) ->
                    if switchingTo == Just name then
                        [ segment Color.successColor ("   Built " ++ name ++ ", switching to it") ]

                    else
                        -- The switch is done: had it failed, the host would have said
                        -- BuildFailed instead.
                        [ segment Color.successColor ("   Running " ++ name ++ ", built here") ]

                Nothing ->
                    []

        -- There whenever something differs from the running build, even while a build
        -- is going: if the host never answers (an older host, or one with no tools
        -- partition), the button still works.
        buildButton =
            (if unsaved || differsFromRunning model then
                [ button BuildButton "Build and run" ]

             else
                []
            )
                -- A build made here stays until this: the host follows the deployed
                -- builds again only when asked, so as not to drop the edits.
                ++ (if String.startsWith "local-" running && not (buildRunning model) then
                        [ button DeployedButton "Back to deployed build" ]

                    else
                        []
                   )
                ++ (if SeqDict.isEmpty model.saved && not unsaved then
                        []

                    else
                        [ button CommitButton "Commit" ]
                   )

        buttons =
            case ( model.showErrors, editing ) of
                ( True, _ ) ->
                    [ button ErrorsCloseButton "Back to code", button CloseButton "Close" ]

                ( False, Nothing ) ->
                    if model.committing then
                        (if gitWorking model.git then
                            []

                         else
                            [ button PushButton "Push" ]
                        )
                            ++ [ button CommitCloseButton "Back to code", button CloseButton "Close" ]

                    else
                        buildButton ++ [ button CloseButton "Close" ]

                ( False, Just name ) ->
                    (if unsaved then
                        [ button SaveButton "Save" ]

                     else
                        []
                    )
                        ++ (if isEdited name model.saved then
                                [ button RevertButton "Back to built-in" ]

                            else
                                []
                           )
                        ++ buildButton
                        ++ [ button CloseButton "Close" ]

        boxHeight =
            Units.ui (Coord.yRaw (CodeEditor.size boxStyle))

        errors =
            case model.build of
                Just (BuildFailed step output) ->
                    "The build stopped at: " ++ step ++ "\n\n" ++ output

                _ ->
                    ""

        pane =
            if model.committing then
                Ui.viewport
                    { id = UiId.Code CommitViewport, viewportHeight = boxHeight }
                    (commitView boxStyle.width model)

            else if model.showErrors then
                Ui.viewport
                    { id = UiId.Code ErrorsViewport, viewportHeight = boxHeight }
                    -- Wrapped: a compiler's lines can be wider than the App.
                    (Ui.customTextWrapped
                        Sprite.Small
                        boxStyle.width
                        [ { text = errors, color = Color.textColor, font = Sprite.Mono, decorations = [], link = Nothing } ]
                    )

            else
                case editing of
                    Just _ ->
                        Ui.column
                            gap
                            ((if findShown model then
                                [ findBar boxStyle.width ]

                              else
                                []
                             )
                                ++ [ Ui.codeEditor { id = UiId.Code Input, style = boxStyle } ]
                                ++ (case model.usages of
                                        Just usages ->
                                            [ usagesPanel boxStyle.width usages ]

                                        Nothing ->
                                            []
                                   )
                            )

                    Nothing ->
                        Ui.center
                            { size = Coord.xy (Quantity.unwrap boxStyle.width) (Quantity.unwrap boxHeight) }
                            (Ui.customText Sprite.Small [ segment Color.dimTextColor "Pick a module on the left" ])

        content =
            Ui.column
                6
                [ Ui.leftAndRight (Units.ui (Coord.xRaw windowSize - 16))
                    (Ui.customText Sprite.Big [ segment Color.textColor title ])
                    (Ui.row 6 buttons)
                , Ui.row gap [ Ui.lazy3 lazyCache modulesList boxHeight editing model.saved, pane ]
                , Ui.customText Sprite.Small (fileStatus ++ buildStatus)
                ]
    in
    Ui.elWithId
        (UiId.Code Window)
        -- The code shows in whole lines, so what's left of the window's height under them
        -- goes below the status line.
        { pad = { top = 8, bottom = 8 + max 0 (Coord.yRaw windowSize - 16 - Coord.yRaw (Ui.size content)), left = 8, right = 8 }
        , style = Ui.windowBorderAndFill
        }
        content


{-| Whether the usages of a definition show under the code: only over the code of a
module.
-}
usagesShown : Model -> Bool
usagesShown model =
    model.usages /= Nothing && not model.showErrors && not model.committing && model.module_ /= Nothing


{-| How tall the usages' panel is, and what it takes from the code's height with the gap
above it.
-}
usagesPanelHeight : Int
usagesPanelHeight =
    Coord.yRaw (Ui.size (usagesPanel (Units.ui 600) { module_ = "", name = "", found = [] })) + gap


{-| Where a definition is used, one use to a line (a button that goes there), and a button
to hide them. Lines are cut off where the panel ends.
-}
usagesPanel : Quantity Int UiPixels -> UsageList -> Element UiId.UiId
usagesPanel width usages =
    let
        found : Int
        found =
            List.length usages.found

        characterWidth : Int
        characterWidth =
            Coord.xRaw (Sprite.textSize Sprite.Small Sprite.Mono "x")

        -- What the viewport's outline, a button's border and padding and the scroll bar
        -- take of the width.
        fits : Int
        fits =
            (Quantity.unwrap width - 2 - 2 * 6 - 2 * 2 - 8) // characterWidth

        mono color text =
            { text = text, color = color, font = Sprite.Mono, decorations = [], link = Nothing }

        row index usage =
            let
                place : String
                place =
                    usage.module_ ++ ":" ++ String.fromInt (usage.line + 1) ++ "  "
            in
            Ui.button
                { id = UiId.Code (UsageButton index), pad = Ui.paddingXY 6 2 }
                (Ui.customText
                    Sprite.Small
                    [ mono Color.dimTextColor (String.left fits place)
                    , mono Color.textColor (String.left (fits - String.length place) usage.text)
                    ]
                )

        rowHeight : Int
        rowHeight =
            lineHeight + 8

        title : String
        title =
            "Used "
                ++ String.fromInt found
                ++ (if found == 1 then
                        " time: "

                    else
                        " times: "
                   )
                ++ usages.module_
                ++ "."
                ++ usages.name
    in
    Ui.column
        gap
        [ Ui.leftAndRight
            width
            (Ui.customText Sprite.Small [ { text = title, color = Color.textColor, font = Sprite.Sans Sprite.Regular, decorations = [], link = Nothing } ])
            (Ui.button { id = UiId.Code UsagesCloseButton, pad = Ui.paddingXY 6 3 } (Ui.text "Close"))
        , Ui.viewport
            { id = UiId.Code UsagesViewport, viewportHeight = Units.ui (5 * rowHeight) }
            (Ui.column 4 (List.indexedMap row usages.found))
        ]


{-| The modules beside the code, one under another, to pick the one to read or change
(`open` is the one shown, if any). It is as tall as the text box.
-}
modulesList : Quantity Int UiPixels -> Maybe String -> SeqDict String String -> Element UiId.UiId
modulesList height open saved =
    Ui.viewport
        { id = UiId.Code ModulesViewport, viewportHeight = height }
        (Ui.column
            4
            (List.map
                (\name ->
                    Ui.button
                        { id = UiId.Code (ModuleButton name), pad = Ui.paddingXY 6 3 }
                        (Ui.customText
                            Sprite.Small
                            [ { text = name
                              , color =
                                    if isEdited name saved then
                                        Color.successColor

                                    else
                                        Color.textColor
                              , font = Sprite.Sans Sprite.Regular
                              , decorations =
                                    if open == Just name then
                                        [ Sprite.Underline ]

                                    else
                                        []
                              , link = Nothing
                              }
                            ]
                        )
                )
                (List.filter shownModule (SeqDict.keys SourceCode.sourceCode))
            )
        )


{-| How wide the list of modules is: the widest name's button, and the viewport's frame.
-}
sidebarWidth : Int
sidebarWidth =
    Coord.xRaw (Ui.size (modulesList (Units.ui 100) Nothing init.saved))


{-| Which match the selection is, and how many there are: "3 of 15 matches", or just the
count when the selection isn't one of them, or "No matches". Nothing when the text box
searches for nothing (the find box is empty).
-}
matchCount : CodeEditor.Model -> String
matchCount editor =
    let
        count : Int
        count =
            CodeEditor.matchCount editor
    in
    if not (CodeEditor.isSearching editor) then
        ""

    else if count == 0 then
        "   No matches"

    else
        case CodeEditor.matchNumber editor of
            Just index ->
                "   " ++ String.fromInt index ++ " of " ++ String.fromInt count ++ " matches"

            Nothing ->
                "   " ++ String.fromInt count ++ " matches"


{-| The find and replace bar: two rows, each a box (as wide as is left) and its buttons.
-}
findBar : Quantity Int UiPixels -> Element UiId.UiId
findBar width =
    let
        button id caption =
            Ui.button { id = UiId.Code id, pad = Ui.paddingXY 6 3 } (Ui.text caption)

        findButtons : Element UiId.UiId
        findButtons =
            Ui.row 8 [ button FindPreviousButton "Previous", button FindNextButton "Next", button FindCloseButton "Close" ]

        replaceButtons : Element UiId.UiId
        replaceButtons =
            Ui.row 8 [ button ReplaceButton "Replace", button ReplaceAllButton "Replace all" ]

        label : String -> Element UiId.UiId
        label text =
            Ui.left
                (Coord.x (Ui.size (Ui.text "Replace")))
                (Ui.el { pad = Ui.paddingXY 0 4, style = Ui.NoBorderOrFill } (Ui.text text))

        inputWidth : Int
        inputWidth =
            (Quantity.unwrap width - Coord.xRaw (Ui.size (label "Replace")) - Coord.xRaw (Ui.size findButtons) - 2 * 8)
                |> max 80
                |> min 400

        input id =
            Ui.textInput
                { id = UiId.Code id
                , style = { font = Sprite.Sans Sprite.Regular, fontSize = Sprite.Small, width = Units.ui inputWidth, masked = False }
                , isValid = True
                }
    in
    Ui.column
        4
        [ Ui.row 8 [ label "Find", input FindInput, findButtons ]
        , Ui.row 8 [ label "Replace", input ReplaceInput, replaceButtons ]
        ]


{-| Whether the list of modules shows it: not the frozen copies of old versions (they
are only there for migrations), nor BuildInfo (the build writes it).
-}
shownModule : String -> Bool
shownModule name =
    not (String.startsWith "Evergreen." name) && name /= "BuildInfo"


{-| The commit view: what a commit would hold and where it would go, the token and the
message, and how the last commit went.
-}
commitView : Quantity Int UiPixels -> Model -> Element UiId.UiId
commitView width model =
    let
        line color text =
            Ui.customTextWrapped Sprite.Small width [ { text = text, color = color, font = Sprite.Sans Sprite.Regular, decorations = [], link = Nothing } ]

        input id masked =
            Ui.textInput
                { id = UiId.Code id
                , style = { font = Sprite.Sans Sprite.Regular, fontSize = Sprite.Small, width = width, masked = masked }
                , isValid = True
                }

        changed =
            SeqDict.keys model.saved
                |> List.filter (\name -> SeqDict.get name model.git.pushed /= SeqDict.get name model.saved)

        where_ =
            case Code.GitHub.startingPoint model.git of
                ( "", _ ) ->
                    line Color.errorColor noCommitToStartFrom

                ( base, branch ) ->
                    line Color.dimTextColor
                        ("On top of commit "
                            ++ String.left 12 base
                            ++ (if branch == "" then
                                    ", on a new branch."

                                else
                                    ", pushed to " ++ branch ++ " (or to a new branch, if " ++ branch ++ " has moved on since)."
                               )
                        )

        status =
            case model.git.status of
                GitIdle ->
                    []

                GitWorking _ ->
                    [ line Color.textColor "Committing and pushing..." ]

                GitPushed commit branch ->
                    [ line Color.successColor ("Pushed commit " ++ String.left 12 commit ++ " to " ++ branch ++ ".") ]

                GitFailed step why ->
                    [ line Color.errorColor (step ++ " failed. " ++ why) ]
    in
    Ui.column 8
        ([ line Color.textColor
            ("Saved modules: "
                ++ String.join ", " (SeqDict.keys model.saved)
                ++ (if List.isEmpty changed then
                        " (all already pushed)"

                    else
                        ""
                   )
            )
         , where_
         , line Color.dimTextColor "GitHub token (a fine-grained one that can only write the contents of Elm-OS)"
         , input TokenInput False
         , line Color.dimTextColor "Commit message"
         , input MessageInput False
         ]
            ++ status
        )
