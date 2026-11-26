module Generated.ModelTree exposing (model)

{-| WRITTEN BY tools/wire: DON'T EDIT IT. `make` writes it again from the Model's types.

The Model as a tree, for the Model viewer app (see elm/src/ModelTree.elm): a
`ModelTree.Tree` for each type the Model is made of. An opaque type shows as its name,
unless its module exposes a `modelTree<Type>` that says how to show it.

-}

import About.Types
import AsciiCollab
import AsciiCollab.Types
import Calculator
import Calculator.Types
import Code.Types
import DebugInfo.Types
import Editor.Types
import Effect
import Email
import Email.Types
import HackerNews
import HackerNews.Types
import History.Types
import Install
import Install.Types
import ModelTree
import ModelViewer.Types
import Network
import Network.Types
import News.Types
import Paint.Types
import ScreenshotViewer.Types
import TextInputMultiline
import TicTacToe
import TicTacToe.Types
import Ui
import UiId
import Weather
import Weather.Types
import WebViewer
import WebViewer.Types


model put value =
    tree_Main_Model put value


tree_About_Types_SystemInfo put value =
    ModelTree.record
        [ ( "kernel", \() -> ModelTree.string (\x -> put { value | kernel = x }) value.kernel )
        , ( "cpu", \() -> ModelTree.string (\x -> put { value | cpu = x }) value.cpu )
        , ( "commit", \() -> ModelTree.string (\x -> put { value | commit = x }) value.commit )
        , ( "build", \() -> ModelTree.string (\x -> put { value | build = x }) value.build )
        ]


tree_About_Types_UiId put value =
    case value of
        About.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_About_Types_UiId put)

        About.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_About_Types_UiId put)


choices_About_Types_UiId put =
    [ ( "OpenButton", \() -> put About.Types.OpenButton )
    , ( "CloseButton", \() -> put About.Types.CloseButton )
    ]


tree_AsciiCollab_Connection put value =
    case value of
        AsciiCollab.Disconnected a0 ->
            ModelTree.variant "Disconnected" [ \() -> (\put1 value1 -> ModelTree.record [ ( "reason", \() -> ModelTree.string (\x1 -> put1 { value1 | reason = x1 }) value1.reason ), ( "retryAt", \() -> ModelTree.int (\x1 -> put1 { value1 | retryAt = x1 }) value1.retryAt ) ]) (\new -> put (AsciiCollab.Disconnected new)) a0 ] (choices_AsciiCollab_Connection put)

        AsciiCollab.WaitingForId ->
            ModelTree.variant "WaitingForId" [] (choices_AsciiCollab_Connection put)

        AsciiCollab.Connecting ->
            ModelTree.variant "Connecting" [] (choices_AsciiCollab_Connection put)

        AsciiCollab.Connected ->
            ModelTree.variant "Connected" [] (choices_AsciiCollab_Connection put)


choices_AsciiCollab_Connection put =
    [ ( "WaitingForId", \() -> put AsciiCollab.WaitingForId )
    , ( "Connecting", \() -> put AsciiCollab.Connecting )
    , ( "Connected", \() -> put AsciiCollab.Connected )
    ]


tree_AsciiCollab_Model put value =
    ModelTree.record
        [ ( "isOpen", \() -> ModelTree.bool (\x -> put { value | isOpen = x }) value.isOpen )
        , ( "connection", \() -> tree_AsciiCollab_Connection (\x -> put { value | connection = x }) value.connection )
        , ( "clientId", \() -> ModelTree.maybe ModelTree.string (\x -> put { value | clientId = x }) value.clientId )
        , ( "sessionCookie", \() -> ModelTree.maybe ModelTree.string (\x -> put { value | sessionCookie = x }) value.sessionCookie )
        , ( "appVersion", \() -> ModelTree.int (\x -> put { value | appVersion = x }) value.appVersion )
        , ( "nextSeq", \() -> ModelTree.int (\x -> put { value | nextSeq = x }) value.nextSeq )
        , ( "unacked", \() -> ModelTree.list (\put1 value1 -> ModelTree.record [ ( "seq", \() -> ModelTree.int (\x1 -> put1 { value1 | seq = x1 }) value1.seq ), ( "data", \() -> ModelTree.bytes (\x1 -> put1 { value1 | data = x1 }) value1.data ) ]) (\x -> put { value | unacked = x }) value.unacked )
        , ( "state", \() -> tree_AsciiCollab_State (\x -> put { value | state = x }) value.state )
        , ( "cursor", \() -> tree_Coord_Coord (\x -> put { value | cursor = x }) value.cursor )
        , ( "lineStart", \() -> ModelTree.int (\x -> put { value | lineStart = x }) value.lineStart )
        , ( "viewPoint", \() -> tree_Coord_Coord (\x -> put { value | viewPoint = x }) value.viewPoint )
        , ( "scrollRemainder", \() -> ModelTree.float (\x -> put { value | scrollRemainder = x }) value.scrollRemainder )
        , ( "pendingChanges", \() -> ModelTree.list tree_AsciiCollab_Types_LocalChange (\x -> put { value | pendingChanges = x }) value.pendingChanges )
        , ( "now", \() -> ModelTree.int (\x -> put { value | now = x }) value.now )
        , ( "lastUndoPoint", \() -> ModelTree.int (\x -> put { value | lastUndoPoint = x }) value.lastUndoPoint )
        , ( "lastSent", \() -> ModelTree.int (\x -> put { value | lastSent = x }) value.lastSent )
        ]


tree_AsciiCollab_State put value =
    case value of
        AsciiCollab.NotLoaded ->
            ModelTree.variant "NotLoaded" [] (choices_AsciiCollab_State put)

        AsciiCollab.Loaded a0 ->
            ModelTree.variant "Loaded" [ \() -> tree_AsciiCollab_LocalGrid_LocalModel (\new -> put (AsciiCollab.Loaded new)) a0 ] (choices_AsciiCollab_State put)


choices_AsciiCollab_State put =
    [ ( "NotLoaded", \() -> put AsciiCollab.NotLoaded )
    ]


tree_AsciiCollab_LocalGrid_LocalGrid put value =
    ModelTree.record
        [ ( "grid", \() -> tree_AsciiCollab_Types_Grid (\x -> put { value | grid = x }) value.grid )
        , ( "undoHistory", \() -> ModelTree.list (ModelTree.dict (ModelTree.tuple2 ModelTree.int ModelTree.int) ModelTree.int) (\x -> put { value | undoHistory = x }) value.undoHistory )
        , ( "redoHistory", \() -> ModelTree.list (ModelTree.dict (ModelTree.tuple2 ModelTree.int ModelTree.int) ModelTree.int) (\x -> put { value | redoHistory = x }) value.redoHistory )
        , ( "user", \() -> tree_AsciiCollab_Types_UserId (\x -> put { value | user = x }) value.user )
        , ( "hiddenUsers", \() -> ModelTree.seqSet tree_AsciiCollab_Types_UserId (\x -> put { value | hiddenUsers = x }) value.hiddenUsers )
        , ( "adminHiddenUsers", \() -> ModelTree.seqSet tree_AsciiCollab_Types_UserId (\x -> put { value | adminHiddenUsers = x }) value.adminHiddenUsers )
        , ( "viewBounds", \() -> tree_AsciiCollab_Types_Bounds (\x -> put { value | viewBounds = x }) value.viewBounds )
        , ( "undoCurrent", \() -> ModelTree.dict (ModelTree.tuple2 ModelTree.int ModelTree.int) ModelTree.int (\x -> put { value | undoCurrent = x }) value.undoCurrent )
        ]


tree_AsciiCollab_LocalGrid_LocalModel put value =
    ModelTree.record
        [ ( "localMsgs", \() -> ModelTree.list tree_AsciiCollab_Types_Change (\x -> put { value | localMsgs = x }) value.localMsgs )
        , ( "localModel", \() -> tree_AsciiCollab_LocalGrid_LocalGrid (\x -> put { value | localModel = x }) value.localModel )
        , ( "model", \() -> tree_AsciiCollab_LocalGrid_LocalGrid (\x -> put { value | model = x }) value.model )
        ]


tree_AsciiCollab_Types_Ascii put value =
    case value of
        AsciiCollab.Types.Ascii a0 ->
            ModelTree.variant "Ascii" [ \() -> ModelTree.int (\new -> put (AsciiCollab.Types.Ascii new)) a0 ] []


tree_AsciiCollab_Types_Bounds put value =
    case value of
        AsciiCollab.Types.Bounds a0 ->
            ModelTree.variant "Bounds" [ \() -> (\put1 value1 -> ModelTree.record [ ( "min", \() -> tree_Coord_Coord (\x1 -> put1 { value1 | min = x1 }) value1.min ), ( "max", \() -> tree_Coord_Coord (\x1 -> put1 { value1 | max = x1 }) value1.max ) ]) (\new -> put (AsciiCollab.Types.Bounds new)) a0 ] []


tree_AsciiCollab_Types_Cell put value =
    case value of
        AsciiCollab.Types.Cell a0 ->
            ModelTree.variant "Cell" [ \() -> (\put1 value1 -> ModelTree.record [ ( "history", \() -> ModelTree.list (\put2 value2 -> ModelTree.record [ ( "userId", \() -> tree_AsciiCollab_Types_UserId (\x2 -> put2 { value2 | userId = x2 }) value2.userId ), ( "position", \() -> ModelTree.int (\x2 -> put2 { value2 | position = x2 }) value2.position ), ( "line", \() -> tree_AsciiCollab_Types_Nonempty tree_AsciiCollab_Types_Ascii (\x2 -> put2 { value2 | line = x2 }) value2.line ) ]) (\x1 -> put1 { value1 | history = x1 }) value1.history ), ( "undoPoint", \() -> ModelTree.dict ModelTree.int ModelTree.int (\x1 -> put1 { value1 | undoPoint = x1 }) value1.undoPoint ) ]) (\new -> put (AsciiCollab.Types.Cell new)) a0 ] []


tree_AsciiCollab_Types_Change put value =
    case value of
        AsciiCollab.Types.LocalChange a0 ->
            ModelTree.variant "LocalChange" [ \() -> tree_AsciiCollab_Types_LocalChange (\new -> put (AsciiCollab.Types.LocalChange new)) a0 ] []

        AsciiCollab.Types.ServerChange a0 ->
            ModelTree.variant "ServerChange" [ \() -> tree_AsciiCollab_Types_ServerChange (\new -> put (AsciiCollab.Types.ServerChange new)) a0 ] []

        AsciiCollab.Types.ClientChange a0 ->
            ModelTree.variant "ClientChange" [ \() -> tree_AsciiCollab_Types_ClientChange (\new -> put (AsciiCollab.Types.ClientChange new)) a0 ] []


tree_AsciiCollab_Types_ClientChange put value =
    case value of
        AsciiCollab.Types.ViewBoundsChange a0 a1 ->
            ModelTree.variant "ViewBoundsChange" [ \() -> tree_AsciiCollab_Types_Bounds (\new -> put (AsciiCollab.Types.ViewBoundsChange new a1)) a0, \() -> ModelTree.list (ModelTree.tuple2 tree_Coord_Coord tree_AsciiCollab_Types_Cell) (\new -> put (AsciiCollab.Types.ViewBoundsChange a0 new)) a1 ] []


tree_AsciiCollab_Types_Grid put value =
    case value of
        AsciiCollab.Types.Grid a0 ->
            ModelTree.variant "Grid" [ \() -> ModelTree.dict (ModelTree.tuple2 ModelTree.int ModelTree.int) tree_AsciiCollab_Types_Cell (\new -> put (AsciiCollab.Types.Grid new)) a0 ] []


tree_AsciiCollab_Types_GridChangeData put value =
    ModelTree.record
        [ ( "cellPosition", \() -> tree_Coord_Coord (\x -> put { value | cellPosition = x }) value.cellPosition )
        , ( "localPosition", \() -> ModelTree.int (\x -> put { value | localPosition = x }) value.localPosition )
        , ( "change", \() -> tree_AsciiCollab_Types_Nonempty tree_AsciiCollab_Types_Ascii (\x -> put { value | change = x }) value.change )
        , ( "userId", \() -> tree_AsciiCollab_Types_UserId (\x -> put { value | userId = x }) value.userId )
        ]


tree_AsciiCollab_Types_LocalChange put value =
    case value of
        AsciiCollab.Types.LocalGridChange a0 ->
            ModelTree.variant "LocalGridChange" [ \() -> tree_AsciiCollab_Types_LocalGridChangeData (\new -> put (AsciiCollab.Types.LocalGridChange new)) a0 ] (choices_AsciiCollab_Types_LocalChange put)

        AsciiCollab.Types.LocalUndo ->
            ModelTree.variant "LocalUndo" [] (choices_AsciiCollab_Types_LocalChange put)

        AsciiCollab.Types.LocalRedo ->
            ModelTree.variant "LocalRedo" [] (choices_AsciiCollab_Types_LocalChange put)

        AsciiCollab.Types.LocalAddUndo ->
            ModelTree.variant "LocalAddUndo" [] (choices_AsciiCollab_Types_LocalChange put)

        AsciiCollab.Types.LocalHideUser a0 a1 ->
            ModelTree.variant "LocalHideUser" [ \() -> tree_AsciiCollab_Types_UserId (\new -> put (AsciiCollab.Types.LocalHideUser new a1)) a0, \() -> tree_Coord_Coord (\new -> put (AsciiCollab.Types.LocalHideUser a0 new)) a1 ] (choices_AsciiCollab_Types_LocalChange put)

        AsciiCollab.Types.LocalUnhideUser a0 ->
            ModelTree.variant "LocalUnhideUser" [ \() -> tree_AsciiCollab_Types_UserId (\new -> put (AsciiCollab.Types.LocalUnhideUser new)) a0 ] (choices_AsciiCollab_Types_LocalChange put)

        AsciiCollab.Types.LocalToggleUserVisibilityForAll a0 ->
            ModelTree.variant "LocalToggleUserVisibilityForAll" [ \() -> tree_AsciiCollab_Types_UserId (\new -> put (AsciiCollab.Types.LocalToggleUserVisibilityForAll new)) a0 ] (choices_AsciiCollab_Types_LocalChange put)


choices_AsciiCollab_Types_LocalChange put =
    [ ( "LocalUndo", \() -> put AsciiCollab.Types.LocalUndo )
    , ( "LocalRedo", \() -> put AsciiCollab.Types.LocalRedo )
    , ( "LocalAddUndo", \() -> put AsciiCollab.Types.LocalAddUndo )
    ]


tree_AsciiCollab_Types_LocalGridChangeData put value =
    ModelTree.record
        [ ( "cellPosition", \() -> tree_Coord_Coord (\x -> put { value | cellPosition = x }) value.cellPosition )
        , ( "localPosition", \() -> ModelTree.int (\x -> put { value | localPosition = x }) value.localPosition )
        , ( "change", \() -> tree_AsciiCollab_Types_Nonempty tree_AsciiCollab_Types_Ascii (\x -> put { value | change = x }) value.change )
        ]


tree_AsciiCollab_Types_Nonempty tree_a put value =
    case value of
        AsciiCollab.Types.Nonempty a0 a1 ->
            ModelTree.variant "Nonempty" [ \() -> tree_a (\new -> put (AsciiCollab.Types.Nonempty new a1)) a0, \() -> ModelTree.list tree_a (\new -> put (AsciiCollab.Types.Nonempty a0 new)) a1 ] []


tree_AsciiCollab_Types_ServerChange put value =
    case value of
        AsciiCollab.Types.ServerGridChange a0 ->
            ModelTree.variant "ServerGridChange" [ \() -> tree_AsciiCollab_Types_GridChangeData (\new -> put (AsciiCollab.Types.ServerGridChange new)) a0 ] []

        AsciiCollab.Types.ServerUndoPoint a0 ->
            ModelTree.variant "ServerUndoPoint" [ \() -> (\put1 value1 -> ModelTree.record [ ( "userId", \() -> tree_AsciiCollab_Types_UserId (\x1 -> put1 { value1 | userId = x1 }) value1.userId ), ( "undoPoints", \() -> ModelTree.dict (ModelTree.tuple2 ModelTree.int ModelTree.int) ModelTree.int (\x1 -> put1 { value1 | undoPoints = x1 }) value1.undoPoints ) ]) (\new -> put (AsciiCollab.Types.ServerUndoPoint new)) a0 ] []

        AsciiCollab.Types.ServerToggleUserVisibilityForAll a0 ->
            ModelTree.variant "ServerToggleUserVisibilityForAll" [ \() -> tree_AsciiCollab_Types_UserId (\new -> put (AsciiCollab.Types.ServerToggleUserVisibilityForAll new)) a0 ] []


tree_AsciiCollab_Types_UiId put value =
    case value of
        AsciiCollab.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_AsciiCollab_Types_UiId put)

        AsciiCollab.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_AsciiCollab_Types_UiId put)

        AsciiCollab.Types.GridArea ->
            ModelTree.variant "GridArea" [] (choices_AsciiCollab_Types_UiId put)


choices_AsciiCollab_Types_UiId put =
    [ ( "OpenButton", \() -> put AsciiCollab.Types.OpenButton )
    , ( "CloseButton", \() -> put AsciiCollab.Types.CloseButton )
    , ( "GridArea", \() -> put AsciiCollab.Types.GridArea )
    ]


tree_AsciiCollab_Types_UserId put value =
    case value of
        AsciiCollab.Types.UserId a0 ->
            ModelTree.variant "UserId" [ \() -> ModelTree.int (\new -> put (AsciiCollab.Types.UserId new)) a0 ] []


tree_BootInfo_Battery put value =
    ModelTree.record
        [ ( "batteries", \() -> ModelTree.int (\x -> put { value | batteries = x }) value.batteries )
        , ( "percent", \() -> ModelTree.maybe ModelTree.float (\x -> put { value | percent = x }) value.percent )
        , ( "status", \() -> ModelTree.string (\x -> put { value | status = x }) value.status )
        , ( "minutes", \() -> ModelTree.maybe ModelTree.float (\x -> put { value | minutes = x }) value.minutes )
        ]


tree_BootInfo_BootTimes put value =
    ModelTree.record
        [ ( "initMs", \() -> ModelTree.float (\x -> put { value | initMs = x }) value.initMs )
        , ( "elmMs", \() -> ModelTree.float (\x -> put { value | elmMs = x }) value.elmMs )
        , ( "frameMs", \() -> ModelTree.float (\x -> put { value | frameMs = x }) value.frameMs )
        ]


tree_BootInfo_Clock put value =
    ModelTree.record
        [ ( "minMhz", \() -> ModelTree.float (\x -> put { value | minMhz = x }) value.minMhz )
        , ( "maxMhz", \() -> ModelTree.float (\x -> put { value | maxMhz = x }) value.maxMhz )
        , ( "limitMhz", \() -> ModelTree.float (\x -> put { value | limitMhz = x }) value.limitMhz )
        , ( "governor", \() -> ModelTree.string (\x -> put { value | governor = x }) value.governor )
        , ( "hint", \() -> ModelTree.string (\x -> put { value | hint = x }) value.hint )
        ]


tree_BootInfo_Model put value =
    ModelTree.record
        [ ( "image", \() -> ModelTree.opaqueTree "BootInfo.Image" (\x -> put { value | image = x }) value.image )
        , ( "seconds", \() -> ModelTree.int (\x -> put { value | seconds = x }) value.seconds )
        , ( "gptDisks", \() -> ModelTree.list ModelTree.string (\x -> put { value | gptDisks = x }) value.gptDisks )
        , ( "battery", \() -> ModelTree.maybe tree_BootInfo_Battery (\x -> put { value | battery = x }) value.battery )
        , ( "cpufreqPolicies", \() -> ModelTree.list ModelTree.string (\x -> put { value | cpufreqPolicies = x }) value.cpufreqPolicies )
        , ( "clock", \() -> ModelTree.maybe tree_BootInfo_Clock (\x -> put { value | clock = x }) value.clock )
        , ( "boot", \() -> ModelTree.maybe tree_BootInfo_BootTimes (\x -> put { value | boot = x }) value.boot )
        , ( "firmwareMs", \() -> ModelTree.maybe ModelTree.float (\x -> put { value | firmwareMs = x }) value.firmwareMs )
        ]


tree_Bounds_Bounds put value =
    ModelTree.record
        [ ( "topLeft", \() -> tree_Coord_Coord (\x -> put { value | topLeft = x }) value.topLeft )
        , ( "bottomRight", \() -> tree_Coord_Coord (\x -> put { value | bottomRight = x }) value.bottomRight )
        ]


tree_Button_Model put value =
    ModelTree.record
        [ ( "buttonDown", \() -> ModelTree.maybe (ModelTree.tuple2 ModelTree.posix tree_Coord_Coord) (\x -> put { value | buttonDown = x }) value.buttonDown )
        ]


tree_Calculator_Entry put value =
    case value of
        Calculator.Typed a0 ->
            ModelTree.variant "Typed" [ \() -> ModelTree.string (\new -> put (Calculator.Typed new)) a0 ] (choices_Calculator_Entry put)

        Calculator.Shown a0 ->
            ModelTree.variant "Shown" [ \() -> ModelTree.float (\new -> put (Calculator.Shown new)) a0 ] (choices_Calculator_Entry put)

        Calculator.Error ->
            ModelTree.variant "Error" [] (choices_Calculator_Entry put)


choices_Calculator_Entry put =
    [ ( "Error", \() -> put Calculator.Error )
    ]


tree_Calculator_Model put value =
    ModelTree.record
        [ ( "entry", \() -> tree_Calculator_Entry (\x -> put { value | entry = x }) value.entry )
        , ( "pending", \() -> ModelTree.maybe (ModelTree.tuple2 ModelTree.float tree_Calculator_Types_Operator) (\x -> put { value | pending = x }) value.pending )
        , ( "repeat", \() -> ModelTree.maybe (ModelTree.tuple2 tree_Calculator_Types_Operator ModelTree.float) (\x -> put { value | repeat = x }) value.repeat )
        ]


tree_Calculator_Types_Key put value =
    case value of
        Calculator.Types.Digit a0 ->
            ModelTree.variant "Digit" [ \() -> ModelTree.int (\new -> put (Calculator.Types.Digit new)) a0 ] (choices_Calculator_Types_Key put)

        Calculator.Types.Point ->
            ModelTree.variant "Point" [] (choices_Calculator_Types_Key put)

        Calculator.Types.Operator a0 ->
            ModelTree.variant "Operator" [ \() -> tree_Calculator_Types_Operator (\new -> put (Calculator.Types.Operator new)) a0 ] (choices_Calculator_Types_Key put)

        Calculator.Types.Equals ->
            ModelTree.variant "Equals" [] (choices_Calculator_Types_Key put)

        Calculator.Types.Negate ->
            ModelTree.variant "Negate" [] (choices_Calculator_Types_Key put)

        Calculator.Types.Backspace ->
            ModelTree.variant "Backspace" [] (choices_Calculator_Types_Key put)

        Calculator.Types.Clear ->
            ModelTree.variant "Clear" [] (choices_Calculator_Types_Key put)


choices_Calculator_Types_Key put =
    [ ( "Point", \() -> put Calculator.Types.Point )
    , ( "Equals", \() -> put Calculator.Types.Equals )
    , ( "Negate", \() -> put Calculator.Types.Negate )
    , ( "Backspace", \() -> put Calculator.Types.Backspace )
    , ( "Clear", \() -> put Calculator.Types.Clear )
    ]


tree_Calculator_Types_Operator put value =
    case value of
        Calculator.Types.Add ->
            ModelTree.variant "Add" [] (choices_Calculator_Types_Operator put)

        Calculator.Types.Subtract ->
            ModelTree.variant "Subtract" [] (choices_Calculator_Types_Operator put)

        Calculator.Types.Multiply ->
            ModelTree.variant "Multiply" [] (choices_Calculator_Types_Operator put)

        Calculator.Types.Divide ->
            ModelTree.variant "Divide" [] (choices_Calculator_Types_Operator put)


choices_Calculator_Types_Operator put =
    [ ( "Add", \() -> put Calculator.Types.Add )
    , ( "Subtract", \() -> put Calculator.Types.Subtract )
    , ( "Multiply", \() -> put Calculator.Types.Multiply )
    , ( "Divide", \() -> put Calculator.Types.Divide )
    ]


tree_Calculator_Types_UiId put value =
    case value of
        Calculator.Types.KeyButton a0 ->
            ModelTree.variant "KeyButton" [ \() -> tree_Calculator_Types_Key (\new -> put (Calculator.Types.KeyButton new)) a0 ] (choices_Calculator_Types_UiId put)

        Calculator.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_Calculator_Types_UiId put)

        Calculator.Types.Panel ->
            ModelTree.variant "Panel" [] (choices_Calculator_Types_UiId put)


choices_Calculator_Types_UiId put =
    [ ( "CloseButton", \() -> put Calculator.Types.CloseButton )
    , ( "Panel", \() -> put Calculator.Types.Panel )
    ]


tree_Code_Model put value =
    ModelTree.record
        [ ( "isOpen", \() -> ModelTree.bool (\x -> put { value | isOpen = x }) value.isOpen )
        , ( "module_", \() -> ModelTree.maybe ModelTree.string (\x -> put { value | module_ = x }) value.module_ )
        , ( "saved", \() -> ModelTree.seqDict ModelTree.string ModelTree.string (\x -> put { value | saved = x }) value.saved )
        , ( "build", \() -> ModelTree.maybe tree_Code_Types_BuildStatus (\x -> put { value | build = x }) value.build )
        , ( "showErrors", \() -> ModelTree.bool (\x -> put { value | showErrors = x }) value.showErrors )
        , ( "committing", \() -> ModelTree.bool (\x -> put { value | committing = x }) value.committing )
        , ( "git", \() -> tree_Code_Types_Git (\x -> put { value | git = x }) value.git )
        , ( "finding", \() -> ModelTree.bool (\x -> put { value | finding = x }) value.finding )
        , ( "back", \() -> ModelTree.list tree_Code_Types_Place (\x -> put { value | back = x }) value.back )
        , ( "forward", \() -> ModelTree.list tree_Code_Types_Place (\x -> put { value | forward = x }) value.forward )
        , ( "lastPlace", \() -> ModelTree.maybe tree_Code_Types_Place (\x -> put { value | lastPlace = x }) value.lastPlace )
        , ( "usages", \() -> ModelTree.maybe tree_Code_Types_UsageList (\x -> put { value | usages = x }) value.usages )
        ]


tree_Code_Index_Usage put value =
    ModelTree.record
        [ ( "module_", \() -> ModelTree.string (\x -> put { value | module_ = x }) value.module_ )
        , ( "position", \() -> ModelTree.int (\x -> put { value | position = x }) value.position )
        , ( "line", \() -> ModelTree.int (\x -> put { value | line = x }) value.line )
        , ( "text", \() -> ModelTree.string (\x -> put { value | text = x }) value.text )
        ]


tree_Code_Types_BuildStatus put value =
    case value of
        Code.Types.BuildRunning a0 ->
            ModelTree.variant "BuildRunning" [ \() -> ModelTree.string (\new -> put (Code.Types.BuildRunning new)) a0 ] []

        Code.Types.BuildFailed a0 a1 ->
            ModelTree.variant "BuildFailed" [ \() -> ModelTree.string (\new -> put (Code.Types.BuildFailed new a1)) a0, \() -> ModelTree.string (\new -> put (Code.Types.BuildFailed a0 new)) a1 ] []

        Code.Types.Built a0 ->
            ModelTree.variant "Built" [ \() -> ModelTree.string (\new -> put (Code.Types.Built new)) a0 ] []


tree_Code_Types_Git put value =
    ModelTree.record
        [ ( "base", \() -> ModelTree.string (\x -> put { value | base = x }) value.base )
        , ( "branch", \() -> ModelTree.string (\x -> put { value | branch = x }) value.branch )
        , ( "from", \() -> ModelTree.string (\x -> put { value | from = x }) value.from )
        , ( "pushed", \() -> ModelTree.seqDict ModelTree.string ModelTree.string (\x -> put { value | pushed = x }) value.pushed )
        , ( "status", \() -> tree_Code_Types_GitStatus (\x -> put { value | status = x }) value.status )
        , ( "requests", \() -> ModelTree.int (\x -> put { value | requests = x }) value.requests )
        ]


tree_Code_Types_GitStatus put value =
    case value of
        Code.Types.GitIdle ->
            ModelTree.variant "GitIdle" [] (choices_Code_Types_GitStatus put)

        Code.Types.GitWorking a0 ->
            ModelTree.variant "GitWorking" [ \() -> tree_Code_Types_GitWork (\new -> put (Code.Types.GitWorking new)) a0 ] (choices_Code_Types_GitStatus put)

        Code.Types.GitPushed a0 a1 ->
            ModelTree.variant "GitPushed" [ \() -> ModelTree.string (\new -> put (Code.Types.GitPushed new a1)) a0, \() -> ModelTree.string (\new -> put (Code.Types.GitPushed a0 new)) a1 ] (choices_Code_Types_GitStatus put)

        Code.Types.GitFailed a0 a1 ->
            ModelTree.variant "GitFailed" [ \() -> ModelTree.string (\new -> put (Code.Types.GitFailed new a1)) a0, \() -> ModelTree.string (\new -> put (Code.Types.GitFailed a0 new)) a1 ] (choices_Code_Types_GitStatus put)


choices_Code_Types_GitStatus put =
    [ ( "GitIdle", \() -> put Code.Types.GitIdle )
    ]


tree_Code_Types_GitStep put value =
    case value of
        Code.Types.GettingBase ->
            ModelTree.variant "GettingBase" [] (choices_Code_Types_GitStep put)

        Code.Types.MakingTree ->
            ModelTree.variant "MakingTree" [] (choices_Code_Types_GitStep put)

        Code.Types.MakingCommit ->
            ModelTree.variant "MakingCommit" [] (choices_Code_Types_GitStep put)

        Code.Types.Pushing a0 ->
            ModelTree.variant "Pushing" [ \() -> ModelTree.string (\new -> put (Code.Types.Pushing new)) a0 ] (choices_Code_Types_GitStep put)

        Code.Types.MakingBranch a0 a1 ->
            ModelTree.variant "MakingBranch" [ \() -> ModelTree.string (\new -> put (Code.Types.MakingBranch new a1)) a0, \() -> ModelTree.string (\new -> put (Code.Types.MakingBranch a0 new)) a1 ] (choices_Code_Types_GitStep put)


choices_Code_Types_GitStep put =
    [ ( "GettingBase", \() -> put Code.Types.GettingBase )
    , ( "MakingTree", \() -> put Code.Types.MakingTree )
    , ( "MakingCommit", \() -> put Code.Types.MakingCommit )
    ]


tree_Code_Types_GitWork put value =
    ModelTree.record
        [ ( "request", \() -> ModelTree.int (\x -> put { value | request = x }) value.request )
        , ( "step", \() -> tree_Code_Types_GitStep (\x -> put { value | step = x }) value.step )
        , ( "token", \() -> ModelTree.string (\x -> put { value | token = x }) value.token )
        , ( "message", \() -> ModelTree.string (\x -> put { value | message = x }) value.message )
        , ( "base", \() -> ModelTree.string (\x -> put { value | base = x }) value.base )
        , ( "branch", \() -> ModelTree.string (\x -> put { value | branch = x }) value.branch )
        , ( "modules", \() -> ModelTree.seqDict ModelTree.string ModelTree.string (\x -> put { value | modules = x }) value.modules )
        ]


tree_Code_Types_Place put value =
    ModelTree.record
        [ ( "module_", \() -> ModelTree.string (\x -> put { value | module_ = x }) value.module_ )
        , ( "position", \() -> ModelTree.int (\x -> put { value | position = x }) value.position )
        , ( "line", \() -> ModelTree.int (\x -> put { value | line = x }) value.line )
        ]


tree_Code_Types_UiId put value =
    case value of
        Code.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_Code_Types_UiId put)

        Code.Types.Window ->
            ModelTree.variant "Window" [] (choices_Code_Types_UiId put)

        Code.Types.Input ->
            ModelTree.variant "Input" [] (choices_Code_Types_UiId put)

        Code.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_Code_Types_UiId put)

        Code.Types.ModulesViewport ->
            ModelTree.variant "ModulesViewport" [] (choices_Code_Types_UiId put)

        Code.Types.ModuleButton a0 ->
            ModelTree.variant "ModuleButton" [ \() -> ModelTree.string (\new -> put (Code.Types.ModuleButton new)) a0 ] (choices_Code_Types_UiId put)

        Code.Types.SaveButton ->
            ModelTree.variant "SaveButton" [] (choices_Code_Types_UiId put)

        Code.Types.RevertButton ->
            ModelTree.variant "RevertButton" [] (choices_Code_Types_UiId put)

        Code.Types.BuildButton ->
            ModelTree.variant "BuildButton" [] (choices_Code_Types_UiId put)

        Code.Types.DeployedButton ->
            ModelTree.variant "DeployedButton" [] (choices_Code_Types_UiId put)

        Code.Types.ErrorsCloseButton ->
            ModelTree.variant "ErrorsCloseButton" [] (choices_Code_Types_UiId put)

        Code.Types.ErrorsViewport ->
            ModelTree.variant "ErrorsViewport" [] (choices_Code_Types_UiId put)

        Code.Types.CommitButton ->
            ModelTree.variant "CommitButton" [] (choices_Code_Types_UiId put)

        Code.Types.CommitCloseButton ->
            ModelTree.variant "CommitCloseButton" [] (choices_Code_Types_UiId put)

        Code.Types.CommitViewport ->
            ModelTree.variant "CommitViewport" [] (choices_Code_Types_UiId put)

        Code.Types.TokenInput ->
            ModelTree.variant "TokenInput" [] (choices_Code_Types_UiId put)

        Code.Types.MessageInput ->
            ModelTree.variant "MessageInput" [] (choices_Code_Types_UiId put)

        Code.Types.PushButton ->
            ModelTree.variant "PushButton" [] (choices_Code_Types_UiId put)

        Code.Types.FindInput ->
            ModelTree.variant "FindInput" [] (choices_Code_Types_UiId put)

        Code.Types.ReplaceInput ->
            ModelTree.variant "ReplaceInput" [] (choices_Code_Types_UiId put)

        Code.Types.FindPreviousButton ->
            ModelTree.variant "FindPreviousButton" [] (choices_Code_Types_UiId put)

        Code.Types.FindNextButton ->
            ModelTree.variant "FindNextButton" [] (choices_Code_Types_UiId put)

        Code.Types.ReplaceButton ->
            ModelTree.variant "ReplaceButton" [] (choices_Code_Types_UiId put)

        Code.Types.ReplaceAllButton ->
            ModelTree.variant "ReplaceAllButton" [] (choices_Code_Types_UiId put)

        Code.Types.FindCloseButton ->
            ModelTree.variant "FindCloseButton" [] (choices_Code_Types_UiId put)

        Code.Types.UsagesViewport ->
            ModelTree.variant "UsagesViewport" [] (choices_Code_Types_UiId put)

        Code.Types.UsageButton a0 ->
            ModelTree.variant "UsageButton" [ \() -> ModelTree.int (\new -> put (Code.Types.UsageButton new)) a0 ] (choices_Code_Types_UiId put)

        Code.Types.UsagesCloseButton ->
            ModelTree.variant "UsagesCloseButton" [] (choices_Code_Types_UiId put)


choices_Code_Types_UiId put =
    [ ( "OpenButton", \() -> put Code.Types.OpenButton )
    , ( "Window", \() -> put Code.Types.Window )
    , ( "Input", \() -> put Code.Types.Input )
    , ( "CloseButton", \() -> put Code.Types.CloseButton )
    , ( "ModulesViewport", \() -> put Code.Types.ModulesViewport )
    , ( "SaveButton", \() -> put Code.Types.SaveButton )
    , ( "RevertButton", \() -> put Code.Types.RevertButton )
    , ( "BuildButton", \() -> put Code.Types.BuildButton )
    , ( "DeployedButton", \() -> put Code.Types.DeployedButton )
    , ( "ErrorsCloseButton", \() -> put Code.Types.ErrorsCloseButton )
    , ( "ErrorsViewport", \() -> put Code.Types.ErrorsViewport )
    , ( "CommitButton", \() -> put Code.Types.CommitButton )
    , ( "CommitCloseButton", \() -> put Code.Types.CommitCloseButton )
    , ( "CommitViewport", \() -> put Code.Types.CommitViewport )
    , ( "TokenInput", \() -> put Code.Types.TokenInput )
    , ( "MessageInput", \() -> put Code.Types.MessageInput )
    , ( "PushButton", \() -> put Code.Types.PushButton )
    , ( "FindInput", \() -> put Code.Types.FindInput )
    , ( "ReplaceInput", \() -> put Code.Types.ReplaceInput )
    , ( "FindPreviousButton", \() -> put Code.Types.FindPreviousButton )
    , ( "FindNextButton", \() -> put Code.Types.FindNextButton )
    , ( "ReplaceButton", \() -> put Code.Types.ReplaceButton )
    , ( "ReplaceAllButton", \() -> put Code.Types.ReplaceAllButton )
    , ( "FindCloseButton", \() -> put Code.Types.FindCloseButton )
    , ( "UsagesViewport", \() -> put Code.Types.UsagesViewport )
    , ( "UsagesCloseButton", \() -> put Code.Types.UsagesCloseButton )
    ]


tree_Code_Types_UsageList put value =
    ModelTree.record
        [ ( "module_", \() -> ModelTree.string (\x -> put { value | module_ = x }) value.module_ )
        , ( "name", \() -> ModelTree.string (\x -> put { value | name = x }) value.name )
        , ( "found", \() -> ModelTree.list tree_Code_Index_Usage (\x -> put { value | found = x }) value.found )
        ]


tree_Coord_Coord put value =
    ModelTree.tuple2 (ModelTree.quantity ModelTree.int) (ModelTree.quantity ModelTree.int) put value


tree_DebugInfo_Types_RendererInfo put value =
    ModelTree.record
        [ ( "gpu", \() -> ModelTree.bool (\x -> put { value | gpu = x }) value.gpu )
        , ( "name", \() -> ModelTree.string (\x -> put { value | name = x }) value.name )
        , ( "hardwareCursor", \() -> ModelTree.bool (\x -> put { value | hardwareCursor = x }) value.hardwareCursor )
        ]


tree_DebugInfo_Types_SystemStats put value =
    ModelTree.record
        [ ( "cores", \() -> ModelTree.int (\x -> put { value | cores = x }) value.cores )
        , ( "cpu", \() -> ModelTree.float (\x -> put { value | cpu = x }) value.cpu )
        , ( "cpuElm", \() -> ModelTree.float (\x -> put { value | cpuElm = x }) value.cpuElm )
        , ( "cpuHost", \() -> ModelTree.float (\x -> put { value | cpuHost = x }) value.cpuHost )
        , ( "cpuGpu", \() -> ModelTree.float (\x -> put { value | cpuGpu = x }) value.cpuGpu )
        , ( "memUsed", \() -> ModelTree.int (\x -> put { value | memUsed = x }) value.memUsed )
        , ( "memTotal", \() -> ModelTree.int (\x -> put { value | memTotal = x }) value.memTotal )
        , ( "gpuMs", \() -> ModelTree.maybe ModelTree.float (\x -> put { value | gpuMs = x }) value.gpuMs )
        , ( "elmMs", \() -> ModelTree.maybe ModelTree.float (\x -> put { value | elmMs = x }) value.elmMs )
        , ( "drawMs", \() -> ModelTree.maybe ModelTree.float (\x -> put { value | drawMs = x }) value.drawMs )
        ]


tree_DebugInfo_Types_UiId put value =
    case value of
        DebugInfo.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_DebugInfo_Types_UiId put)

        DebugInfo.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_DebugInfo_Types_UiId put)


choices_DebugInfo_Types_UiId put =
    [ ( "OpenButton", \() -> put DebugInfo.Types.OpenButton )
    , ( "CloseButton", \() -> put DebugInfo.Types.CloseButton )
    ]


tree_Display_Display put value =
    ModelTree.record
        [ ( "id", \() -> ModelTree.int (\x -> put { value | id = x }) value.id )
        , ( "name", \() -> ModelTree.string (\x -> put { value | name = x }) value.name )
        , ( "position", \() -> tree_Coord_Coord (\x -> put { value | position = x }) value.position )
        , ( "size", \() -> tree_Coord_Coord (\x -> put { value | size = x }) value.size )
        , ( "sizeMm", \() -> ModelTree.tuple2 ModelTree.int ModelTree.int (\x -> put { value | sizeMm = x }) value.sizeMm )
        ]


tree_Editor_Types_UiId put value =
    case value of
        Editor.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_Editor_Types_UiId put)

        Editor.Types.Input ->
            ModelTree.variant "Input" [] (choices_Editor_Types_UiId put)

        Editor.Types.Window ->
            ModelTree.variant "Window" [] (choices_Editor_Types_UiId put)

        Editor.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_Editor_Types_UiId put)


choices_Editor_Types_UiId put =
    [ ( "OpenButton", \() -> put Editor.Types.OpenButton )
    , ( "Input", \() -> put Editor.Types.Input )
    , ( "Window", \() -> put Editor.Types.Window )
    , ( "CloseButton", \() -> put Editor.Types.CloseButton )
    ]


tree_Effect_HttpError put value =
    case value of
        Effect.BadUrl a0 ->
            ModelTree.variant "BadUrl" [ \() -> ModelTree.string (\new -> put (Effect.BadUrl new)) a0 ] (choices_Effect_HttpError put)

        Effect.Timeout ->
            ModelTree.variant "Timeout" [] (choices_Effect_HttpError put)

        Effect.NetworkError a0 ->
            ModelTree.variant "NetworkError" [ \() -> ModelTree.string (\new -> put (Effect.NetworkError new)) a0 ] (choices_Effect_HttpError put)

        Effect.Interrupted ->
            ModelTree.variant "Interrupted" [] (choices_Effect_HttpError put)

        Effect.BadBody a0 ->
            ModelTree.variant "BadBody" [ \() -> (\put1 value1 -> ModelTree.record [ ( "status", \() -> ModelTree.int (\x1 -> put1 { value1 | status = x1 }) value1.status ), ( "body", \() -> ModelTree.string (\x1 -> put1 { value1 | body = x1 }) value1.body ) ]) (\new -> put (Effect.BadBody new)) a0 ] (choices_Effect_HttpError put)

        Effect.FailedToDecodeBody a0 ->
            ModelTree.variant "FailedToDecodeBody" [ \() -> ModelTree.string (\new -> put (Effect.FailedToDecodeBody new)) a0 ] (choices_Effect_HttpError put)


choices_Effect_HttpError put =
    [ ( "Timeout", \() -> put Effect.Timeout )
    , ( "Interrupted", \() -> put Effect.Interrupted )
    ]


tree_Email_Account put value =
    ModelTree.record
        [ ( "server", \() -> ModelTree.string (\x -> put { value | server = x }) value.server )
        , ( "address", \() -> ModelTree.string (\x -> put { value | address = x }) value.address )
        , ( "password", \() -> ModelTree.string (\x -> put { value | password = x }) value.password )
        ]


tree_Email_Job put value =
    case value of
        Email.ListInbox ->
            ModelTree.variant "ListInbox" [] (choices_Email_Job put)

        Email.ReadMessage a0 ->
            ModelTree.variant "ReadMessage" [ \() -> ModelTree.int (\new -> put (Email.ReadMessage new)) a0 ] (choices_Email_Job put)


choices_Email_Job put =
    [ ( "ListInbox", \() -> put Email.ListInbox )
    ]


tree_Email_MessageState put value =
    case value of
        Email.MessageLoading ->
            ModelTree.variant "MessageLoading" [] (choices_Email_MessageState put)

        Email.MessageLoaded a0 ->
            ModelTree.variant "MessageLoaded" [ \() -> ModelTree.string (\new -> put (Email.MessageLoaded new)) a0 ] (choices_Email_MessageState put)

        Email.MessageFailed a0 ->
            ModelTree.variant "MessageFailed" [ \() -> ModelTree.string (\new -> put (Email.MessageFailed new)) a0 ] (choices_Email_MessageState put)


choices_Email_MessageState put =
    [ ( "MessageLoading", \() -> put Email.MessageLoading )
    ]


tree_Email_Model put value =
    ModelTree.record
        [ ( "isOpen", \() -> ModelTree.bool (\x -> put { value | isOpen = x }) value.isOpen )
        , ( "account", \() -> ModelTree.maybe tree_Email_Account (\x -> put { value | account = x }) value.account )
        , ( "inbox", \() -> ModelTree.list tree_Email_Summary (\x -> put { value | inbox = x }) value.inbox )
        , ( "page", \() -> tree_Email_Page (\x -> put { value | page = x }) value.page )
        , ( "session", \() -> ModelTree.maybe tree_Email_Session (\x -> put { value | session = x }) value.session )
        , ( "sessionCount", \() -> ModelTree.int (\x -> put { value | sessionCount = x }) value.sessionCount )
        , ( "error", \() -> ModelTree.maybe ModelTree.string (\x -> put { value | error = x }) value.error )
        ]


tree_Email_Page put value =
    case value of
        Email.InboxPage ->
            ModelTree.variant "InboxPage" [] (choices_Email_Page put)

        Email.MessagePage a0 ->
            ModelTree.variant "MessagePage" [ \() -> (\put1 value1 -> ModelTree.record [ ( "uid", \() -> ModelTree.int (\x1 -> put1 { value1 | uid = x1 }) value1.uid ), ( "state", \() -> tree_Email_MessageState (\x1 -> put1 { value1 | state = x1 }) value1.state ) ]) (\new -> put (Email.MessagePage new)) a0 ] (choices_Email_Page put)


choices_Email_Page put =
    [ ( "InboxPage", \() -> put Email.InboxPage )
    ]


tree_Email_Session put value =
    ModelTree.record
        [ ( "id", \() -> ModelTree.string (\x -> put { value | id = x }) value.id )
        , ( "job", \() -> tree_Email_Job (\x -> put { value | job = x }) value.job )
        , ( "stage", \() -> tree_Email_Stage (\x -> put { value | stage = x }) value.stage )
        , ( "buffer", \() -> ModelTree.string (\x -> put { value | buffer = x }) value.buffer )
        , ( "exists", \() -> ModelTree.int (\x -> put { value | exists = x }) value.exists )
        , ( "results", \() -> ModelTree.list tree_Email_Imap_Fetched (\x -> put { value | results = x }) value.results )
        , ( "startedAt", \() -> ModelTree.maybe ModelTree.int (\x -> put { value | startedAt = x }) value.startedAt )
        ]


tree_Email_Stage put value =
    case value of
        Email.Connecting ->
            ModelTree.variant "Connecting" [] (choices_Email_Stage put)

        Email.WaitingForGreeting ->
            ModelTree.variant "WaitingForGreeting" [] (choices_Email_Stage put)

        Email.LoggingIn ->
            ModelTree.variant "LoggingIn" [] (choices_Email_Stage put)

        Email.Selecting ->
            ModelTree.variant "Selecting" [] (choices_Email_Stage put)

        Email.Fetching ->
            ModelTree.variant "Fetching" [] (choices_Email_Stage put)


choices_Email_Stage put =
    [ ( "Connecting", \() -> put Email.Connecting )
    , ( "WaitingForGreeting", \() -> put Email.WaitingForGreeting )
    , ( "LoggingIn", \() -> put Email.LoggingIn )
    , ( "Selecting", \() -> put Email.Selecting )
    , ( "Fetching", \() -> put Email.Fetching )
    ]


tree_Email_Summary put value =
    ModelTree.record
        [ ( "uid", \() -> ModelTree.int (\x -> put { value | uid = x }) value.uid )
        , ( "from", \() -> ModelTree.string (\x -> put { value | from = x }) value.from )
        , ( "subject", \() -> ModelTree.string (\x -> put { value | subject = x }) value.subject )
        , ( "date", \() -> ModelTree.string (\x -> put { value | date = x }) value.date )
        , ( "seen", \() -> ModelTree.bool (\x -> put { value | seen = x }) value.seen )
        ]


tree_Email_Imap_Fetched put value =
    ModelTree.record
        [ ( "uid", \() -> ModelTree.int (\x -> put { value | uid = x }) value.uid )
        , ( "seen", \() -> ModelTree.bool (\x -> put { value | seen = x }) value.seen )
        , ( "header", \() -> ModelTree.string (\x -> put { value | header = x }) value.header )
        , ( "text", \() -> ModelTree.string (\x -> put { value | text = x }) value.text )
        ]


tree_Email_Types_Field put value =
    case value of
        Email.Types.AddressField ->
            ModelTree.variant "AddressField" [] (choices_Email_Types_Field put)

        Email.Types.PasswordField ->
            ModelTree.variant "PasswordField" [] (choices_Email_Types_Field put)

        Email.Types.ServerField ->
            ModelTree.variant "ServerField" [] (choices_Email_Types_Field put)


choices_Email_Types_Field put =
    [ ( "AddressField", \() -> put Email.Types.AddressField )
    , ( "PasswordField", \() -> put Email.Types.PasswordField )
    , ( "ServerField", \() -> put Email.Types.ServerField )
    ]


tree_Email_Types_UiId put value =
    case value of
        Email.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_Email_Types_UiId put)

        Email.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_Email_Types_UiId put)

        Email.Types.InputField a0 ->
            ModelTree.variant "InputField" [ \() -> tree_Email_Types_Field (\new -> put (Email.Types.InputField new)) a0 ] (choices_Email_Types_UiId put)

        Email.Types.LinkButton ->
            ModelTree.variant "LinkButton" [] (choices_Email_Types_UiId put)

        Email.Types.RefreshButton ->
            ModelTree.variant "RefreshButton" [] (choices_Email_Types_UiId put)

        Email.Types.SignOutButton ->
            ModelTree.variant "SignOutButton" [] (choices_Email_Types_UiId put)

        Email.Types.BackButton ->
            ModelTree.variant "BackButton" [] (choices_Email_Types_UiId put)

        Email.Types.MessageButton a0 ->
            ModelTree.variant "MessageButton" [ \() -> ModelTree.int (\new -> put (Email.Types.MessageButton new)) a0 ] (choices_Email_Types_UiId put)

        Email.Types.ListViewport ->
            ModelTree.variant "ListViewport" [] (choices_Email_Types_UiId put)

        Email.Types.MessageViewport ->
            ModelTree.variant "MessageViewport" [] (choices_Email_Types_UiId put)


choices_Email_Types_UiId put =
    [ ( "OpenButton", \() -> put Email.Types.OpenButton )
    , ( "CloseButton", \() -> put Email.Types.CloseButton )
    , ( "LinkButton", \() -> put Email.Types.LinkButton )
    , ( "RefreshButton", \() -> put Email.Types.RefreshButton )
    , ( "SignOutButton", \() -> put Email.Types.SignOutButton )
    , ( "BackButton", \() -> put Email.Types.BackButton )
    , ( "ListViewport", \() -> put Email.Types.ListViewport )
    , ( "MessageViewport", \() -> put Email.Types.MessageViewport )
    ]


tree_HackerNews_HackerNewsState put value =
    case value of
        HackerNews.NotLoading ->
            ModelTree.variant "NotLoading" [] (choices_HackerNews_HackerNewsState put)

        HackerNews.Loading a0 ->
            ModelTree.variant "Loading" [ \() -> ModelTree.maybe (ModelTree.list tree_HackerNews_Types_Post) (\new -> put (HackerNews.Loading new)) a0 ] (choices_HackerNews_HackerNewsState put)

        HackerNews.Loaded a0 ->
            ModelTree.variant "Loaded" [ \() -> ModelTree.list tree_HackerNews_Types_Post (\new -> put (HackerNews.Loaded new)) a0 ] (choices_HackerNews_HackerNewsState put)

        HackerNews.LoadFailed a0 ->
            ModelTree.variant "LoadFailed" [ \() -> tree_Effect_HttpError (\new -> put (HackerNews.LoadFailed new)) a0 ] (choices_HackerNews_HackerNewsState put)


choices_HackerNews_HackerNewsState put =
    [ ( "NotLoading", \() -> put HackerNews.NotLoading )
    ]


tree_HackerNews_Model put value =
    ModelTree.record
        [ ( "data", \() -> tree_HackerNews_HackerNewsState (\x -> put { value | data = x }) value.data )
        , ( "page", \() -> ModelTree.opaqueTree "HackerNews.Page" (\x -> put { value | page = x }) value.page )
        , ( "comments", \() -> ModelTree.seqDict tree_HackerNews_Types_PostId (\put1 value1 -> ModelTree.record [ ( "opened", \() -> ModelTree.int (\x1 -> put1 { value1 | opened = x1 }) value1.opened ), ( "state", \() -> ModelTree.opaqueTree "HackerNews.CommentsState" (\x1 -> put1 { value1 | state = x1 }) value1.state ) ]) (\x -> put { value | comments = x }) value.comments )
        , ( "openCount", \() -> ModelTree.int (\x -> put { value | openCount = x }) value.openCount )
        , ( "isOpen", \() -> ModelTree.bool (\x -> put { value | isOpen = x }) value.isOpen )
        ]


tree_HackerNews_Types_Post put value =
    ModelTree.record
        [ ( "id", \() -> tree_HackerNews_Types_PostId (\x -> put { value | id = x }) value.id )
        , ( "title", \() -> ModelTree.string (\x -> put { value | title = x }) value.title )
        , ( "comments", \() -> ModelTree.int (\x -> put { value | comments = x }) value.comments )
        ]


tree_HackerNews_Types_PostId put value =
    case value of
        HackerNews.Types.PostId a0 ->
            ModelTree.variant "PostId" [ \() -> ModelTree.string (\new -> put (HackerNews.Types.PostId new)) a0 ] []


tree_HackerNews_Types_UiId put value =
    case value of
        HackerNews.Types.PostButton a0 ->
            ModelTree.variant "PostButton" [ \() -> tree_HackerNews_Types_PostId (\new -> put (HackerNews.Types.PostButton new)) a0 ] (choices_HackerNews_Types_UiId put)

        HackerNews.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_HackerNews_Types_UiId put)

        HackerNews.Types.PostsViewport ->
            ModelTree.variant "PostsViewport" [] (choices_HackerNews_Types_UiId put)

        HackerNews.Types.CommentsViewport a0 ->
            ModelTree.variant "CommentsViewport" [ \() -> tree_HackerNews_Types_PostId (\new -> put (HackerNews.Types.CommentsViewport new)) a0 ] (choices_HackerNews_Types_UiId put)

        HackerNews.Types.BackButton ->
            ModelTree.variant "BackButton" [] (choices_HackerNews_Types_UiId put)

        HackerNews.Types.CommentToggle a0 ->
            ModelTree.variant "CommentToggle" [ \() -> ModelTree.int (\new -> put (HackerNews.Types.CommentToggle new)) a0 ] (choices_HackerNews_Types_UiId put)

        HackerNews.Types.CommentLink ->
            ModelTree.variant "CommentLink" [] (choices_HackerNews_Types_UiId put)


choices_HackerNews_Types_UiId put =
    [ ( "OpenButton", \() -> put HackerNews.Types.OpenButton )
    , ( "PostsViewport", \() -> put HackerNews.Types.PostsViewport )
    , ( "BackButton", \() -> put HackerNews.Types.BackButton )
    , ( "CommentLink", \() -> put HackerNews.Types.CommentLink )
    ]


tree_History_Head put value =
    ModelTree.record
        [ ( "name", \() -> ModelTree.string (\x -> put { value | name = x }) value.name )
        , ( "sha", \() -> ModelTree.string (\x -> put { value | sha = x }) value.sha )
        ]


tree_History_Model put value =
    ModelTree.record
        [ ( "isOpen", \() -> ModelTree.bool (\x -> put { value | isOpen = x }) value.isOpen )
        , ( "generation", \() -> ModelTree.int (\x -> put { value | generation = x }) value.generation )
        , ( "waiting", \() -> ModelTree.list (ModelTree.tuple2 ModelTree.int ModelTree.string) (\x -> put { value | waiting = x }) value.waiting )
        , ( "heads", \() -> ModelTree.list tree_History_Head (\x -> put { value | heads = x }) value.heads )
        , ( "commits", \() -> ModelTree.seqDict ModelTree.string tree_History_Types_Commit (\x -> put { value | commits = x }) value.commits )
        , ( "error", \() -> ModelTree.maybe ModelTree.string (\x -> put { value | error = x }) value.error )
        ]


tree_History_Types_Commit put value =
    ModelTree.record
        [ ( "sha", \() -> ModelTree.string (\x -> put { value | sha = x }) value.sha )
        , ( "parents", \() -> ModelTree.list ModelTree.string (\x -> put { value | parents = x }) value.parents )
        , ( "subject", \() -> ModelTree.string (\x -> put { value | subject = x }) value.subject )
        , ( "description", \() -> ModelTree.string (\x -> put { value | description = x }) value.description )
        , ( "author", \() -> ModelTree.string (\x -> put { value | author = x }) value.author )
        , ( "time", \() -> ModelTree.int (\x -> put { value | time = x }) value.time )
        ]


tree_History_Types_UiId put value =
    case value of
        History.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_History_Types_UiId put)

        History.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_History_Types_UiId put)

        History.Types.RefreshButton ->
            ModelTree.variant "RefreshButton" [] (choices_History_Types_UiId put)

        History.Types.ListViewport ->
            ModelTree.variant "ListViewport" [] (choices_History_Types_UiId put)


choices_History_Types_UiId put =
    [ ( "OpenButton", \() -> put History.Types.OpenButton )
    , ( "CloseButton", \() -> put History.Types.CloseButton )
    , ( "RefreshButton", \() -> put History.Types.RefreshButton )
    , ( "ListViewport", \() -> put History.Types.ListViewport )
    ]


tree_Image_Chunk put value =
    ModelTree.record
        [ ( "hash", \() -> ModelTree.tuple2 ModelTree.int ModelTree.int (\x -> put { value | hash = x }) value.hash )
        , ( "pixels", \() -> ModelTree.bytes (\x -> put { value | pixels = x }) value.pixels )
        ]


tree_Image_Image put value =
    ModelTree.record
        [ ( "across", \() -> ModelTree.int (\x -> put { value | across = x }) value.across )
        , ( "chunks", \() -> ModelTree.array tree_Image_Chunk (\x -> put { value | chunks = x }) value.chunks )
        ]


tree_Install_Choice put value =
    case value of
        Install.InstallOn a0 a1 ->
            ModelTree.variant "InstallOn" [ \() -> ModelTree.string (\new -> put (Install.InstallOn new a1)) a0, \() -> tree_Install_Types_Target (\new -> put (Install.InstallOn a0 new)) a1 ] []

        Install.UpdateOn a0 ->
            ModelTree.variant "UpdateOn" [ \() -> ModelTree.string (\new -> put (Install.UpdateOn new)) a0 ] []


tree_Install_Model put value =
    ModelTree.record
        [ ( "isOpen", \() -> ModelTree.bool (\x -> put { value | isOpen = x }) value.isOpen )
        , ( "disks", \() -> ModelTree.maybe (ModelTree.list tree_Install_Types_Disk) (\x -> put { value | disks = x }) value.disks )
        , ( "chosen", \() -> ModelTree.maybe tree_Install_Choice (\x -> put { value | chosen = x }) value.chosen )
        , ( "keepData", \() -> ModelTree.bool (\x -> put { value | keepData = x }) value.keepData )
        , ( "confirming", \() -> ModelTree.bool (\x -> put { value | confirming = x }) value.confirming )
        , ( "status", \() -> ModelTree.maybe tree_Install_Types_Status (\x -> put { value | status = x }) value.status )
        ]


tree_Install_Types_Contents put value =
    case value of
        Install.Types.EfiSystem ->
            ModelTree.variant "EfiSystem" [] (choices_Install_Types_Contents put)

        Install.Types.Ntfs ->
            ModelTree.variant "Ntfs" [] (choices_Install_Types_Contents put)

        Install.Types.BitLocker ->
            ModelTree.variant "BitLocker" [] (choices_Install_Types_Contents put)

        Install.Types.Ext4 ->
            ModelTree.variant "Ext4" [] (choices_Install_Types_Contents put)

        Install.Types.Btrfs ->
            ModelTree.variant "Btrfs" [] (choices_Install_Types_Contents put)

        Install.Types.Fat ->
            ModelTree.variant "Fat" [] (choices_Install_Types_Contents put)

        Install.Types.Swap ->
            ModelTree.variant "Swap" [] (choices_Install_Types_Contents put)

        Install.Types.Luks ->
            ModelTree.variant "Luks" [] (choices_Install_Types_Contents put)

        Install.Types.MicrosoftReserved ->
            ModelTree.variant "MicrosoftReserved" [] (choices_Install_Types_Contents put)

        Install.Types.WindowsRecovery ->
            ModelTree.variant "WindowsRecovery" [] (choices_Install_Types_Contents put)

        Install.Types.ElmOsData ->
            ModelTree.variant "ElmOsData" [] (choices_Install_Types_Contents put)

        Install.Types.ElmOsTools ->
            ModelTree.variant "ElmOsTools" [] (choices_Install_Types_Contents put)

        Install.Types.Empty ->
            ModelTree.variant "Empty" [] (choices_Install_Types_Contents put)

        Install.Types.Other ->
            ModelTree.variant "Other" [] (choices_Install_Types_Contents put)


choices_Install_Types_Contents put =
    [ ( "EfiSystem", \() -> put Install.Types.EfiSystem )
    , ( "Ntfs", \() -> put Install.Types.Ntfs )
    , ( "BitLocker", \() -> put Install.Types.BitLocker )
    , ( "Ext4", \() -> put Install.Types.Ext4 )
    , ( "Btrfs", \() -> put Install.Types.Btrfs )
    , ( "Fat", \() -> put Install.Types.Fat )
    , ( "Swap", \() -> put Install.Types.Swap )
    , ( "Luks", \() -> put Install.Types.Luks )
    , ( "MicrosoftReserved", \() -> put Install.Types.MicrosoftReserved )
    , ( "WindowsRecovery", \() -> put Install.Types.WindowsRecovery )
    , ( "ElmOsData", \() -> put Install.Types.ElmOsData )
    , ( "ElmOsTools", \() -> put Install.Types.ElmOsTools )
    , ( "Empty", \() -> put Install.Types.Empty )
    , ( "Other", \() -> put Install.Types.Other )
    ]


tree_Install_Types_Disk put value =
    ModelTree.record
        [ ( "name", \() -> ModelTree.string (\x -> put { value | name = x }) value.name )
        , ( "model", \() -> ModelTree.string (\x -> put { value | model = x }) value.model )
        , ( "bytes", \() -> ModelTree.int (\x -> put { value | bytes = x }) value.bytes )
        , ( "usb", \() -> ModelTree.bool (\x -> put { value | usb = x }) value.usb )
        , ( "booted", \() -> ModelTree.bool (\x -> put { value | booted = x }) value.booted )
        , ( "busy", \() -> ModelTree.bool (\x -> put { value | busy = x }) value.busy )
        , ( "installed", \() -> ModelTree.bool (\x -> put { value | installed = x }) value.installed )
        , ( "layout", \() -> ModelTree.string (\x -> put { value | layout = x }) value.layout )
        , ( "table", \() -> tree_Install_Types_Table (\x -> put { value | table = x }) value.table )
        , ( "regions", \() -> ModelTree.list tree_Install_Types_Region (\x -> put { value | regions = x }) value.regions )
        ]


tree_Install_Types_Partition put value =
    ModelTree.record
        [ ( "number", \() -> ModelTree.int (\x -> put { value | number = x }) value.number )
        , ( "name", \() -> ModelTree.string (\x -> put { value | name = x }) value.name )
        , ( "contents", \() -> tree_Install_Types_Contents (\x -> put { value | contents = x }) value.contents )
        ]


tree_Install_Types_Region put value =
    ModelTree.record
        [ ( "start", \() -> ModelTree.int (\x -> put { value | start = x }) value.start )
        , ( "bytes", \() -> ModelTree.int (\x -> put { value | bytes = x }) value.bytes )
        , ( "partition", \() -> ModelTree.maybe tree_Install_Types_Partition (\x -> put { value | partition = x }) value.partition )
        ]


tree_Install_Types_Status put value =
    case value of
        Install.Types.Running a0 ->
            ModelTree.variant "Running" [ \() -> (\put1 value1 -> ModelTree.record [ ( "step", \() -> ModelTree.string (\x1 -> put1 { value1 | step = x1 }) value1.step ), ( "done", \() -> ModelTree.float (\x1 -> put1 { value1 | done = x1 }) value1.done ) ]) (\new -> put (Install.Types.Running new)) a0 ] []

        Install.Types.Failed a0 ->
            ModelTree.variant "Failed" [ \() -> (\put1 value1 -> ModelTree.record [ ( "step", \() -> ModelTree.string (\x1 -> put1 { value1 | step = x1 }) value1.step ), ( "message", \() -> ModelTree.string (\x1 -> put1 { value1 | message = x1 }) value1.message ), ( "wrote", \() -> ModelTree.bool (\x1 -> put1 { value1 | wrote = x1 }) value1.wrote ) ]) (\new -> put (Install.Types.Failed new)) a0 ] []

        Install.Types.Installed a0 ->
            ModelTree.variant "Installed" [ \() -> (\put1 value1 -> ModelTree.record [ ( "grub", \() -> ModelTree.string (\x1 -> put1 { value1 | grub = x1 }) value1.grub ) ]) (\new -> put (Install.Types.Installed new)) a0 ] []


tree_Install_Types_Table put value =
    case value of
        Install.Types.Gpt ->
            ModelTree.variant "Gpt" [] (choices_Install_Types_Table put)

        Install.Types.Mbr ->
            ModelTree.variant "Mbr" [] (choices_Install_Types_Table put)

        Install.Types.NoTable ->
            ModelTree.variant "NoTable" [] (choices_Install_Types_Table put)


choices_Install_Types_Table put =
    [ ( "Gpt", \() -> put Install.Types.Gpt )
    , ( "Mbr", \() -> put Install.Types.Mbr )
    , ( "NoTable", \() -> put Install.Types.NoTable )
    ]


tree_Install_Types_Target put value =
    case value of
        Install.Types.FreeSpace a0 ->
            ModelTree.variant "FreeSpace" [ \() -> ModelTree.int (\new -> put (Install.Types.FreeSpace new)) a0 ] (choices_Install_Types_Target put)

        Install.Types.InPartition a0 ->
            ModelTree.variant "InPartition" [ \() -> ModelTree.int (\new -> put (Install.Types.InPartition new)) a0 ] (choices_Install_Types_Target put)

        Install.Types.WholeDisk ->
            ModelTree.variant "WholeDisk" [] (choices_Install_Types_Target put)


choices_Install_Types_Target put =
    [ ( "WholeDisk", \() -> put Install.Types.WholeDisk )
    ]


tree_Install_Types_UiId put value =
    case value of
        Install.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_Install_Types_UiId put)

        Install.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_Install_Types_UiId put)

        Install.Types.RefreshButton ->
            ModelTree.variant "RefreshButton" [] (choices_Install_Types_UiId put)

        Install.Types.RegionButton a0 a1 ->
            ModelTree.variant "RegionButton" [ \() -> ModelTree.string (\new -> put (Install.Types.RegionButton new a1)) a0, \() -> ModelTree.int (\new -> put (Install.Types.RegionButton a0 new)) a1 ] (choices_Install_Types_UiId put)

        Install.Types.WholeDiskButton a0 ->
            ModelTree.variant "WholeDiskButton" [ \() -> ModelTree.string (\new -> put (Install.Types.WholeDiskButton new)) a0 ] (choices_Install_Types_UiId put)

        Install.Types.UpdateButton a0 ->
            ModelTree.variant "UpdateButton" [ \() -> ModelTree.string (\new -> put (Install.Types.UpdateButton new)) a0 ] (choices_Install_Types_UiId put)

        Install.Types.KeepDataButton ->
            ModelTree.variant "KeepDataButton" [] (choices_Install_Types_UiId put)

        Install.Types.InstallButton ->
            ModelTree.variant "InstallButton" [] (choices_Install_Types_UiId put)

        Install.Types.ConfirmButton ->
            ModelTree.variant "ConfirmButton" [] (choices_Install_Types_UiId put)

        Install.Types.CancelButton ->
            ModelTree.variant "CancelButton" [] (choices_Install_Types_UiId put)

        Install.Types.DoneButton ->
            ModelTree.variant "DoneButton" [] (choices_Install_Types_UiId put)

        Install.Types.ListViewport ->
            ModelTree.variant "ListViewport" [] (choices_Install_Types_UiId put)


choices_Install_Types_UiId put =
    [ ( "OpenButton", \() -> put Install.Types.OpenButton )
    , ( "CloseButton", \() -> put Install.Types.CloseButton )
    , ( "RefreshButton", \() -> put Install.Types.RefreshButton )
    , ( "KeepDataButton", \() -> put Install.Types.KeepDataButton )
    , ( "InstallButton", \() -> put Install.Types.InstallButton )
    , ( "ConfirmButton", \() -> put Install.Types.ConfirmButton )
    , ( "CancelButton", \() -> put Install.Types.CancelButton )
    , ( "DoneButton", \() -> put Install.Types.DoneButton )
    , ( "ListViewport", \() -> put Install.Types.ListViewport )
    ]


tree_Main_Model put value =
    ModelTree.record
        [ ( "displays", \() -> ModelTree.list tree_Display_Display (\x -> put { value | displays = x }) value.displays )
        , ( "appDisplays", \() -> ModelTree.seqDict (ModelTree.opaqueTree "Main.App") ModelTree.string (\x -> put { value | appDisplays = x }) value.appDisplays )
        , ( "mouse", \() -> tree_Coord_Coord (\x -> put { value | mouse = x }) value.mouse )
        , ( "colorIndex", \() -> ModelTree.int (\x -> put { value | colorIndex = x }) value.colorIndex )
        , ( "pressed", \() -> ModelTree.bool (\x -> put { value | pressed = x }) value.pressed )
        , ( "renderer", \() -> ModelTree.maybe tree_DebugInfo_Types_RendererInfo (\x -> put { value | renderer = x }) value.renderer )
        , ( "stats", \() -> ModelTree.maybe tree_DebugInfo_Types_SystemStats (\x -> put { value | stats = x }) value.stats )
        , ( "lastFrame", \() -> ModelTree.maybe ModelTree.float (\x -> put { value | lastFrame = x }) value.lastFrame )
        , ( "frameIntervals", \() -> ModelTree.list ModelTree.float (\x -> put { value | frameIntervals = x }) value.frameIntervals )
        , ( "frames", \() -> ModelTree.int (\x -> put { value | frames = x }) value.frames )
        , ( "lazyCache", \() -> ModelTree.opaqueTree "Ui.LazyCache (not saved)" (\x -> put { value | lazyCache = x }) value.lazyCache )
        , ( "imageCache", \() -> ModelTree.opaqueTree "ImageCache.ImageCache (not saved)" (\x -> put { value | imageCache = x }) value.imageCache )
        , ( "shift", \() -> ModelTree.bool (\x -> put { value | shift = x }) value.shift )
        , ( "ctrl", \() -> ModelTree.bool (\x -> put { value | ctrl = x }) value.ctrl )
        , ( "alt", \() -> ModelTree.bool (\x -> put { value | alt = x }) value.alt )
        , ( "clipboard", \() -> ModelTree.string (\x -> put { value | clipboard = x }) value.clipboard )
        , ( "selectingText", \() -> ModelTree.bool (\x -> put { value | selectingText = x }) value.selectingText )
        , ( "network", \() -> tree_Network_Network (\x -> put { value | network = x }) value.network )
        , ( "weather", \() -> tree_Weather_WeatherState (\x -> put { value | weather = x }) value.weather )
        , ( "lastSnapshot", \() -> ModelTree.maybe (\put1 value1 -> ModelTree.record [ ( "bytes", \() -> ModelTree.int (\x1 -> put1 { value1 | bytes = x1 }) value1.bytes ), ( "time", \() -> ModelTree.maybe ModelTree.posix (\x1 -> put1 { value1 | time = x1 }) value1.time ) ]) (\x -> put { value | lastSnapshot = x }) value.lastSnapshot )
        , ( "time", \() -> ModelTree.maybe ModelTree.posix (\x -> put { value | time = x }) value.time )
        , ( "utcOffsetMinutes", \() -> ModelTree.maybe ModelTree.int (\x -> put { value | utcOffsetMinutes = x }) value.utcOffsetMinutes )
        , ( "geoUrl", \() -> ModelTree.string (\x -> put { value | geoUrl = x }) value.geoUrl )
        , ( "weatherUrl", \() -> ModelTree.string (\x -> put { value | weatherUrl = x }) value.weatherUrl )
        , ( "system", \() -> ModelTree.maybe tree_About_Types_SystemInfo (\x -> put { value | system = x }) value.system )
        , ( "bootInfo", \() -> tree_BootInfo_Model (\x -> put { value | bootInfo = x }) value.bootInfo )
        , ( "aboutOpen", \() -> ModelTree.bool (\x -> put { value | aboutOpen = x }) value.aboutOpen )
        , ( "newsOpen", \() -> ModelTree.bool (\x -> put { value | newsOpen = x }) value.newsOpen )
        , ( "news", \() -> tree_News_Types_NewsState (\x -> put { value | news = x }) value.news )
        , ( "hackerNews", \() -> tree_HackerNews_Model (\x -> put { value | hackerNews = x }) value.hackerNews )
        , ( "email", \() -> tree_Email_Model (\x -> put { value | email = x }) value.email )
        , ( "webViewer", \() -> tree_WebViewer_Model (\x -> put { value | webViewer = x }) value.webViewer )
        , ( "asciiCollab", \() -> tree_AsciiCollab_Model (\x -> put { value | asciiCollab = x }) value.asciiCollab )
        , ( "calculator", \() -> tree_Calculator_Model (\x -> put { value | calculator = x }) value.calculator )
        , ( "calculatorOpen", \() -> ModelTree.bool (\x -> put { value | calculatorOpen = x }) value.calculatorOpen )
        , ( "ticTacToe", \() -> tree_TicTacToe_Model (\x -> put { value | ticTacToe = x }) value.ticTacToe )
        , ( "ticTacToeOpen", \() -> ModelTree.bool (\x -> put { value | ticTacToeOpen = x }) value.ticTacToeOpen )
        , ( "paint", \() -> tree_Paint_Model (\x -> put { value | paint = x }) value.paint )
        , ( "confirmPower", \() -> ModelTree.maybe (ModelTree.opaqueTree "Main.PowerAction") (\x -> put { value | confirmPower = x }) value.confirmPower )
        , ( "editorOpen", \() -> ModelTree.bool (\x -> put { value | editorOpen = x }) value.editorOpen )
        , ( "code", \() -> tree_Code_Model (\x -> put { value | code = x }) value.code )
        , ( "debugOpen", \() -> ModelTree.bool (\x -> put { value | debugOpen = x }) value.debugOpen )
        , ( "networkOpen", \() -> ModelTree.bool (\x -> put { value | networkOpen = x }) value.networkOpen )
        , ( "weatherOpen", \() -> ModelTree.bool (\x -> put { value | weatherOpen = x }) value.weatherOpen )
        , ( "upgradingTo", \() -> ModelTree.maybe ModelTree.string (\x -> put { value | upgradingTo = x }) value.upgradingTo )
        , ( "reflashNeeded", \() -> ModelTree.maybe ModelTree.string (\x -> put { value | reflashNeeded = x }) value.reflashNeeded )
        , ( "uiState", \() -> tree_Ui_Model tree_UiId_UiId (\x -> put { value | uiState = x }) value.uiState )
        , ( "showUiBorders", \() -> ModelTree.bool (\x -> put { value | showUiBorders = x }) value.showUiBorders )
        , ( "inspected", \() -> ModelTree.maybe (\put1 value1 -> ModelTree.record [ ( "display", \() -> ModelTree.int (\x1 -> put1 { value1 | display = x1 }) value1.display ), ( "sources", \() -> ModelTree.list tree_Ui_Source (\x1 -> put1 { value1 | sources = x1 }) value1.sources ) ]) (\x -> put { value | inspected = x }) value.inspected )
        , ( "screenshotViewer", \() -> tree_ScreenshotViewer_Model (\x -> put { value | screenshotViewer = x }) value.screenshotViewer )
        , ( "install", \() -> tree_Install_Model (\x -> put { value | install = x }) value.install )
        , ( "history", \() -> tree_History_Model (\x -> put { value | history = x }) value.history )
        , ( "modelViewer", \() -> tree_ModelViewer_Model (\x -> put { value | modelViewer = x }) value.modelViewer )
        , ( "takingScreenshot", \() -> ModelTree.maybe tree_Main_ScreenshotPreview (\x -> put { value | takingScreenshot = x }) value.takingScreenshot )
        , ( "screenshots", \() -> ModelTree.list tree_Ui_Screenshot (\x -> put { value | screenshots = x }) value.screenshots )
        , ( "testFacts", \() -> ModelTree.maybe (ModelTree.list (ModelTree.tuple2 ModelTree.string ModelTree.string)) (\x -> put { value | testFacts = x }) value.testFacts )
        ]


tree_Main_ScreenshotPreview put value =
    ModelTree.record
        [ ( "mouse", \() -> tree_Coord_Coord (\x -> put { value | mouse = x }) value.mouse )
        , ( "bounds", \() -> tree_Bounds_Bounds (\x -> put { value | bounds = x }) value.bounds )
        , ( "depth", \() -> ModelTree.int (\x -> put { value | depth = x }) value.depth )
        ]


tree_ModelViewer_Model put value =
    ModelTree.record
        [ ( "isOpen", \() -> ModelTree.bool (\x -> put { value | isOpen = x }) value.isOpen )
        , ( "expanded", \() -> ModelTree.set (ModelTree.list ModelTree.int) (\x -> put { value | expanded = x }) value.expanded )
        , ( "editing", \() -> ModelTree.maybe (\put1 value1 -> ModelTree.record [ ( "path", \() -> ModelTree.list ModelTree.int (\x1 -> put1 { value1 | path = x1 }) value1.path ), ( "refused", \() -> ModelTree.bool (\x1 -> put1 { value1 | refused = x1 }) value1.refused ) ]) (\x -> put { value | editing = x }) value.editing )
        ]


tree_ModelViewer_Types_UiId put value =
    case value of
        ModelViewer.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_ModelViewer_Types_UiId put)

        ModelViewer.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_ModelViewer_Types_UiId put)

        ModelViewer.Types.ListViewport ->
            ModelTree.variant "ListViewport" [] (choices_ModelViewer_Types_UiId put)

        ModelViewer.Types.Row a0 ->
            ModelTree.variant "Row" [ \() -> ModelTree.list ModelTree.int (\new -> put (ModelViewer.Types.Row new)) a0 ] (choices_ModelViewer_Types_UiId put)

        ModelViewer.Types.Choice a0 a1 ->
            ModelTree.variant "Choice" [ \() -> ModelTree.list ModelTree.int (\new -> put (ModelViewer.Types.Choice new a1)) a0, \() -> ModelTree.int (\new -> put (ModelViewer.Types.Choice a0 new)) a1 ] (choices_ModelViewer_Types_UiId put)

        ModelViewer.Types.EditInput ->
            ModelTree.variant "EditInput" [] (choices_ModelViewer_Types_UiId put)

        ModelViewer.Types.SaveButton ->
            ModelTree.variant "SaveButton" [] (choices_ModelViewer_Types_UiId put)

        ModelViewer.Types.CancelButton ->
            ModelTree.variant "CancelButton" [] (choices_ModelViewer_Types_UiId put)


choices_ModelViewer_Types_UiId put =
    [ ( "OpenButton", \() -> put ModelViewer.Types.OpenButton )
    , ( "CloseButton", \() -> put ModelViewer.Types.CloseButton )
    , ( "ListViewport", \() -> put ModelViewer.Types.ListViewport )
    , ( "EditInput", \() -> put ModelViewer.Types.EditInput )
    , ( "SaveButton", \() -> put ModelViewer.Types.SaveButton )
    , ( "CancelButton", \() -> put ModelViewer.Types.CancelButton )
    ]


tree_Network_Network put value =
    ModelTree.record
        [ ( "wifiDevice", \() -> tree_Network_WifiDevice (\x -> put { value | wifiDevice = x }) value.wifiDevice )
        , ( "networks", \() -> ModelTree.list tree_Network_WifiNetwork (\x -> put { value | networks = x }) value.networks )
        , ( "scanning", \() -> ModelTree.bool (\x -> put { value | scanning = x }) value.scanning )
        , ( "wifiStatus", \() -> tree_Network_WifiStatus (\x -> put { value | wifiStatus = x }) value.wifiStatus )
        , ( "wired", \() -> ModelTree.list tree_Network_WiredLink (\x -> put { value | wired = x }) value.wired )
        , ( "selected", \() -> ModelTree.maybe tree_Network_WifiNetwork (\x -> put { value | selected = x }) value.selected )
        , ( "savedWifiPasswords", \() -> ModelTree.seqDict (ModelTree.opaqueTree "Network.Types.Ssid") (ModelTree.opaqueTree "Network.Wpa2Password.Wpa2Password") (\x -> put { value | savedWifiPasswords = x }) value.savedWifiPasswords )
        , ( "showPassword", \() -> ModelTree.bool (\x -> put { value | showPassword = x }) value.showPassword )
        ]


tree_Network_WifiDevice put value =
    case value of
        Network.Unknown ->
            ModelTree.variant "Unknown" [] (choices_Network_WifiDevice put)

        Network.NoCard ->
            ModelTree.variant "NoCard" [] (choices_Network_WifiDevice put)

        Network.Card a0 ->
            ModelTree.variant "Card" [ \() -> ModelTree.string (\new -> put (Network.Card new)) a0 ] (choices_Network_WifiDevice put)


choices_Network_WifiDevice put =
    [ ( "Unknown", \() -> put Network.Unknown )
    , ( "NoCard", \() -> put Network.NoCard )
    ]


tree_Network_WifiNetwork put value =
    ModelTree.record
        [ ( "ssid", \() -> ModelTree.opaqueTree "Network.Types.Ssid" (\x -> put { value | ssid = x }) value.ssid )
        , ( "signal", \() -> ModelTree.int (\x -> put { value | signal = x }) value.signal )
        , ( "security", \() -> tree_Network_WifiSecurity (\x -> put { value | security = x }) value.security )
        ]


tree_Network_WifiSecurity put value =
    case value of
        Network.Open ->
            ModelTree.variant "Open" [] (choices_Network_WifiSecurity put)

        Network.Wpa ->
            ModelTree.variant "Wpa" [] (choices_Network_WifiSecurity put)

        Network.Enterprise ->
            ModelTree.variant "Enterprise" [] (choices_Network_WifiSecurity put)

        Network.Wep ->
            ModelTree.variant "Wep" [] (choices_Network_WifiSecurity put)

        Network.Wpa3 ->
            ModelTree.variant "Wpa3" [] (choices_Network_WifiSecurity put)


choices_Network_WifiSecurity put =
    [ ( "Open", \() -> put Network.Open )
    , ( "Wpa", \() -> put Network.Wpa )
    , ( "Enterprise", \() -> put Network.Enterprise )
    , ( "Wep", \() -> put Network.Wep )
    , ( "Wpa3", \() -> put Network.Wpa3 )
    ]


tree_Network_WifiState put value =
    case value of
        Network.Idle ->
            ModelTree.variant "Idle" [] (choices_Network_WifiState put)

        Network.Connecting ->
            ModelTree.variant "Connecting" [] (choices_Network_WifiState put)

        Network.Dhcp ->
            ModelTree.variant "Dhcp" [] (choices_Network_WifiState put)

        Network.Connected ->
            ModelTree.variant "Connected" [] (choices_Network_WifiState put)

        Network.Failed ->
            ModelTree.variant "Failed" [] (choices_Network_WifiState put)


choices_Network_WifiState put =
    [ ( "Idle", \() -> put Network.Idle )
    , ( "Connecting", \() -> put Network.Connecting )
    , ( "Dhcp", \() -> put Network.Dhcp )
    , ( "Connected", \() -> put Network.Connected )
    , ( "Failed", \() -> put Network.Failed )
    ]


tree_Network_WifiStatus put value =
    ModelTree.record
        [ ( "state", \() -> tree_Network_WifiState (\x -> put { value | state = x }) value.state )
        , ( "ssid", \() -> ModelTree.opaqueTree "Network.Types.Ssid" (\x -> put { value | ssid = x }) value.ssid )
        , ( "ip", \() -> ModelTree.maybe (ModelTree.opaqueTree "Network.Ipv4.Ipv4") (\x -> put { value | ip = x }) value.ip )
        , ( "error", \() -> ModelTree.string (\x -> put { value | error = x }) value.error )
        ]


tree_Network_WiredLink put value =
    ModelTree.record
        [ ( "name", \() -> ModelTree.string (\x -> put { value | name = x }) value.name )
        , ( "state", \() -> tree_Network_WiredState (\x -> put { value | state = x }) value.state )
        , ( "ip", \() -> ModelTree.maybe (ModelTree.opaqueTree "Network.Ipv4.Ipv4") (\x -> put { value | ip = x }) value.ip )
        ]


tree_Network_WiredState put value =
    case value of
        Network.WiredNoCable ->
            ModelTree.variant "WiredNoCable" [] (choices_Network_WiredState put)

        Network.WiredDhcp ->
            ModelTree.variant "WiredDhcp" [] (choices_Network_WiredState put)

        Network.WiredConnected ->
            ModelTree.variant "WiredConnected" [] (choices_Network_WiredState put)

        Network.WiredFailed ->
            ModelTree.variant "WiredFailed" [] (choices_Network_WiredState put)


choices_Network_WiredState put =
    [ ( "WiredNoCable", \() -> put Network.WiredNoCable )
    , ( "WiredDhcp", \() -> put Network.WiredDhcp )
    , ( "WiredConnected", \() -> put Network.WiredConnected )
    , ( "WiredFailed", \() -> put Network.WiredFailed )
    ]


tree_Network_Types_UiId put value =
    case value of
        Network.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_Network_Types_UiId put)

        Network.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_Network_Types_UiId put)

        Network.Types.RefreshButton ->
            ModelTree.variant "RefreshButton" [] (choices_Network_Types_UiId put)

        Network.Types.NetworkButton a0 ->
            ModelTree.variant "NetworkButton" [ \() -> ModelTree.opaqueTree "Network.Types.Ssid" (\new -> put (Network.Types.NetworkButton new)) a0 ] (choices_Network_Types_UiId put)

        Network.Types.PasswordInput ->
            ModelTree.variant "PasswordInput" [] (choices_Network_Types_UiId put)

        Network.Types.ShowPasswordButton ->
            ModelTree.variant "ShowPasswordButton" [] (choices_Network_Types_UiId put)

        Network.Types.ConnectButton ->
            ModelTree.variant "ConnectButton" [] (choices_Network_Types_UiId put)

        Network.Types.DisconnectButton ->
            ModelTree.variant "DisconnectButton" [] (choices_Network_Types_UiId put)

        Network.Types.NetworkListViewport ->
            ModelTree.variant "NetworkListViewport" [] (choices_Network_Types_UiId put)


choices_Network_Types_UiId put =
    [ ( "OpenButton", \() -> put Network.Types.OpenButton )
    , ( "CloseButton", \() -> put Network.Types.CloseButton )
    , ( "RefreshButton", \() -> put Network.Types.RefreshButton )
    , ( "PasswordInput", \() -> put Network.Types.PasswordInput )
    , ( "ShowPasswordButton", \() -> put Network.Types.ShowPasswordButton )
    , ( "ConnectButton", \() -> put Network.Types.ConnectButton )
    , ( "DisconnectButton", \() -> put Network.Types.DisconnectButton )
    , ( "NetworkListViewport", \() -> put Network.Types.NetworkListViewport )
    ]


tree_News_Types_Day put value =
    ModelTree.record
        [ ( "date", \() -> ModelTree.date (\x -> put { value | date = x }) value.date )
        , ( "topics", \() -> ModelTree.list tree_News_Types_Topic (\x -> put { value | topics = x }) value.topics )
        ]


tree_News_Types_Emphasis put value =
    case value of
        News.Types.ToggleItalic ->
            ModelTree.variant "ToggleItalic" [] (choices_News_Types_Emphasis put)

        News.Types.ToggleBold ->
            ModelTree.variant "ToggleBold" [] (choices_News_Types_Emphasis put)

        News.Types.ToggleBoldItalic ->
            ModelTree.variant "ToggleBoldItalic" [] (choices_News_Types_Emphasis put)


choices_News_Types_Emphasis put =
    [ ( "ToggleItalic", \() -> put News.Types.ToggleItalic )
    , ( "ToggleBold", \() -> put News.Types.ToggleBold )
    , ( "ToggleBoldItalic", \() -> put News.Types.ToggleBoldItalic )
    ]


tree_News_Types_Inline put value =
    case value of
        News.Types.Text a0 ->
            ModelTree.variant "Text" [ \() -> ModelTree.string (\new -> put (News.Types.Text new)) a0 ] []

        News.Types.WikiLink a0 ->
            ModelTree.variant "WikiLink" [ \() -> (\put1 value1 -> ModelTree.record [ ( "article", \() -> ModelTree.string (\x1 -> put1 { value1 | article = x1 }) value1.article ), ( "label", \() -> ModelTree.string (\x1 -> put1 { value1 | label = x1 }) value1.label ) ]) (\new -> put (News.Types.WikiLink new)) a0 ] []

        News.Types.ExternalLink a0 ->
            ModelTree.variant "ExternalLink" [ \() -> (\put1 value1 -> ModelTree.record [ ( "url", \() -> ModelTree.string (\x1 -> put1 { value1 | url = x1 }) value1.url ), ( "label", \() -> ModelTree.string (\x1 -> put1 { value1 | label = x1 }) value1.label ) ]) (\new -> put (News.Types.ExternalLink new)) a0 ] []

        News.Types.Toggle a0 ->
            ModelTree.variant "Toggle" [ \() -> tree_News_Types_Emphasis (\new -> put (News.Types.Toggle new)) a0 ] []


tree_News_Types_Item put value =
    case value of
        News.Types.Item a0 ->
            ModelTree.variant "Item" [ \() -> (\put1 value1 -> ModelTree.record [ ( "content", \() -> ModelTree.list tree_News_Types_Inline (\x1 -> put1 { value1 | content = x1 }) value1.content ), ( "children", \() -> ModelTree.list tree_News_Types_Item (\x1 -> put1 { value1 | children = x1 }) value1.children ) ]) (\new -> put (News.Types.Item new)) a0 ] []


tree_News_Types_NewsState put value =
    case value of
        News.Types.NewsNotRequested ->
            ModelTree.variant "NewsNotRequested" [] (choices_News_Types_NewsState put)

        News.Types.LoadingNews a0 ->
            ModelTree.variant "LoadingNews" [ \() -> ModelTree.maybe (ModelTree.list tree_News_Types_Day) (\new -> put (News.Types.LoadingNews new)) a0 ] (choices_News_Types_NewsState put)

        News.Types.LoadedNews a0 ->
            ModelTree.variant "LoadedNews" [ \() -> ModelTree.list tree_News_Types_Day (\new -> put (News.Types.LoadedNews new)) a0 ] (choices_News_Types_NewsState put)

        News.Types.NewsFailed a0 ->
            ModelTree.variant "NewsFailed" [ \() -> tree_Effect_HttpError (\new -> put (News.Types.NewsFailed new)) a0 ] (choices_News_Types_NewsState put)


choices_News_Types_NewsState put =
    [ ( "NewsNotRequested", \() -> put News.Types.NewsNotRequested )
    ]


tree_News_Types_Topic put value =
    ModelTree.record
        [ ( "heading", \() -> ModelTree.string (\x -> put { value | heading = x }) value.heading )
        , ( "items", \() -> ModelTree.list tree_News_Types_Item (\x -> put { value | items = x }) value.items )
        ]


tree_News_Types_UiId put value =
    case value of
        News.Types.Viewport ->
            ModelTree.variant "Viewport" [] (choices_News_Types_UiId put)


choices_News_Types_UiId put =
    [ ( "Viewport", \() -> put News.Types.Viewport )
    ]


tree_Paint_Model put value =
    ModelTree.record
        [ ( "isOpen", \() -> ModelTree.bool (\x -> put { value | isOpen = x }) value.isOpen )
        , ( "canvas", \() -> tree_Image_Image (\x -> put { value | canvas = x }) value.canvas )
        , ( "color", \() -> ModelTree.opaqueTree "Color.Color" (\x -> put { value | color = x }) value.color )
        , ( "brush", \() -> ModelTree.int (\x -> put { value | brush = x }) value.brush )
        , ( "tool", \() -> tree_Paint_Types_Tool (\x -> put { value | tool = x }) value.tool )
        , ( "undoable", \() -> ModelTree.list tree_Image_Image (\x -> put { value | undoable = x }) value.undoable )
        , ( "redoable", \() -> ModelTree.list tree_Image_Image (\x -> put { value | redoable = x }) value.redoable )
        , ( "stroke", \() -> ModelTree.maybe tree_Paint_Stroke (\x -> put { value | stroke = x }) value.stroke )
        , ( "zoom", \() -> ModelTree.float (\x -> put { value | zoom = x }) value.zoom )
        , ( "offset", \() -> ModelTree.tuple2 ModelTree.float ModelTree.float (\x -> put { value | offset = x }) value.offset )
        , ( "panning", \() -> ModelTree.bool (\x -> put { value | panning = x }) value.panning )
        ]


tree_Paint_Stroke put value =
    ModelTree.record
        [ ( "at", \() -> ModelTree.tuple2 ModelTree.int ModelTree.int (\x -> put { value | at = x }) value.at )
        , ( "exact", \() -> ModelTree.tuple2 ModelTree.float ModelTree.float (\x -> put { value | exact = x }) value.exact )
        , ( "target", \() -> ModelTree.int (\x -> put { value | target = x }) value.target )
        , ( "filled", \() -> ModelTree.set ModelTree.int (\x -> put { value | filled = x }) value.filled )
        ]


tree_Paint_Types_Tool put value =
    case value of
        Paint.Types.Pen ->
            ModelTree.variant "Pen" [] (choices_Paint_Types_Tool put)

        Paint.Types.Fill ->
            ModelTree.variant "Fill" [] (choices_Paint_Types_Tool put)


choices_Paint_Types_Tool put =
    [ ( "Pen", \() -> put Paint.Types.Pen )
    , ( "Fill", \() -> put Paint.Types.Fill )
    ]


tree_Paint_Types_UiId put value =
    case value of
        Paint.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_Paint_Types_UiId put)

        Paint.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_Paint_Types_UiId put)

        Paint.Types.ClearButton ->
            ModelTree.variant "ClearButton" [] (choices_Paint_Types_UiId put)

        Paint.Types.UndoButton ->
            ModelTree.variant "UndoButton" [] (choices_Paint_Types_UiId put)

        Paint.Types.RedoButton ->
            ModelTree.variant "RedoButton" [] (choices_Paint_Types_UiId put)

        Paint.Types.Canvas ->
            ModelTree.variant "Canvas" [] (choices_Paint_Types_UiId put)

        Paint.Types.ColorButton a0 ->
            ModelTree.variant "ColorButton" [ \() -> ModelTree.int (\new -> put (Paint.Types.ColorButton new)) a0 ] (choices_Paint_Types_UiId put)

        Paint.Types.BrushButton a0 ->
            ModelTree.variant "BrushButton" [ \() -> ModelTree.int (\new -> put (Paint.Types.BrushButton new)) a0 ] (choices_Paint_Types_UiId put)

        Paint.Types.ToolButton a0 ->
            ModelTree.variant "ToolButton" [ \() -> tree_Paint_Types_Tool (\new -> put (Paint.Types.ToolButton new)) a0 ] (choices_Paint_Types_UiId put)


choices_Paint_Types_UiId put =
    [ ( "OpenButton", \() -> put Paint.Types.OpenButton )
    , ( "CloseButton", \() -> put Paint.Types.CloseButton )
    , ( "ClearButton", \() -> put Paint.Types.ClearButton )
    , ( "UndoButton", \() -> put Paint.Types.UndoButton )
    , ( "RedoButton", \() -> put Paint.Types.RedoButton )
    , ( "Canvas", \() -> put Paint.Types.Canvas )
    ]


tree_ScreenshotViewer_Model put value =
    ModelTree.record
        [ ( "isOpen", \() -> ModelTree.bool (\x -> put { value | isOpen = x }) value.isOpen )
        , ( "selected", \() -> ModelTree.maybe ModelTree.int (\x -> put { value | selected = x }) value.selected )
        , ( "zoom", \() -> ModelTree.float (\x -> put { value | zoom = x }) value.zoom )
        , ( "offset", \() -> ModelTree.tuple2 ModelTree.float ModelTree.float (\x -> put { value | offset = x }) value.offset )
        , ( "dragging", \() -> ModelTree.bool (\x -> put { value | dragging = x }) value.dragging )
        ]


tree_ScreenshotViewer_Types_UiId put value =
    case value of
        ScreenshotViewer.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.PreviewList ->
            ModelTree.variant "PreviewList" [] (choices_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.Preview a0 ->
            ModelTree.variant "Preview" [ \() -> ModelTree.int (\new -> put (ScreenshotViewer.Types.Preview new)) a0 ] (choices_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.ImageArea ->
            ModelTree.variant "ImageArea" [] (choices_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.ZoomInButton ->
            ModelTree.variant "ZoomInButton" [] (choices_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.ZoomOutButton ->
            ModelTree.variant "ZoomOutButton" [] (choices_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.ActualSizeButton ->
            ModelTree.variant "ActualSizeButton" [] (choices_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.FitButton ->
            ModelTree.variant "FitButton" [] (choices_ScreenshotViewer_Types_UiId put)


choices_ScreenshotViewer_Types_UiId put =
    [ ( "OpenButton", \() -> put ScreenshotViewer.Types.OpenButton )
    , ( "CloseButton", \() -> put ScreenshotViewer.Types.CloseButton )
    , ( "PreviewList", \() -> put ScreenshotViewer.Types.PreviewList )
    , ( "ImageArea", \() -> put ScreenshotViewer.Types.ImageArea )
    , ( "ZoomInButton", \() -> put ScreenshotViewer.Types.ZoomInButton )
    , ( "ZoomOutButton", \() -> put ScreenshotViewer.Types.ZoomOutButton )
    , ( "ActualSizeButton", \() -> put ScreenshotViewer.Types.ActualSizeButton )
    , ( "FitButton", \() -> put ScreenshotViewer.Types.FitButton )
    ]


tree_TextInput_Click put value =
    ModelTree.record
        [ ( "time", \() -> ModelTree.posix (\x -> put { value | time = x }) value.time )
        , ( "clicks", \() -> ModelTree.int (\x -> put { value | clicks = x }) value.clicks )
        , ( "index", \() -> ModelTree.int (\x -> put { value | index = x }) value.index )
        ]


tree_TextInput_Model put value =
    ModelTree.record
        [ ( "current", \() -> tree_TextInput_State (\x -> put { value | current = x }) value.current )
        , ( "undoHistory", \() -> ModelTree.list tree_TextInput_State (\x -> put { value | undoHistory = x }) value.undoHistory )
        , ( "redoHistory", \() -> ModelTree.list tree_TextInput_State (\x -> put { value | redoHistory = x }) value.redoHistory )
        , ( "lastClick", \() -> ModelTree.maybe tree_TextInput_Click (\x -> put { value | lastClick = x }) value.lastClick )
        ]


tree_TextInput_State put value =
    ModelTree.record
        [ ( "cursorPosition", \() -> ModelTree.int (\x -> put { value | cursorPosition = x }) value.cursorPosition )
        , ( "cursorSize", \() -> ModelTree.int (\x -> put { value | cursorSize = x }) value.cursorSize )
        , ( "text", \() -> ModelTree.string (\x -> put { value | text = x }) value.text )
        ]


tree_TextInputMultiline_Glide put value =
    case value of
        TextInputMultiline.Still ->
            ModelTree.variant "Still" [] (choices_TextInputMultiline_Glide put)

        TextInputMultiline.Fingers a0 ->
            ModelTree.variant "Fingers" [ \() -> ModelTree.float (\new -> put (TextInputMultiline.Fingers new)) a0 ] (choices_TextInputMultiline_Glide put)

        TextInputMultiline.Easing a0 ->
            ModelTree.variant "Easing" [ \() -> ModelTree.float (\new -> put (TextInputMultiline.Easing new)) a0 ] (choices_TextInputMultiline_Glide put)


choices_TextInputMultiline_Glide put =
    [ ( "Still", \() -> put TextInputMultiline.Still )
    ]


tree_TextInputMultiline_Model put value =
    ModelTree.record
        [ ( "input", \() -> tree_TextInput_Model (\x -> put { value | input = x }) value.input )
        , ( "scroll", \() -> ModelTree.int (\x -> put { value | scroll = x }) value.scroll )
        , ( "position", \() -> ModelTree.float (\x -> put { value | position = x }) value.position )
        , ( "glide", \() -> tree_TextInputMultiline_Glide (\x -> put { value | glide = x }) value.glide )
        , ( "goalX", \() -> ModelTree.maybe ModelTree.int (\x -> put { value | goalX = x }) value.goalX )
        , ( "grab", \() -> ModelTree.maybe ModelTree.int (\x -> put { value | grab = x }) value.grab )
        , ( "scrollbarShown", \() -> ModelTree.float (\x -> put { value | scrollbarShown = x }) value.scrollbarShown )
        , ( "scrollbarWidened", \() -> ModelTree.float (\x -> put { value | scrollbarWidened = x }) value.scrollbarWidened )
        ]


tree_TicTacToe_Mark put value =
    case value of
        TicTacToe.X ->
            ModelTree.variant "X" [] (choices_TicTacToe_Mark put)

        TicTacToe.O ->
            ModelTree.variant "O" [] (choices_TicTacToe_Mark put)


choices_TicTacToe_Mark put =
    [ ( "X", \() -> put TicTacToe.X )
    , ( "O", \() -> put TicTacToe.O )
    ]


tree_TicTacToe_Model put value =
    ModelTree.record
        [ ( "squares", \() -> ModelTree.list (ModelTree.maybe tree_TicTacToe_Mark) (\x -> put { value | squares = x }) value.squares )
        , ( "next", \() -> tree_TicTacToe_Mark (\x -> put { value | next = x }) value.next )
        ]


tree_TicTacToe_Types_UiId put value =
    case value of
        TicTacToe.Types.Square a0 ->
            ModelTree.variant "Square" [ \() -> ModelTree.int (\new -> put (TicTacToe.Types.Square new)) a0 ] (choices_TicTacToe_Types_UiId put)

        TicTacToe.Types.NewGameButton ->
            ModelTree.variant "NewGameButton" [] (choices_TicTacToe_Types_UiId put)

        TicTacToe.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_TicTacToe_Types_UiId put)

        TicTacToe.Types.Panel ->
            ModelTree.variant "Panel" [] (choices_TicTacToe_Types_UiId put)


choices_TicTacToe_Types_UiId put =
    [ ( "NewGameButton", \() -> put TicTacToe.Types.NewGameButton )
    , ( "CloseButton", \() -> put TicTacToe.Types.CloseButton )
    , ( "Panel", \() -> put TicTacToe.Types.Panel )
    ]


tree_Ui_ElementState put value =
    case value of
        Ui.TextInputState a0 ->
            ModelTree.variant "TextInputState" [ \() -> tree_TextInput_Model (\new -> put (Ui.TextInputState new)) a0 ] []

        Ui.TextInputMultilineState a0 ->
            ModelTree.variant "TextInputMultilineState" [ \() -> tree_TextInputMultiline_Model (\new -> put (Ui.TextInputMultilineState new)) a0 ] []

        Ui.ViewportState a0 ->
            ModelTree.variant "ViewportState" [ \() -> tree_Ui_ViewportModel (\new -> put (Ui.ViewportState new)) a0 ] []

        Ui.ButtonState a0 ->
            ModelTree.variant "ButtonState" [ \() -> tree_Button_Model (\new -> put (Ui.ButtonState new)) a0 ] []


tree_Ui_Model tree_id put value =
    ModelTree.record
        [ ( "focus", \() -> ModelTree.maybe tree_id (\x -> put { value | focus = x }) value.focus )
        , ( "uiState", \() -> ModelTree.seqDict tree_id tree_Ui_ElementState (\x -> put { value | uiState = x }) value.uiState )
        , ( "mouseStill", \() -> (\put1 value1 -> ModelTree.record [ ( "at", \() -> tree_Coord_Coord (\x1 -> put1 { value1 | at = x1 }) value1.at ), ( "seconds", \() -> ModelTree.quantity ModelTree.float (\x1 -> put1 { value1 | seconds = x1 }) value1.seconds ) ]) (\x -> put { value | mouseStill = x }) value.mouseStill )
        ]


tree_Ui_Screenshot put value =
    ModelTree.record
        [ ( "time", \() -> ModelTree.posix (\x -> put { value | time = x }) value.time )
        , ( "uiState", \() -> tree_Ui_Model ModelTree.int (\x -> put { value | uiState = x }) value.uiState )
        , ( "uiScale", \() -> tree_Units_UiScale (\x -> put { value | uiScale = x }) value.uiScale )
        , ( "screenshot", \() -> ModelTree.opaqueTree "Ui.ElementFull" (\x -> put { value | screenshot = x }) value.screenshot )
        ]


tree_Ui_Source put value =
    ModelTree.record
        [ ( "module_", \() -> ModelTree.string (\x -> put { value | module_ = x }) value.module_ )
        , ( "line", \() -> ModelTree.int (\x -> put { value | line = x }) value.line )
        , ( "function", \() -> ModelTree.string (\x -> put { value | function = x }) value.function )
        ]


tree_Ui_ViewportModel put value =
    ModelTree.record
        [ ( "offset", \() -> ModelTree.quantity ModelTree.float (\x -> put { value | offset = x }) value.offset )
        , ( "target", \() -> ModelTree.quantity ModelTree.float (\x -> put { value | target = x }) value.target )
        , ( "momentum", \() -> ModelTree.float (\x -> put { value | momentum = x }) value.momentum )
        , ( "bottom", \() -> ModelTree.quantity ModelTree.float (\x -> put { value | bottom = x }) value.bottom )
        , ( "grab", \() -> ModelTree.maybe ModelTree.int (\x -> put { value | grab = x }) value.grab )
        , ( "scrollbarShown", \() -> ModelTree.float (\x -> put { value | scrollbarShown = x }) value.scrollbarShown )
        , ( "scrollbarWidened", \() -> ModelTree.float (\x -> put { value | scrollbarWidened = x }) value.scrollbarWidened )
        ]


tree_UiId_UiId put value =
    case value of
        UiId.About a0 ->
            ModelTree.variant "About" [ \() -> tree_About_Types_UiId (\new -> put (UiId.About new)) a0 ] (choices_UiId_UiId put)

        UiId.DebugInfo a0 ->
            ModelTree.variant "DebugInfo" [ \() -> tree_DebugInfo_Types_UiId (\new -> put (UiId.DebugInfo new)) a0 ] (choices_UiId_UiId put)

        UiId.Editor a0 ->
            ModelTree.variant "Editor" [ \() -> tree_Editor_Types_UiId (\new -> put (UiId.Editor new)) a0 ] (choices_UiId_UiId put)

        UiId.Weather a0 ->
            ModelTree.variant "Weather" [ \() -> tree_Weather_Types_UiId (\new -> put (UiId.Weather new)) a0 ] (choices_UiId_UiId put)

        UiId.NewsButton ->
            ModelTree.variant "NewsButton" [] (choices_UiId_UiId put)

        UiId.CalculatorButton ->
            ModelTree.variant "CalculatorButton" [] (choices_UiId_UiId put)

        UiId.TicTacToeButton ->
            ModelTree.variant "TicTacToeButton" [] (choices_UiId_UiId put)

        UiId.PowerOffButton ->
            ModelTree.variant "PowerOffButton" [] (choices_UiId_UiId put)

        UiId.RestartButton ->
            ModelTree.variant "RestartButton" [] (choices_UiId_UiId put)

        UiId.ConfirmPowerButton ->
            ModelTree.variant "ConfirmPowerButton" [] (choices_UiId_UiId put)

        UiId.CancelPowerButton ->
            ModelTree.variant "CancelPowerButton" [] (choices_UiId_UiId put)

        UiId.Network a0 ->
            ModelTree.variant "Network" [ \() -> tree_Network_Types_UiId (\new -> put (UiId.Network new)) a0 ] (choices_UiId_UiId put)

        UiId.Calculator a0 ->
            ModelTree.variant "Calculator" [ \() -> tree_Calculator_Types_UiId (\new -> put (UiId.Calculator new)) a0 ] (choices_UiId_UiId put)

        UiId.TicTacToe a0 ->
            ModelTree.variant "TicTacToe" [ \() -> tree_TicTacToe_Types_UiId (\new -> put (UiId.TicTacToe new)) a0 ] (choices_UiId_UiId put)

        UiId.Paint a0 ->
            ModelTree.variant "Paint" [ \() -> tree_Paint_Types_UiId (\new -> put (UiId.Paint new)) a0 ] (choices_UiId_UiId put)

        UiId.Code a0 ->
            ModelTree.variant "Code" [ \() -> tree_Code_Types_UiId (\new -> put (UiId.Code new)) a0 ] (choices_UiId_UiId put)

        UiId.News a0 ->
            ModelTree.variant "News" [ \() -> tree_News_Types_UiId (\new -> put (UiId.News new)) a0 ] (choices_UiId_UiId put)

        UiId.HackerNews a0 ->
            ModelTree.variant "HackerNews" [ \() -> tree_HackerNews_Types_UiId (\new -> put (UiId.HackerNews new)) a0 ] (choices_UiId_UiId put)

        UiId.AsciiCollab a0 ->
            ModelTree.variant "AsciiCollab" [ \() -> tree_AsciiCollab_Types_UiId (\new -> put (UiId.AsciiCollab new)) a0 ] (choices_UiId_UiId put)

        UiId.Email a0 ->
            ModelTree.variant "Email" [ \() -> tree_Email_Types_UiId (\new -> put (UiId.Email new)) a0 ] (choices_UiId_UiId put)

        UiId.WebViewer a0 ->
            ModelTree.variant "WebViewer" [ \() -> tree_WebViewer_Types_UiId (\new -> put (UiId.WebViewer new)) a0 ] (choices_UiId_UiId put)

        UiId.ScreenshotViewer a0 ->
            ModelTree.variant "ScreenshotViewer" [ \() -> tree_ScreenshotViewer_Types_UiId (\new -> put (UiId.ScreenshotViewer new)) a0 ] (choices_UiId_UiId put)

        UiId.Install a0 ->
            ModelTree.variant "Install" [ \() -> tree_Install_Types_UiId (\new -> put (UiId.Install new)) a0 ] (choices_UiId_UiId put)

        UiId.History a0 ->
            ModelTree.variant "History" [ \() -> tree_History_Types_UiId (\new -> put (UiId.History new)) a0 ] (choices_UiId_UiId put)

        UiId.ModelViewer a0 ->
            ModelTree.variant "ModelViewer" [ \() -> tree_ModelViewer_Types_UiId (\new -> put (UiId.ModelViewer new)) a0 ] (choices_UiId_UiId put)

        UiId.Lazy a0 ->
            ModelTree.variant "Lazy" [ \() -> ModelTree.opaqueTree "UiId.LazyKey (not saved)" (\new -> put (UiId.Lazy new)) a0 ] (choices_UiId_UiId put)


choices_UiId_UiId put =
    [ ( "NewsButton", \() -> put UiId.NewsButton )
    , ( "CalculatorButton", \() -> put UiId.CalculatorButton )
    , ( "TicTacToeButton", \() -> put UiId.TicTacToeButton )
    , ( "PowerOffButton", \() -> put UiId.PowerOffButton )
    , ( "RestartButton", \() -> put UiId.RestartButton )
    , ( "ConfirmPowerButton", \() -> put UiId.ConfirmPowerButton )
    , ( "CancelPowerButton", \() -> put UiId.CancelPowerButton )
    ]


tree_Units_UiScale put value =
    ModelTree.quantity ModelTree.int put value


tree_Weather_Day put value =
    ModelTree.record
        [ ( "date", \() -> ModelTree.string (\x -> put { value | date = x }) value.date )
        , ( "code", \() -> ModelTree.int (\x -> put { value | code = x }) value.code )
        , ( "high", \() -> ModelTree.float (\x -> put { value | high = x }) value.high )
        , ( "low", \() -> ModelTree.float (\x -> put { value | low = x }) value.low )
        ]


tree_Weather_Forecast put value =
    ModelTree.record
        [ ( "temperature", \() -> ModelTree.float (\x -> put { value | temperature = x }) value.temperature )
        , ( "humidity", \() -> ModelTree.float (\x -> put { value | humidity = x }) value.humidity )
        , ( "wind", \() -> ModelTree.float (\x -> put { value | wind = x }) value.wind )
        , ( "code", \() -> ModelTree.int (\x -> put { value | code = x }) value.code )
        , ( "time", \() -> ModelTree.string (\x -> put { value | time = x }) value.time )
        , ( "days", \() -> ModelTree.list tree_Weather_Day (\x -> put { value | days = x }) value.days )
        , ( "utcOffsetSeconds", \() -> ModelTree.maybe ModelTree.int (\x -> put { value | utcOffsetSeconds = x }) value.utcOffsetSeconds )
        ]


tree_Weather_Place put value =
    ModelTree.record
        [ ( "latitude", \() -> ModelTree.float (\x -> put { value | latitude = x }) value.latitude )
        , ( "longitude", \() -> ModelTree.float (\x -> put { value | longitude = x }) value.longitude )
        , ( "name", \() -> ModelTree.string (\x -> put { value | name = x }) value.name )
        ]


tree_Weather_WeatherState put value =
    case value of
        Weather.NoWeather ->
            ModelTree.variant "NoWeather" [] (choices_Weather_WeatherState put)

        Weather.FindingPlace ->
            ModelTree.variant "FindingPlace" [] (choices_Weather_WeatherState put)

        Weather.LoadingForecast a0 ->
            ModelTree.variant "LoadingForecast" [ \() -> tree_Weather_Place (\new -> put (Weather.LoadingForecast new)) a0 ] (choices_Weather_WeatherState put)

        Weather.GotWeather a0 a1 ->
            ModelTree.variant "GotWeather" [ \() -> tree_Weather_Place (\new -> put (Weather.GotWeather new a1)) a0, \() -> tree_Weather_Forecast (\new -> put (Weather.GotWeather a0 new)) a1 ] (choices_Weather_WeatherState put)

        Weather.WeatherFailed a0 ->
            ModelTree.variant "WeatherFailed" [ \() -> tree_Effect_HttpError (\new -> put (Weather.WeatherFailed new)) a0 ] (choices_Weather_WeatherState put)


choices_Weather_WeatherState put =
    [ ( "NoWeather", \() -> put Weather.NoWeather )
    , ( "FindingPlace", \() -> put Weather.FindingPlace )
    ]


tree_Weather_Types_UiId put value =
    case value of
        Weather.Types.RefreshButton ->
            ModelTree.variant "RefreshButton" [] (choices_Weather_Types_UiId put)

        Weather.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_Weather_Types_UiId put)

        Weather.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_Weather_Types_UiId put)


choices_Weather_Types_UiId put =
    [ ( "RefreshButton", \() -> put Weather.Types.RefreshButton )
    , ( "OpenButton", \() -> put Weather.Types.OpenButton )
    , ( "CloseButton", \() -> put Weather.Types.CloseButton )
    ]


tree_WebViewer_Mode put value =
    case value of
        WebViewer.TextMode ->
            ModelTree.variant "TextMode" [] (choices_WebViewer_Mode put)

        WebViewer.HtmlMode ->
            ModelTree.variant "HtmlMode" [] (choices_WebViewer_Mode put)


choices_WebViewer_Mode put =
    [ ( "TextMode", \() -> put WebViewer.TextMode )
    , ( "HtmlMode", \() -> put WebViewer.HtmlMode )
    ]


tree_WebViewer_Model put value =
    ModelTree.record
        [ ( "isOpen", \() -> ModelTree.bool (\x -> put { value | isOpen = x }) value.isOpen )
        , ( "mode", \() -> tree_WebViewer_Mode (\x -> put { value | mode = x }) value.mode )
        , ( "page", \() -> tree_WebViewer_Page (\x -> put { value | page = x }) value.page )
        , ( "requestCount", \() -> ModelTree.int (\x -> put { value | requestCount = x }) value.requestCount )
        ]


tree_WebViewer_Page put value =
    case value of
        WebViewer.NoPage ->
            ModelTree.variant "NoPage" [] (choices_WebViewer_Page put)

        WebViewer.Loading a0 ->
            ModelTree.variant "Loading" [ \() -> ModelTree.string (\new -> put (WebViewer.Loading new)) a0 ] (choices_WebViewer_Page put)

        WebViewer.Loaded a0 ->
            ModelTree.variant "Loaded" [ \() -> (\put1 value1 -> ModelTree.record [ ( "url", \() -> ModelTree.string (\x1 -> put1 { value1 | url = x1 }) value1.url ), ( "status", \() -> ModelTree.int (\x1 -> put1 { value1 | status = x1 }) value1.status ), ( "html", \() -> ModelTree.string (\x1 -> put1 { value1 | html = x1 }) value1.html ), ( "text", \() -> ModelTree.string (\x1 -> put1 { value1 | text = x1 }) value1.text ) ]) (\new -> put (WebViewer.Loaded new)) a0 ] (choices_WebViewer_Page put)

        WebViewer.Failed a0 ->
            ModelTree.variant "Failed" [ \() -> (\put1 value1 -> ModelTree.record [ ( "url", \() -> ModelTree.string (\x1 -> put1 { value1 | url = x1 }) value1.url ), ( "error", \() -> ModelTree.string (\x1 -> put1 { value1 | error = x1 }) value1.error ) ]) (\new -> put (WebViewer.Failed new)) a0 ] (choices_WebViewer_Page put)


choices_WebViewer_Page put =
    [ ( "NoPage", \() -> put WebViewer.NoPage )
    ]


tree_WebViewer_Types_UiId put value =
    case value of
        WebViewer.Types.OpenButton ->
            ModelTree.variant "OpenButton" [] (choices_WebViewer_Types_UiId put)

        WebViewer.Types.CloseButton ->
            ModelTree.variant "CloseButton" [] (choices_WebViewer_Types_UiId put)

        WebViewer.Types.UrlInput ->
            ModelTree.variant "UrlInput" [] (choices_WebViewer_Types_UiId put)

        WebViewer.Types.GoButton ->
            ModelTree.variant "GoButton" [] (choices_WebViewer_Types_UiId put)

        WebViewer.Types.TextModeButton ->
            ModelTree.variant "TextModeButton" [] (choices_WebViewer_Types_UiId put)

        WebViewer.Types.HtmlModeButton ->
            ModelTree.variant "HtmlModeButton" [] (choices_WebViewer_Types_UiId put)

        WebViewer.Types.TextViewport ->
            ModelTree.variant "TextViewport" [] (choices_WebViewer_Types_UiId put)

        WebViewer.Types.HtmlViewport ->
            ModelTree.variant "HtmlViewport" [] (choices_WebViewer_Types_UiId put)


choices_WebViewer_Types_UiId put =
    [ ( "OpenButton", \() -> put WebViewer.Types.OpenButton )
    , ( "CloseButton", \() -> put WebViewer.Types.CloseButton )
    , ( "UrlInput", \() -> put WebViewer.Types.UrlInput )
    , ( "GoButton", \() -> put WebViewer.Types.GoButton )
    , ( "TextModeButton", \() -> put WebViewer.Types.TextModeButton )
    , ( "HtmlModeButton", \() -> put WebViewer.Types.HtmlModeButton )
    , ( "TextViewport", \() -> put WebViewer.Types.TextViewport )
    , ( "HtmlViewport", \() -> put WebViewer.Types.HtmlViewport )
    ]
