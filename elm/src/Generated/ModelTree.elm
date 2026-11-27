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
import History
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
    ModelTree.record [ "kernel", "cpu", "commit", "build" ] (field_About_Types_SystemInfo put value)


field_About_Types_SystemInfo put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | kernel = x })) value.kernel

        1 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | cpu = x })) value.cpu

        2 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | commit = x })) value.commit

        _ ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | build = x })) value.build


tree_About_Types_UiId put value =
    case value of
        About.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 ModelTree.noChild names_About_Types_UiId (choose_About_Types_UiId put)

        About.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 ModelTree.noChild names_About_Types_UiId (choose_About_Types_UiId put)


names_About_Types_UiId =
    [ "OpenButton"
    , "CloseButton"
    ]


choose_About_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put About.Types.OpenButton

        _ ->
            ModelTree.apply put About.Types.CloseButton


tree_AsciiCollab_Connection put value =
    case value of
        AsciiCollab.Disconnected _ ->
            ModelTree.variant "Disconnected" 1 (args_AsciiCollab_Connection put value) names_AsciiCollab_Connection (choose_AsciiCollab_Connection put)

        AsciiCollab.WaitingForId ->
            ModelTree.variant "WaitingForId" 0 (args_AsciiCollab_Connection put value) names_AsciiCollab_Connection (choose_AsciiCollab_Connection put)

        AsciiCollab.Connecting ->
            ModelTree.variant "Connecting" 0 (args_AsciiCollab_Connection put value) names_AsciiCollab_Connection (choose_AsciiCollab_Connection put)

        AsciiCollab.Connected ->
            ModelTree.variant "Connected" 0 (args_AsciiCollab_Connection put value) names_AsciiCollab_Connection (choose_AsciiCollab_Connection put)


args_AsciiCollab_Connection put value i =
    case value of
        AsciiCollab.Disconnected a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "reason", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | reason = x1 })) value1.reason ), ( "retryAt", \() -> ModelTree.int (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | retryAt = x1 })) value1.retryAt ) ]) (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Disconnected new))) a0

        AsciiCollab.WaitingForId ->
            ModelTree.noChild i

        AsciiCollab.Connecting ->
            ModelTree.noChild i

        AsciiCollab.Connected ->
            ModelTree.noChild i


names_AsciiCollab_Connection =
    [ "WaitingForId"
    , "Connecting"
    , "Connected"
    ]


choose_AsciiCollab_Connection put i =
    case i of
        0 ->
            ModelTree.apply put AsciiCollab.WaitingForId

        1 ->
            ModelTree.apply put AsciiCollab.Connecting

        _ ->
            ModelTree.apply put AsciiCollab.Connected


tree_AsciiCollab_Model put value =
    ModelTree.record [ "isOpen", "connection", "clientId", "sessionCookie", "appVersion", "nextSeq", "unacked", "state", "cursor", "lineStart", "viewPoint", "scrollRemainder", "pendingChanges", "now", "lastUndoPoint", "lastSent" ] (field_AsciiCollab_Model put value)


field_AsciiCollab_Model put value i =
    case i of
        0 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | isOpen = x })) value.isOpen

        1 ->
            tree_AsciiCollab_Connection (ModelTree.Put (\x -> ModelTree.apply put { value | connection = x })) value.connection

        2 ->
            ModelTree.maybe ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | clientId = x })) value.clientId

        3 ->
            ModelTree.maybe ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | sessionCookie = x })) value.sessionCookie

        4 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | appVersion = x })) value.appVersion

        5 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | nextSeq = x })) value.nextSeq

        6 ->
            ModelTree.list (\put1 value1 -> ModelTree.fields [ ( "seq", \() -> ModelTree.int (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | seq = x1 })) value1.seq ), ( "data", \() -> ModelTree.bytes (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | data = x1 })) value1.data ) ]) (ModelTree.Put (\x -> ModelTree.apply put { value | unacked = x })) value.unacked

        7 ->
            tree_AsciiCollab_State (ModelTree.Put (\x -> ModelTree.apply put { value | state = x })) value.state

        8 ->
            tree_Coord_Coord (ModelTree.Put (\x -> ModelTree.apply put { value | cursor = x })) value.cursor

        9 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | lineStart = x })) value.lineStart

        10 ->
            tree_Coord_Coord (ModelTree.Put (\x -> ModelTree.apply put { value | viewPoint = x })) value.viewPoint

        11 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | scrollRemainder = x })) value.scrollRemainder

        12 ->
            ModelTree.list tree_AsciiCollab_Types_LocalChange (ModelTree.Put (\x -> ModelTree.apply put { value | pendingChanges = x })) value.pendingChanges

        13 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | now = x })) value.now

        14 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | lastUndoPoint = x })) value.lastUndoPoint

        _ ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | lastSent = x })) value.lastSent


tree_AsciiCollab_State put value =
    case value of
        AsciiCollab.NotLoaded ->
            ModelTree.variant "NotLoaded" 0 (args_AsciiCollab_State put value) names_AsciiCollab_State (choose_AsciiCollab_State put)

        AsciiCollab.Loaded _ ->
            ModelTree.variant "Loaded" 1 (args_AsciiCollab_State put value) names_AsciiCollab_State (choose_AsciiCollab_State put)


args_AsciiCollab_State put value i =
    case value of
        AsciiCollab.NotLoaded ->
            ModelTree.noChild i

        AsciiCollab.Loaded a0 ->
            tree_AsciiCollab_LocalGrid_LocalModel (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Loaded new))) a0


names_AsciiCollab_State =
    [ "NotLoaded"
    ]


choose_AsciiCollab_State put _ =
    ModelTree.apply put AsciiCollab.NotLoaded


tree_AsciiCollab_LocalGrid_LocalGrid put value =
    ModelTree.record [ "grid", "undoHistory", "redoHistory", "user", "hiddenUsers", "adminHiddenUsers", "viewBounds", "undoCurrent" ] (field_AsciiCollab_LocalGrid_LocalGrid put value)


field_AsciiCollab_LocalGrid_LocalGrid put value i =
    case i of
        0 ->
            tree_AsciiCollab_Types_Grid (ModelTree.Put (\x -> ModelTree.apply put { value | grid = x })) value.grid

        1 ->
            ModelTree.list (ModelTree.dict (ModelTree.tuple2 ModelTree.int ModelTree.int) ModelTree.int) (ModelTree.Put (\x -> ModelTree.apply put { value | undoHistory = x })) value.undoHistory

        2 ->
            ModelTree.list (ModelTree.dict (ModelTree.tuple2 ModelTree.int ModelTree.int) ModelTree.int) (ModelTree.Put (\x -> ModelTree.apply put { value | redoHistory = x })) value.redoHistory

        3 ->
            tree_AsciiCollab_Types_UserId (ModelTree.Put (\x -> ModelTree.apply put { value | user = x })) value.user

        4 ->
            ModelTree.seqSet tree_AsciiCollab_Types_UserId (ModelTree.Put (\x -> ModelTree.apply put { value | hiddenUsers = x })) value.hiddenUsers

        5 ->
            ModelTree.seqSet tree_AsciiCollab_Types_UserId (ModelTree.Put (\x -> ModelTree.apply put { value | adminHiddenUsers = x })) value.adminHiddenUsers

        6 ->
            tree_AsciiCollab_Types_Bounds (ModelTree.Put (\x -> ModelTree.apply put { value | viewBounds = x })) value.viewBounds

        _ ->
            ModelTree.dict (ModelTree.tuple2 ModelTree.int ModelTree.int) ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | undoCurrent = x })) value.undoCurrent


tree_AsciiCollab_LocalGrid_LocalModel put value =
    ModelTree.record [ "localMsgs", "localModel", "model" ] (field_AsciiCollab_LocalGrid_LocalModel put value)


field_AsciiCollab_LocalGrid_LocalModel put value i =
    case i of
        0 ->
            ModelTree.list tree_AsciiCollab_Types_Change (ModelTree.Put (\x -> ModelTree.apply put { value | localMsgs = x })) value.localMsgs

        1 ->
            tree_AsciiCollab_LocalGrid_LocalGrid (ModelTree.Put (\x -> ModelTree.apply put { value | localModel = x })) value.localModel

        _ ->
            tree_AsciiCollab_LocalGrid_LocalGrid (ModelTree.Put (\x -> ModelTree.apply put { value | model = x })) value.model


tree_AsciiCollab_Types_Ascii put value =
    case value of
        AsciiCollab.Types.Ascii _ ->
            ModelTree.variant "Ascii" 1 (args_AsciiCollab_Types_Ascii put value) [] (ModelTree.unchanged put value)


args_AsciiCollab_Types_Ascii put value i =
    case value of
        AsciiCollab.Types.Ascii a0 ->
            ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.Ascii new))) a0


tree_AsciiCollab_Types_Bounds put value =
    case value of
        AsciiCollab.Types.Bounds _ ->
            ModelTree.variant "Bounds" 1 (args_AsciiCollab_Types_Bounds put value) [] (ModelTree.unchanged put value)


args_AsciiCollab_Types_Bounds put value i =
    case value of
        AsciiCollab.Types.Bounds a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "min", \() -> tree_Coord_Coord (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | min = x1 })) value1.min ), ( "max", \() -> tree_Coord_Coord (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | max = x1 })) value1.max ) ]) (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.Bounds new))) a0


tree_AsciiCollab_Types_Cell put value =
    case value of
        AsciiCollab.Types.Cell _ ->
            ModelTree.variant "Cell" 1 (args_AsciiCollab_Types_Cell put value) [] (ModelTree.unchanged put value)


args_AsciiCollab_Types_Cell put value i =
    case value of
        AsciiCollab.Types.Cell a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "history", \() -> ModelTree.list (\put2 value2 -> ModelTree.fields [ ( "userId", \() -> tree_AsciiCollab_Types_UserId (ModelTree.Put (\x2 -> ModelTree.apply put2 { value2 | userId = x2 })) value2.userId ), ( "position", \() -> ModelTree.int (ModelTree.Put (\x2 -> ModelTree.apply put2 { value2 | position = x2 })) value2.position ), ( "line", \() -> tree_AsciiCollab_Types_Nonempty tree_AsciiCollab_Types_Ascii (ModelTree.Put (\x2 -> ModelTree.apply put2 { value2 | line = x2 })) value2.line ) ]) (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | history = x1 })) value1.history ), ( "undoPoint", \() -> ModelTree.dict ModelTree.int ModelTree.int (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | undoPoint = x1 })) value1.undoPoint ) ]) (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.Cell new))) a0


tree_AsciiCollab_Types_Change put value =
    case value of
        AsciiCollab.Types.LocalChange _ ->
            ModelTree.variant "LocalChange" 1 (args_AsciiCollab_Types_Change put value) [] (ModelTree.unchanged put value)

        AsciiCollab.Types.ServerChange _ ->
            ModelTree.variant "ServerChange" 1 (args_AsciiCollab_Types_Change put value) [] (ModelTree.unchanged put value)

        AsciiCollab.Types.ClientChange _ ->
            ModelTree.variant "ClientChange" 1 (args_AsciiCollab_Types_Change put value) [] (ModelTree.unchanged put value)


args_AsciiCollab_Types_Change put value i =
    case value of
        AsciiCollab.Types.LocalChange a0 ->
            tree_AsciiCollab_Types_LocalChange (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.LocalChange new))) a0

        AsciiCollab.Types.ServerChange a0 ->
            tree_AsciiCollab_Types_ServerChange (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.ServerChange new))) a0

        AsciiCollab.Types.ClientChange a0 ->
            tree_AsciiCollab_Types_ClientChange (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.ClientChange new))) a0


tree_AsciiCollab_Types_ClientChange put value =
    case value of
        AsciiCollab.Types.ViewBoundsChange _ _ ->
            ModelTree.variant "ViewBoundsChange" 2 (args_AsciiCollab_Types_ClientChange put value) [] (ModelTree.unchanged put value)


args_AsciiCollab_Types_ClientChange put value i =
    case value of
        AsciiCollab.Types.ViewBoundsChange a0 a1 ->
            case i of
                0 ->
                    tree_AsciiCollab_Types_Bounds (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.ViewBoundsChange new a1))) a0

                _ ->
                    ModelTree.list (ModelTree.tuple2 tree_Coord_Coord tree_AsciiCollab_Types_Cell) (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.ViewBoundsChange a0 new))) a1


tree_AsciiCollab_Types_Grid put value =
    case value of
        AsciiCollab.Types.Grid _ ->
            ModelTree.variant "Grid" 1 (args_AsciiCollab_Types_Grid put value) [] (ModelTree.unchanged put value)


args_AsciiCollab_Types_Grid put value i =
    case value of
        AsciiCollab.Types.Grid a0 ->
            ModelTree.dict (ModelTree.tuple2 ModelTree.int ModelTree.int) tree_AsciiCollab_Types_Cell (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.Grid new))) a0


tree_AsciiCollab_Types_GridChangeData put value =
    ModelTree.record [ "cellPosition", "localPosition", "change", "userId" ] (field_AsciiCollab_Types_GridChangeData put value)


field_AsciiCollab_Types_GridChangeData put value i =
    case i of
        0 ->
            tree_Coord_Coord (ModelTree.Put (\x -> ModelTree.apply put { value | cellPosition = x })) value.cellPosition

        1 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | localPosition = x })) value.localPosition

        2 ->
            tree_AsciiCollab_Types_Nonempty tree_AsciiCollab_Types_Ascii (ModelTree.Put (\x -> ModelTree.apply put { value | change = x })) value.change

        _ ->
            tree_AsciiCollab_Types_UserId (ModelTree.Put (\x -> ModelTree.apply put { value | userId = x })) value.userId


tree_AsciiCollab_Types_LocalChange put value =
    case value of
        AsciiCollab.Types.LocalGridChange _ ->
            ModelTree.variant "LocalGridChange" 1 (args_AsciiCollab_Types_LocalChange put value) names_AsciiCollab_Types_LocalChange (choose_AsciiCollab_Types_LocalChange put)

        AsciiCollab.Types.LocalUndo ->
            ModelTree.variant "LocalUndo" 0 (args_AsciiCollab_Types_LocalChange put value) names_AsciiCollab_Types_LocalChange (choose_AsciiCollab_Types_LocalChange put)

        AsciiCollab.Types.LocalRedo ->
            ModelTree.variant "LocalRedo" 0 (args_AsciiCollab_Types_LocalChange put value) names_AsciiCollab_Types_LocalChange (choose_AsciiCollab_Types_LocalChange put)

        AsciiCollab.Types.LocalAddUndo ->
            ModelTree.variant "LocalAddUndo" 0 (args_AsciiCollab_Types_LocalChange put value) names_AsciiCollab_Types_LocalChange (choose_AsciiCollab_Types_LocalChange put)

        AsciiCollab.Types.LocalHideUser _ _ ->
            ModelTree.variant "LocalHideUser" 2 (args_AsciiCollab_Types_LocalChange put value) names_AsciiCollab_Types_LocalChange (choose_AsciiCollab_Types_LocalChange put)

        AsciiCollab.Types.LocalUnhideUser _ ->
            ModelTree.variant "LocalUnhideUser" 1 (args_AsciiCollab_Types_LocalChange put value) names_AsciiCollab_Types_LocalChange (choose_AsciiCollab_Types_LocalChange put)

        AsciiCollab.Types.LocalToggleUserVisibilityForAll _ ->
            ModelTree.variant "LocalToggleUserVisibilityForAll" 1 (args_AsciiCollab_Types_LocalChange put value) names_AsciiCollab_Types_LocalChange (choose_AsciiCollab_Types_LocalChange put)


args_AsciiCollab_Types_LocalChange put value i =
    case value of
        AsciiCollab.Types.LocalGridChange a0 ->
            tree_AsciiCollab_Types_LocalGridChangeData (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.LocalGridChange new))) a0

        AsciiCollab.Types.LocalUndo ->
            ModelTree.noChild i

        AsciiCollab.Types.LocalRedo ->
            ModelTree.noChild i

        AsciiCollab.Types.LocalAddUndo ->
            ModelTree.noChild i

        AsciiCollab.Types.LocalHideUser a0 a1 ->
            case i of
                0 ->
                    tree_AsciiCollab_Types_UserId (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.LocalHideUser new a1))) a0

                _ ->
                    tree_Coord_Coord (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.LocalHideUser a0 new))) a1

        AsciiCollab.Types.LocalUnhideUser a0 ->
            tree_AsciiCollab_Types_UserId (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.LocalUnhideUser new))) a0

        AsciiCollab.Types.LocalToggleUserVisibilityForAll a0 ->
            tree_AsciiCollab_Types_UserId (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.LocalToggleUserVisibilityForAll new))) a0


names_AsciiCollab_Types_LocalChange =
    [ "LocalUndo"
    , "LocalRedo"
    , "LocalAddUndo"
    ]


choose_AsciiCollab_Types_LocalChange put i =
    case i of
        0 ->
            ModelTree.apply put AsciiCollab.Types.LocalUndo

        1 ->
            ModelTree.apply put AsciiCollab.Types.LocalRedo

        _ ->
            ModelTree.apply put AsciiCollab.Types.LocalAddUndo


tree_AsciiCollab_Types_LocalGridChangeData put value =
    ModelTree.record [ "cellPosition", "localPosition", "change" ] (field_AsciiCollab_Types_LocalGridChangeData put value)


field_AsciiCollab_Types_LocalGridChangeData put value i =
    case i of
        0 ->
            tree_Coord_Coord (ModelTree.Put (\x -> ModelTree.apply put { value | cellPosition = x })) value.cellPosition

        1 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | localPosition = x })) value.localPosition

        _ ->
            tree_AsciiCollab_Types_Nonempty tree_AsciiCollab_Types_Ascii (ModelTree.Put (\x -> ModelTree.apply put { value | change = x })) value.change


tree_AsciiCollab_Types_Nonempty tree_a put value =
    case value of
        AsciiCollab.Types.Nonempty _ _ ->
            ModelTree.variant "Nonempty" 2 (args_AsciiCollab_Types_Nonempty tree_a put value) [] (ModelTree.unchanged put value)


args_AsciiCollab_Types_Nonempty tree_a put value i =
    case value of
        AsciiCollab.Types.Nonempty a0 a1 ->
            case i of
                0 ->
                    tree_a (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.Nonempty new a1))) a0

                _ ->
                    ModelTree.list tree_a (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.Nonempty a0 new))) a1


tree_AsciiCollab_Types_ServerChange put value =
    case value of
        AsciiCollab.Types.ServerGridChange _ ->
            ModelTree.variant "ServerGridChange" 1 (args_AsciiCollab_Types_ServerChange put value) [] (ModelTree.unchanged put value)

        AsciiCollab.Types.ServerUndoPoint _ ->
            ModelTree.variant "ServerUndoPoint" 1 (args_AsciiCollab_Types_ServerChange put value) [] (ModelTree.unchanged put value)

        AsciiCollab.Types.ServerToggleUserVisibilityForAll _ ->
            ModelTree.variant "ServerToggleUserVisibilityForAll" 1 (args_AsciiCollab_Types_ServerChange put value) [] (ModelTree.unchanged put value)


args_AsciiCollab_Types_ServerChange put value i =
    case value of
        AsciiCollab.Types.ServerGridChange a0 ->
            tree_AsciiCollab_Types_GridChangeData (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.ServerGridChange new))) a0

        AsciiCollab.Types.ServerUndoPoint a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "userId", \() -> tree_AsciiCollab_Types_UserId (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | userId = x1 })) value1.userId ), ( "undoPoints", \() -> ModelTree.dict (ModelTree.tuple2 ModelTree.int ModelTree.int) ModelTree.int (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | undoPoints = x1 })) value1.undoPoints ) ]) (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.ServerUndoPoint new))) a0

        AsciiCollab.Types.ServerToggleUserVisibilityForAll a0 ->
            tree_AsciiCollab_Types_UserId (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.ServerToggleUserVisibilityForAll new))) a0


tree_AsciiCollab_Types_UiId put value =
    case value of
        AsciiCollab.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 ModelTree.noChild names_AsciiCollab_Types_UiId (choose_AsciiCollab_Types_UiId put)

        AsciiCollab.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 ModelTree.noChild names_AsciiCollab_Types_UiId (choose_AsciiCollab_Types_UiId put)

        AsciiCollab.Types.GridArea ->
            ModelTree.variant "GridArea" 0 ModelTree.noChild names_AsciiCollab_Types_UiId (choose_AsciiCollab_Types_UiId put)


names_AsciiCollab_Types_UiId =
    [ "OpenButton"
    , "CloseButton"
    , "GridArea"
    ]


choose_AsciiCollab_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put AsciiCollab.Types.OpenButton

        1 ->
            ModelTree.apply put AsciiCollab.Types.CloseButton

        _ ->
            ModelTree.apply put AsciiCollab.Types.GridArea


tree_AsciiCollab_Types_UserId put value =
    case value of
        AsciiCollab.Types.UserId _ ->
            ModelTree.variant "UserId" 1 (args_AsciiCollab_Types_UserId put value) [] (ModelTree.unchanged put value)


args_AsciiCollab_Types_UserId put value i =
    case value of
        AsciiCollab.Types.UserId a0 ->
            ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (AsciiCollab.Types.UserId new))) a0


tree_BootInfo_Battery put value =
    ModelTree.record [ "batteries", "percent", "status", "minutes" ] (field_BootInfo_Battery put value)


field_BootInfo_Battery put value i =
    case i of
        0 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | batteries = x })) value.batteries

        1 ->
            ModelTree.maybe ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | percent = x })) value.percent

        2 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | status = x })) value.status

        _ ->
            ModelTree.maybe ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | minutes = x })) value.minutes


tree_BootInfo_BootTimes put value =
    ModelTree.record [ "initMs", "elmMs", "frameMs" ] (field_BootInfo_BootTimes put value)


field_BootInfo_BootTimes put value i =
    case i of
        0 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | initMs = x })) value.initMs

        1 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | elmMs = x })) value.elmMs

        _ ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | frameMs = x })) value.frameMs


tree_BootInfo_Clock put value =
    ModelTree.record [ "minMhz", "maxMhz", "limitMhz", "governor", "hint" ] (field_BootInfo_Clock put value)


field_BootInfo_Clock put value i =
    case i of
        0 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | minMhz = x })) value.minMhz

        1 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | maxMhz = x })) value.maxMhz

        2 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | limitMhz = x })) value.limitMhz

        3 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | governor = x })) value.governor

        _ ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | hint = x })) value.hint


tree_BootInfo_Model put value =
    ModelTree.record [ "image", "seconds", "gptDisks", "battery", "cpufreqPolicies", "clock", "boot", "firmwareMs" ] (field_BootInfo_Model put value)


field_BootInfo_Model put value i =
    case i of
        0 ->
            ModelTree.opaqueTree "BootInfo.Image" (ModelTree.Put (\x -> ModelTree.apply put { value | image = x })) value.image

        1 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | seconds = x })) value.seconds

        2 ->
            ModelTree.list ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | gptDisks = x })) value.gptDisks

        3 ->
            ModelTree.maybe tree_BootInfo_Battery (ModelTree.Put (\x -> ModelTree.apply put { value | battery = x })) value.battery

        4 ->
            ModelTree.list ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | cpufreqPolicies = x })) value.cpufreqPolicies

        5 ->
            ModelTree.maybe tree_BootInfo_Clock (ModelTree.Put (\x -> ModelTree.apply put { value | clock = x })) value.clock

        6 ->
            ModelTree.maybe tree_BootInfo_BootTimes (ModelTree.Put (\x -> ModelTree.apply put { value | boot = x })) value.boot

        _ ->
            ModelTree.maybe ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | firmwareMs = x })) value.firmwareMs


tree_Bounds_Bounds put value =
    ModelTree.record [ "topLeft", "bottomRight" ] (field_Bounds_Bounds put value)


field_Bounds_Bounds put value i =
    case i of
        0 ->
            tree_Coord_Coord (ModelTree.Put (\x -> ModelTree.apply put { value | topLeft = x })) value.topLeft

        _ ->
            tree_Coord_Coord (ModelTree.Put (\x -> ModelTree.apply put { value | bottomRight = x })) value.bottomRight


tree_Brightness_Backlight put value =
    ModelTree.record [ "path", "max" ] (field_Brightness_Backlight put value)


field_Brightness_Backlight put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | path = x })) value.path

        _ ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | max = x })) value.max


tree_Brightness_Model put value =
    ModelTree.record [ "backlight", "level" ] (field_Brightness_Model put value)


field_Brightness_Model put value i =
    case i of
        0 ->
            ModelTree.maybe tree_Brightness_Backlight (ModelTree.Put (\x -> ModelTree.apply put { value | backlight = x })) value.backlight

        _ ->
            ModelTree.maybe ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | level = x })) value.level


tree_Button_Model put value =
    ModelTree.record [ "buttonDown" ] (field_Button_Model put value)


field_Button_Model put value _ =
    ModelTree.maybe (ModelTree.tuple2 ModelTree.posix tree_Coord_Coord) (ModelTree.Put (\x -> ModelTree.apply put { value | buttonDown = x })) value.buttonDown


tree_Calculator_Entry put value =
    case value of
        Calculator.Typed _ ->
            ModelTree.variant "Typed" 1 (args_Calculator_Entry put value) names_Calculator_Entry (choose_Calculator_Entry put)

        Calculator.Shown _ ->
            ModelTree.variant "Shown" 1 (args_Calculator_Entry put value) names_Calculator_Entry (choose_Calculator_Entry put)

        Calculator.Error ->
            ModelTree.variant "Error" 0 (args_Calculator_Entry put value) names_Calculator_Entry (choose_Calculator_Entry put)


args_Calculator_Entry put value i =
    case value of
        Calculator.Typed a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Calculator.Typed new))) a0

        Calculator.Shown a0 ->
            ModelTree.float (ModelTree.Put (\new -> ModelTree.apply put (Calculator.Shown new))) a0

        Calculator.Error ->
            ModelTree.noChild i


names_Calculator_Entry =
    [ "Error"
    ]


choose_Calculator_Entry put _ =
    ModelTree.apply put Calculator.Error


tree_Calculator_Model put value =
    ModelTree.record [ "entry", "pending", "repeat" ] (field_Calculator_Model put value)


field_Calculator_Model put value i =
    case i of
        0 ->
            tree_Calculator_Entry (ModelTree.Put (\x -> ModelTree.apply put { value | entry = x })) value.entry

        1 ->
            ModelTree.maybe (ModelTree.tuple2 ModelTree.float tree_Calculator_Types_Operator) (ModelTree.Put (\x -> ModelTree.apply put { value | pending = x })) value.pending

        _ ->
            ModelTree.maybe (ModelTree.tuple2 tree_Calculator_Types_Operator ModelTree.float) (ModelTree.Put (\x -> ModelTree.apply put { value | repeat = x })) value.repeat


tree_Calculator_Types_Key put value =
    case value of
        Calculator.Types.Digit _ ->
            ModelTree.variant "Digit" 1 (args_Calculator_Types_Key put value) names_Calculator_Types_Key (choose_Calculator_Types_Key put)

        Calculator.Types.Point ->
            ModelTree.variant "Point" 0 (args_Calculator_Types_Key put value) names_Calculator_Types_Key (choose_Calculator_Types_Key put)

        Calculator.Types.Operator _ ->
            ModelTree.variant "Operator" 1 (args_Calculator_Types_Key put value) names_Calculator_Types_Key (choose_Calculator_Types_Key put)

        Calculator.Types.Equals ->
            ModelTree.variant "Equals" 0 (args_Calculator_Types_Key put value) names_Calculator_Types_Key (choose_Calculator_Types_Key put)

        Calculator.Types.Negate ->
            ModelTree.variant "Negate" 0 (args_Calculator_Types_Key put value) names_Calculator_Types_Key (choose_Calculator_Types_Key put)

        Calculator.Types.Backspace ->
            ModelTree.variant "Backspace" 0 (args_Calculator_Types_Key put value) names_Calculator_Types_Key (choose_Calculator_Types_Key put)

        Calculator.Types.Clear ->
            ModelTree.variant "Clear" 0 (args_Calculator_Types_Key put value) names_Calculator_Types_Key (choose_Calculator_Types_Key put)


args_Calculator_Types_Key put value i =
    case value of
        Calculator.Types.Digit a0 ->
            ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (Calculator.Types.Digit new))) a0

        Calculator.Types.Point ->
            ModelTree.noChild i

        Calculator.Types.Operator a0 ->
            tree_Calculator_Types_Operator (ModelTree.Put (\new -> ModelTree.apply put (Calculator.Types.Operator new))) a0

        Calculator.Types.Equals ->
            ModelTree.noChild i

        Calculator.Types.Negate ->
            ModelTree.noChild i

        Calculator.Types.Backspace ->
            ModelTree.noChild i

        Calculator.Types.Clear ->
            ModelTree.noChild i


names_Calculator_Types_Key =
    [ "Point"
    , "Equals"
    , "Negate"
    , "Backspace"
    , "Clear"
    ]


choose_Calculator_Types_Key put i =
    case i of
        0 ->
            ModelTree.apply put Calculator.Types.Point

        1 ->
            ModelTree.apply put Calculator.Types.Equals

        2 ->
            ModelTree.apply put Calculator.Types.Negate

        3 ->
            ModelTree.apply put Calculator.Types.Backspace

        _ ->
            ModelTree.apply put Calculator.Types.Clear


tree_Calculator_Types_Operator put value =
    case value of
        Calculator.Types.Add ->
            ModelTree.variant "Add" 0 ModelTree.noChild names_Calculator_Types_Operator (choose_Calculator_Types_Operator put)

        Calculator.Types.Subtract ->
            ModelTree.variant "Subtract" 0 ModelTree.noChild names_Calculator_Types_Operator (choose_Calculator_Types_Operator put)

        Calculator.Types.Multiply ->
            ModelTree.variant "Multiply" 0 ModelTree.noChild names_Calculator_Types_Operator (choose_Calculator_Types_Operator put)

        Calculator.Types.Divide ->
            ModelTree.variant "Divide" 0 ModelTree.noChild names_Calculator_Types_Operator (choose_Calculator_Types_Operator put)


names_Calculator_Types_Operator =
    [ "Add"
    , "Subtract"
    , "Multiply"
    , "Divide"
    ]


choose_Calculator_Types_Operator put i =
    case i of
        0 ->
            ModelTree.apply put Calculator.Types.Add

        1 ->
            ModelTree.apply put Calculator.Types.Subtract

        2 ->
            ModelTree.apply put Calculator.Types.Multiply

        _ ->
            ModelTree.apply put Calculator.Types.Divide


tree_Calculator_Types_UiId put value =
    case value of
        Calculator.Types.KeyButton _ ->
            ModelTree.variant "KeyButton" 1 (args_Calculator_Types_UiId put value) names_Calculator_Types_UiId (choose_Calculator_Types_UiId put)

        Calculator.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 (args_Calculator_Types_UiId put value) names_Calculator_Types_UiId (choose_Calculator_Types_UiId put)

        Calculator.Types.Panel ->
            ModelTree.variant "Panel" 0 (args_Calculator_Types_UiId put value) names_Calculator_Types_UiId (choose_Calculator_Types_UiId put)


args_Calculator_Types_UiId put value i =
    case value of
        Calculator.Types.KeyButton a0 ->
            tree_Calculator_Types_Key (ModelTree.Put (\new -> ModelTree.apply put (Calculator.Types.KeyButton new))) a0

        Calculator.Types.CloseButton ->
            ModelTree.noChild i

        Calculator.Types.Panel ->
            ModelTree.noChild i


names_Calculator_Types_UiId =
    [ "CloseButton"
    , "Panel"
    ]


choose_Calculator_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put Calculator.Types.CloseButton

        _ ->
            ModelTree.apply put Calculator.Types.Panel


tree_Code_Model put value =
    ModelTree.record [ "isOpen", "local", "module_", "saved", "build", "showErrors", "committing", "git", "finding", "back", "forward", "lastPlace", "usages" ] (field_Code_Model put value)


field_Code_Model put value i =
    case i of
        0 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | isOpen = x })) value.isOpen

        1 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | local = x })) value.local

        2 ->
            ModelTree.maybe ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | module_ = x })) value.module_

        3 ->
            ModelTree.seqDict ModelTree.string ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | saved = x })) value.saved

        4 ->
            ModelTree.maybe tree_Code_Types_BuildStatus (ModelTree.Put (\x -> ModelTree.apply put { value | build = x })) value.build

        5 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | showErrors = x })) value.showErrors

        6 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | committing = x })) value.committing

        7 ->
            tree_Code_Types_Git (ModelTree.Put (\x -> ModelTree.apply put { value | git = x })) value.git

        8 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | finding = x })) value.finding

        9 ->
            ModelTree.list tree_Code_Types_Place (ModelTree.Put (\x -> ModelTree.apply put { value | back = x })) value.back

        10 ->
            ModelTree.list tree_Code_Types_Place (ModelTree.Put (\x -> ModelTree.apply put { value | forward = x })) value.forward

        11 ->
            ModelTree.maybe tree_Code_Types_Place (ModelTree.Put (\x -> ModelTree.apply put { value | lastPlace = x })) value.lastPlace

        _ ->
            ModelTree.maybe tree_Code_Types_UsageList (ModelTree.Put (\x -> ModelTree.apply put { value | usages = x })) value.usages


tree_Code_Index_Usage put value =
    ModelTree.record [ "module_", "position", "line", "text" ] (field_Code_Index_Usage put value)


field_Code_Index_Usage put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | module_ = x })) value.module_

        1 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | position = x })) value.position

        2 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | line = x })) value.line

        _ ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | text = x })) value.text


tree_Code_Types_BuildStatus put value =
    case value of
        Code.Types.BuildRunning _ ->
            ModelTree.variant "BuildRunning" 1 (args_Code_Types_BuildStatus put value) [] (ModelTree.unchanged put value)

        Code.Types.BuildFailed _ _ ->
            ModelTree.variant "BuildFailed" 2 (args_Code_Types_BuildStatus put value) [] (ModelTree.unchanged put value)

        Code.Types.Built _ ->
            ModelTree.variant "Built" 1 (args_Code_Types_BuildStatus put value) [] (ModelTree.unchanged put value)


args_Code_Types_BuildStatus put value i =
    case value of
        Code.Types.BuildRunning a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.BuildRunning new))) a0

        Code.Types.BuildFailed a0 a1 ->
            case i of
                0 ->
                    ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.BuildFailed new a1))) a0

                _ ->
                    ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.BuildFailed a0 new))) a1

        Code.Types.Built a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.Built new))) a0


tree_Code_Types_Git put value =
    ModelTree.record [ "base", "branch", "from", "pushed", "status", "requests" ] (field_Code_Types_Git put value)


field_Code_Types_Git put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | base = x })) value.base

        1 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | branch = x })) value.branch

        2 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | from = x })) value.from

        3 ->
            ModelTree.seqDict ModelTree.string ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | pushed = x })) value.pushed

        4 ->
            tree_Code_Types_GitStatus (ModelTree.Put (\x -> ModelTree.apply put { value | status = x })) value.status

        _ ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | requests = x })) value.requests


tree_Code_Types_GitStatus put value =
    case value of
        Code.Types.GitIdle ->
            ModelTree.variant "GitIdle" 0 (args_Code_Types_GitStatus put value) names_Code_Types_GitStatus (choose_Code_Types_GitStatus put)

        Code.Types.GitWorking _ ->
            ModelTree.variant "GitWorking" 1 (args_Code_Types_GitStatus put value) names_Code_Types_GitStatus (choose_Code_Types_GitStatus put)

        Code.Types.GitPushed _ _ ->
            ModelTree.variant "GitPushed" 2 (args_Code_Types_GitStatus put value) names_Code_Types_GitStatus (choose_Code_Types_GitStatus put)

        Code.Types.GitFailed _ _ ->
            ModelTree.variant "GitFailed" 2 (args_Code_Types_GitStatus put value) names_Code_Types_GitStatus (choose_Code_Types_GitStatus put)


args_Code_Types_GitStatus put value i =
    case value of
        Code.Types.GitIdle ->
            ModelTree.noChild i

        Code.Types.GitWorking a0 ->
            tree_Code_Types_GitWork (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.GitWorking new))) a0

        Code.Types.GitPushed a0 a1 ->
            case i of
                0 ->
                    ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.GitPushed new a1))) a0

                _ ->
                    ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.GitPushed a0 new))) a1

        Code.Types.GitFailed a0 a1 ->
            case i of
                0 ->
                    ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.GitFailed new a1))) a0

                _ ->
                    ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.GitFailed a0 new))) a1


names_Code_Types_GitStatus =
    [ "GitIdle"
    ]


choose_Code_Types_GitStatus put _ =
    ModelTree.apply put Code.Types.GitIdle


tree_Code_Types_GitStep put value =
    case value of
        Code.Types.GettingBase ->
            ModelTree.variant "GettingBase" 0 (args_Code_Types_GitStep put value) names_Code_Types_GitStep (choose_Code_Types_GitStep put)

        Code.Types.MakingTree ->
            ModelTree.variant "MakingTree" 0 (args_Code_Types_GitStep put value) names_Code_Types_GitStep (choose_Code_Types_GitStep put)

        Code.Types.MakingCommit ->
            ModelTree.variant "MakingCommit" 0 (args_Code_Types_GitStep put value) names_Code_Types_GitStep (choose_Code_Types_GitStep put)

        Code.Types.Pushing _ ->
            ModelTree.variant "Pushing" 1 (args_Code_Types_GitStep put value) names_Code_Types_GitStep (choose_Code_Types_GitStep put)

        Code.Types.MakingBranch _ _ ->
            ModelTree.variant "MakingBranch" 2 (args_Code_Types_GitStep put value) names_Code_Types_GitStep (choose_Code_Types_GitStep put)


args_Code_Types_GitStep put value i =
    case value of
        Code.Types.GettingBase ->
            ModelTree.noChild i

        Code.Types.MakingTree ->
            ModelTree.noChild i

        Code.Types.MakingCommit ->
            ModelTree.noChild i

        Code.Types.Pushing a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.Pushing new))) a0

        Code.Types.MakingBranch a0 a1 ->
            case i of
                0 ->
                    ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.MakingBranch new a1))) a0

                _ ->
                    ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.MakingBranch a0 new))) a1


names_Code_Types_GitStep =
    [ "GettingBase"
    , "MakingTree"
    , "MakingCommit"
    ]


choose_Code_Types_GitStep put i =
    case i of
        0 ->
            ModelTree.apply put Code.Types.GettingBase

        1 ->
            ModelTree.apply put Code.Types.MakingTree

        _ ->
            ModelTree.apply put Code.Types.MakingCommit


tree_Code_Types_GitWork put value =
    ModelTree.record [ "request", "step", "token", "message", "base", "branch", "modules" ] (field_Code_Types_GitWork put value)


field_Code_Types_GitWork put value i =
    case i of
        0 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | request = x })) value.request

        1 ->
            tree_Code_Types_GitStep (ModelTree.Put (\x -> ModelTree.apply put { value | step = x })) value.step

        2 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | token = x })) value.token

        3 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | message = x })) value.message

        4 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | base = x })) value.base

        5 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | branch = x })) value.branch

        _ ->
            ModelTree.seqDict ModelTree.string ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | modules = x })) value.modules


tree_Code_Types_Place put value =
    ModelTree.record [ "module_", "position", "line" ] (field_Code_Types_Place put value)


field_Code_Types_Place put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | module_ = x })) value.module_

        1 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | position = x })) value.position

        _ ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | line = x })) value.line


tree_Code_Types_UiId put value =
    case value of
        Code.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.Window ->
            ModelTree.variant "Window" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.Input ->
            ModelTree.variant "Input" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.ModulesViewport ->
            ModelTree.variant "ModulesViewport" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.ModuleButton _ ->
            ModelTree.variant "ModuleButton" 1 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.SaveButton ->
            ModelTree.variant "SaveButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.RevertButton ->
            ModelTree.variant "RevertButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.BuildButton ->
            ModelTree.variant "BuildButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.DeployedButton ->
            ModelTree.variant "DeployedButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.ErrorsCloseButton ->
            ModelTree.variant "ErrorsCloseButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.ErrorsViewport ->
            ModelTree.variant "ErrorsViewport" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.CommitButton ->
            ModelTree.variant "CommitButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.CommitCloseButton ->
            ModelTree.variant "CommitCloseButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.CommitViewport ->
            ModelTree.variant "CommitViewport" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.TokenInput ->
            ModelTree.variant "TokenInput" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.MessageInput ->
            ModelTree.variant "MessageInput" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.PushButton ->
            ModelTree.variant "PushButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.FindInput ->
            ModelTree.variant "FindInput" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.ReplaceInput ->
            ModelTree.variant "ReplaceInput" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.FindPreviousButton ->
            ModelTree.variant "FindPreviousButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.FindNextButton ->
            ModelTree.variant "FindNextButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.ReplaceButton ->
            ModelTree.variant "ReplaceButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.ReplaceAllButton ->
            ModelTree.variant "ReplaceAllButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.FindCloseButton ->
            ModelTree.variant "FindCloseButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.UsagesViewport ->
            ModelTree.variant "UsagesViewport" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.UsageButton _ ->
            ModelTree.variant "UsageButton" 1 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)

        Code.Types.UsagesCloseButton ->
            ModelTree.variant "UsagesCloseButton" 0 (args_Code_Types_UiId put value) names_Code_Types_UiId (choose_Code_Types_UiId put)


args_Code_Types_UiId put value i =
    case value of
        Code.Types.OpenButton ->
            ModelTree.noChild i

        Code.Types.Window ->
            ModelTree.noChild i

        Code.Types.Input ->
            ModelTree.noChild i

        Code.Types.CloseButton ->
            ModelTree.noChild i

        Code.Types.ModulesViewport ->
            ModelTree.noChild i

        Code.Types.ModuleButton a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.ModuleButton new))) a0

        Code.Types.SaveButton ->
            ModelTree.noChild i

        Code.Types.RevertButton ->
            ModelTree.noChild i

        Code.Types.BuildButton ->
            ModelTree.noChild i

        Code.Types.DeployedButton ->
            ModelTree.noChild i

        Code.Types.ErrorsCloseButton ->
            ModelTree.noChild i

        Code.Types.ErrorsViewport ->
            ModelTree.noChild i

        Code.Types.CommitButton ->
            ModelTree.noChild i

        Code.Types.CommitCloseButton ->
            ModelTree.noChild i

        Code.Types.CommitViewport ->
            ModelTree.noChild i

        Code.Types.TokenInput ->
            ModelTree.noChild i

        Code.Types.MessageInput ->
            ModelTree.noChild i

        Code.Types.PushButton ->
            ModelTree.noChild i

        Code.Types.FindInput ->
            ModelTree.noChild i

        Code.Types.ReplaceInput ->
            ModelTree.noChild i

        Code.Types.FindPreviousButton ->
            ModelTree.noChild i

        Code.Types.FindNextButton ->
            ModelTree.noChild i

        Code.Types.ReplaceButton ->
            ModelTree.noChild i

        Code.Types.ReplaceAllButton ->
            ModelTree.noChild i

        Code.Types.FindCloseButton ->
            ModelTree.noChild i

        Code.Types.UsagesViewport ->
            ModelTree.noChild i

        Code.Types.UsageButton a0 ->
            ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (Code.Types.UsageButton new))) a0

        Code.Types.UsagesCloseButton ->
            ModelTree.noChild i


names_Code_Types_UiId =
    [ "OpenButton"
    , "Window"
    , "Input"
    , "CloseButton"
    , "ModulesViewport"
    , "SaveButton"
    , "RevertButton"
    , "BuildButton"
    , "DeployedButton"
    , "ErrorsCloseButton"
    , "ErrorsViewport"
    , "CommitButton"
    , "CommitCloseButton"
    , "CommitViewport"
    , "TokenInput"
    , "MessageInput"
    , "PushButton"
    , "FindInput"
    , "ReplaceInput"
    , "FindPreviousButton"
    , "FindNextButton"
    , "ReplaceButton"
    , "ReplaceAllButton"
    , "FindCloseButton"
    , "UsagesViewport"
    , "UsagesCloseButton"
    ]


choose_Code_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put Code.Types.OpenButton

        1 ->
            ModelTree.apply put Code.Types.Window

        2 ->
            ModelTree.apply put Code.Types.Input

        3 ->
            ModelTree.apply put Code.Types.CloseButton

        4 ->
            ModelTree.apply put Code.Types.ModulesViewport

        5 ->
            ModelTree.apply put Code.Types.SaveButton

        6 ->
            ModelTree.apply put Code.Types.RevertButton

        7 ->
            ModelTree.apply put Code.Types.BuildButton

        8 ->
            ModelTree.apply put Code.Types.DeployedButton

        9 ->
            ModelTree.apply put Code.Types.ErrorsCloseButton

        10 ->
            ModelTree.apply put Code.Types.ErrorsViewport

        11 ->
            ModelTree.apply put Code.Types.CommitButton

        12 ->
            ModelTree.apply put Code.Types.CommitCloseButton

        13 ->
            ModelTree.apply put Code.Types.CommitViewport

        14 ->
            ModelTree.apply put Code.Types.TokenInput

        15 ->
            ModelTree.apply put Code.Types.MessageInput

        16 ->
            ModelTree.apply put Code.Types.PushButton

        17 ->
            ModelTree.apply put Code.Types.FindInput

        18 ->
            ModelTree.apply put Code.Types.ReplaceInput

        19 ->
            ModelTree.apply put Code.Types.FindPreviousButton

        20 ->
            ModelTree.apply put Code.Types.FindNextButton

        21 ->
            ModelTree.apply put Code.Types.ReplaceButton

        22 ->
            ModelTree.apply put Code.Types.ReplaceAllButton

        23 ->
            ModelTree.apply put Code.Types.FindCloseButton

        24 ->
            ModelTree.apply put Code.Types.UsagesViewport

        _ ->
            ModelTree.apply put Code.Types.UsagesCloseButton


tree_Code_Types_UsageList put value =
    ModelTree.record [ "module_", "name", "found" ] (field_Code_Types_UsageList put value)


field_Code_Types_UsageList put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | module_ = x })) value.module_

        1 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | name = x })) value.name

        _ ->
            ModelTree.list tree_Code_Index_Usage (ModelTree.Put (\x -> ModelTree.apply put { value | found = x })) value.found


tree_Coord_Coord put value =
    ModelTree.tuple2 (ModelTree.quantity ModelTree.int) (ModelTree.quantity ModelTree.int) put value


tree_DebugInfo_Types_RendererInfo put value =
    ModelTree.record [ "gpu", "name", "hardwareCursor" ] (field_DebugInfo_Types_RendererInfo put value)


field_DebugInfo_Types_RendererInfo put value i =
    case i of
        0 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | gpu = x })) value.gpu

        1 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | name = x })) value.name

        _ ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | hardwareCursor = x })) value.hardwareCursor


tree_DebugInfo_Types_SystemStats put value =
    ModelTree.record [ "cores", "cpu", "cpuElm", "cpuHost", "cpuGpu", "memUsed", "memTotal", "gpuMs", "elmMs", "drawMs" ] (field_DebugInfo_Types_SystemStats put value)


field_DebugInfo_Types_SystemStats put value i =
    case i of
        0 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | cores = x })) value.cores

        1 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | cpu = x })) value.cpu

        2 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | cpuElm = x })) value.cpuElm

        3 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | cpuHost = x })) value.cpuHost

        4 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | cpuGpu = x })) value.cpuGpu

        5 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | memUsed = x })) value.memUsed

        6 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | memTotal = x })) value.memTotal

        7 ->
            ModelTree.maybe ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | gpuMs = x })) value.gpuMs

        8 ->
            ModelTree.maybe ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | elmMs = x })) value.elmMs

        _ ->
            ModelTree.maybe ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | drawMs = x })) value.drawMs


tree_DebugInfo_Types_UiId put value =
    case value of
        DebugInfo.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 ModelTree.noChild names_DebugInfo_Types_UiId (choose_DebugInfo_Types_UiId put)

        DebugInfo.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 ModelTree.noChild names_DebugInfo_Types_UiId (choose_DebugInfo_Types_UiId put)


names_DebugInfo_Types_UiId =
    [ "OpenButton"
    , "CloseButton"
    ]


choose_DebugInfo_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put DebugInfo.Types.OpenButton

        _ ->
            ModelTree.apply put DebugInfo.Types.CloseButton


tree_Display_Display put value =
    ModelTree.record [ "id", "name", "position", "size", "sizeMm" ] (field_Display_Display put value)


field_Display_Display put value i =
    case i of
        0 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | id = x })) value.id

        1 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | name = x })) value.name

        2 ->
            tree_Coord_Coord (ModelTree.Put (\x -> ModelTree.apply put { value | position = x })) value.position

        3 ->
            tree_Coord_Coord (ModelTree.Put (\x -> ModelTree.apply put { value | size = x })) value.size

        _ ->
            ModelTree.tuple2 ModelTree.int ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | sizeMm = x })) value.sizeMm


tree_Editor_Types_UiId put value =
    case value of
        Editor.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 ModelTree.noChild names_Editor_Types_UiId (choose_Editor_Types_UiId put)

        Editor.Types.Input ->
            ModelTree.variant "Input" 0 ModelTree.noChild names_Editor_Types_UiId (choose_Editor_Types_UiId put)

        Editor.Types.Window ->
            ModelTree.variant "Window" 0 ModelTree.noChild names_Editor_Types_UiId (choose_Editor_Types_UiId put)

        Editor.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 ModelTree.noChild names_Editor_Types_UiId (choose_Editor_Types_UiId put)


names_Editor_Types_UiId =
    [ "OpenButton"
    , "Input"
    , "Window"
    , "CloseButton"
    ]


choose_Editor_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put Editor.Types.OpenButton

        1 ->
            ModelTree.apply put Editor.Types.Input

        2 ->
            ModelTree.apply put Editor.Types.Window

        _ ->
            ModelTree.apply put Editor.Types.CloseButton


tree_Effect_HttpError put value =
    case value of
        Effect.BadUrl _ ->
            ModelTree.variant "BadUrl" 1 (args_Effect_HttpError put value) names_Effect_HttpError (choose_Effect_HttpError put)

        Effect.Timeout ->
            ModelTree.variant "Timeout" 0 (args_Effect_HttpError put value) names_Effect_HttpError (choose_Effect_HttpError put)

        Effect.NetworkError _ ->
            ModelTree.variant "NetworkError" 1 (args_Effect_HttpError put value) names_Effect_HttpError (choose_Effect_HttpError put)

        Effect.Interrupted ->
            ModelTree.variant "Interrupted" 0 (args_Effect_HttpError put value) names_Effect_HttpError (choose_Effect_HttpError put)

        Effect.BadBody _ ->
            ModelTree.variant "BadBody" 1 (args_Effect_HttpError put value) names_Effect_HttpError (choose_Effect_HttpError put)

        Effect.FailedToDecodeBody _ ->
            ModelTree.variant "FailedToDecodeBody" 1 (args_Effect_HttpError put value) names_Effect_HttpError (choose_Effect_HttpError put)


args_Effect_HttpError put value i =
    case value of
        Effect.BadUrl a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Effect.BadUrl new))) a0

        Effect.Timeout ->
            ModelTree.noChild i

        Effect.NetworkError a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Effect.NetworkError new))) a0

        Effect.Interrupted ->
            ModelTree.noChild i

        Effect.BadBody a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "status", \() -> ModelTree.int (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | status = x1 })) value1.status ), ( "body", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | body = x1 })) value1.body ) ]) (ModelTree.Put (\new -> ModelTree.apply put (Effect.BadBody new))) a0

        Effect.FailedToDecodeBody a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Effect.FailedToDecodeBody new))) a0


names_Effect_HttpError =
    [ "Timeout"
    , "Interrupted"
    ]


choose_Effect_HttpError put i =
    case i of
        0 ->
            ModelTree.apply put Effect.Timeout

        _ ->
            ModelTree.apply put Effect.Interrupted


tree_Email_Account put value =
    ModelTree.record [ "server", "address", "password" ] (field_Email_Account put value)


field_Email_Account put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | server = x })) value.server

        1 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | address = x })) value.address

        _ ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | password = x })) value.password


tree_Email_Job put value =
    case value of
        Email.ListInbox ->
            ModelTree.variant "ListInbox" 0 (args_Email_Job put value) names_Email_Job (choose_Email_Job put)

        Email.ReadMessage _ ->
            ModelTree.variant "ReadMessage" 1 (args_Email_Job put value) names_Email_Job (choose_Email_Job put)


args_Email_Job put value i =
    case value of
        Email.ListInbox ->
            ModelTree.noChild i

        Email.ReadMessage a0 ->
            ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (Email.ReadMessage new))) a0


names_Email_Job =
    [ "ListInbox"
    ]


choose_Email_Job put _ =
    ModelTree.apply put Email.ListInbox


tree_Email_MessageState put value =
    case value of
        Email.MessageLoading ->
            ModelTree.variant "MessageLoading" 0 (args_Email_MessageState put value) names_Email_MessageState (choose_Email_MessageState put)

        Email.MessageLoaded _ ->
            ModelTree.variant "MessageLoaded" 1 (args_Email_MessageState put value) names_Email_MessageState (choose_Email_MessageState put)

        Email.MessageFailed _ ->
            ModelTree.variant "MessageFailed" 1 (args_Email_MessageState put value) names_Email_MessageState (choose_Email_MessageState put)


args_Email_MessageState put value i =
    case value of
        Email.MessageLoading ->
            ModelTree.noChild i

        Email.MessageLoaded a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Email.MessageLoaded new))) a0

        Email.MessageFailed a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Email.MessageFailed new))) a0


names_Email_MessageState =
    [ "MessageLoading"
    ]


choose_Email_MessageState put _ =
    ModelTree.apply put Email.MessageLoading


tree_Email_Model put value =
    ModelTree.record [ "isOpen", "account", "inbox", "page", "session", "sessionCount", "error" ] (field_Email_Model put value)


field_Email_Model put value i =
    case i of
        0 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | isOpen = x })) value.isOpen

        1 ->
            ModelTree.maybe tree_Email_Account (ModelTree.Put (\x -> ModelTree.apply put { value | account = x })) value.account

        2 ->
            ModelTree.list tree_Email_Summary (ModelTree.Put (\x -> ModelTree.apply put { value | inbox = x })) value.inbox

        3 ->
            tree_Email_Page (ModelTree.Put (\x -> ModelTree.apply put { value | page = x })) value.page

        4 ->
            ModelTree.maybe tree_Email_Session (ModelTree.Put (\x -> ModelTree.apply put { value | session = x })) value.session

        5 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | sessionCount = x })) value.sessionCount

        _ ->
            ModelTree.maybe ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | error = x })) value.error


tree_Email_Page put value =
    case value of
        Email.InboxPage ->
            ModelTree.variant "InboxPage" 0 (args_Email_Page put value) names_Email_Page (choose_Email_Page put)

        Email.MessagePage _ ->
            ModelTree.variant "MessagePage" 1 (args_Email_Page put value) names_Email_Page (choose_Email_Page put)


args_Email_Page put value i =
    case value of
        Email.InboxPage ->
            ModelTree.noChild i

        Email.MessagePage a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "uid", \() -> ModelTree.int (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | uid = x1 })) value1.uid ), ( "state", \() -> tree_Email_MessageState (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | state = x1 })) value1.state ) ]) (ModelTree.Put (\new -> ModelTree.apply put (Email.MessagePage new))) a0


names_Email_Page =
    [ "InboxPage"
    ]


choose_Email_Page put _ =
    ModelTree.apply put Email.InboxPage


tree_Email_Session put value =
    ModelTree.record [ "id", "job", "stage", "buffer", "exists", "results", "startedAt" ] (field_Email_Session put value)


field_Email_Session put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | id = x })) value.id

        1 ->
            tree_Email_Job (ModelTree.Put (\x -> ModelTree.apply put { value | job = x })) value.job

        2 ->
            tree_Email_Stage (ModelTree.Put (\x -> ModelTree.apply put { value | stage = x })) value.stage

        3 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | buffer = x })) value.buffer

        4 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | exists = x })) value.exists

        5 ->
            ModelTree.list tree_Email_Imap_Fetched (ModelTree.Put (\x -> ModelTree.apply put { value | results = x })) value.results

        _ ->
            ModelTree.maybe ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | startedAt = x })) value.startedAt


tree_Email_Stage put value =
    case value of
        Email.Connecting ->
            ModelTree.variant "Connecting" 0 ModelTree.noChild names_Email_Stage (choose_Email_Stage put)

        Email.WaitingForGreeting ->
            ModelTree.variant "WaitingForGreeting" 0 ModelTree.noChild names_Email_Stage (choose_Email_Stage put)

        Email.LoggingIn ->
            ModelTree.variant "LoggingIn" 0 ModelTree.noChild names_Email_Stage (choose_Email_Stage put)

        Email.Selecting ->
            ModelTree.variant "Selecting" 0 ModelTree.noChild names_Email_Stage (choose_Email_Stage put)

        Email.Fetching ->
            ModelTree.variant "Fetching" 0 ModelTree.noChild names_Email_Stage (choose_Email_Stage put)


names_Email_Stage =
    [ "Connecting"
    , "WaitingForGreeting"
    , "LoggingIn"
    , "Selecting"
    , "Fetching"
    ]


choose_Email_Stage put i =
    case i of
        0 ->
            ModelTree.apply put Email.Connecting

        1 ->
            ModelTree.apply put Email.WaitingForGreeting

        2 ->
            ModelTree.apply put Email.LoggingIn

        3 ->
            ModelTree.apply put Email.Selecting

        _ ->
            ModelTree.apply put Email.Fetching


tree_Email_Summary put value =
    ModelTree.record [ "uid", "from", "subject", "date", "seen" ] (field_Email_Summary put value)


field_Email_Summary put value i =
    case i of
        0 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | uid = x })) value.uid

        1 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | from = x })) value.from

        2 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | subject = x })) value.subject

        3 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | date = x })) value.date

        _ ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | seen = x })) value.seen


tree_Email_Imap_Fetched put value =
    ModelTree.record [ "uid", "seen", "header", "text" ] (field_Email_Imap_Fetched put value)


field_Email_Imap_Fetched put value i =
    case i of
        0 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | uid = x })) value.uid

        1 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | seen = x })) value.seen

        2 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | header = x })) value.header

        _ ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | text = x })) value.text


tree_Email_Types_Field put value =
    case value of
        Email.Types.AddressField ->
            ModelTree.variant "AddressField" 0 ModelTree.noChild names_Email_Types_Field (choose_Email_Types_Field put)

        Email.Types.PasswordField ->
            ModelTree.variant "PasswordField" 0 ModelTree.noChild names_Email_Types_Field (choose_Email_Types_Field put)

        Email.Types.ServerField ->
            ModelTree.variant "ServerField" 0 ModelTree.noChild names_Email_Types_Field (choose_Email_Types_Field put)


names_Email_Types_Field =
    [ "AddressField"
    , "PasswordField"
    , "ServerField"
    ]


choose_Email_Types_Field put i =
    case i of
        0 ->
            ModelTree.apply put Email.Types.AddressField

        1 ->
            ModelTree.apply put Email.Types.PasswordField

        _ ->
            ModelTree.apply put Email.Types.ServerField


tree_Email_Types_UiId put value =
    case value of
        Email.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 (args_Email_Types_UiId put value) names_Email_Types_UiId (choose_Email_Types_UiId put)

        Email.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 (args_Email_Types_UiId put value) names_Email_Types_UiId (choose_Email_Types_UiId put)

        Email.Types.InputField _ ->
            ModelTree.variant "InputField" 1 (args_Email_Types_UiId put value) names_Email_Types_UiId (choose_Email_Types_UiId put)

        Email.Types.LinkButton ->
            ModelTree.variant "LinkButton" 0 (args_Email_Types_UiId put value) names_Email_Types_UiId (choose_Email_Types_UiId put)

        Email.Types.RefreshButton ->
            ModelTree.variant "RefreshButton" 0 (args_Email_Types_UiId put value) names_Email_Types_UiId (choose_Email_Types_UiId put)

        Email.Types.SignOutButton ->
            ModelTree.variant "SignOutButton" 0 (args_Email_Types_UiId put value) names_Email_Types_UiId (choose_Email_Types_UiId put)

        Email.Types.BackButton ->
            ModelTree.variant "BackButton" 0 (args_Email_Types_UiId put value) names_Email_Types_UiId (choose_Email_Types_UiId put)

        Email.Types.MessageButton _ ->
            ModelTree.variant "MessageButton" 1 (args_Email_Types_UiId put value) names_Email_Types_UiId (choose_Email_Types_UiId put)

        Email.Types.ListViewport ->
            ModelTree.variant "ListViewport" 0 (args_Email_Types_UiId put value) names_Email_Types_UiId (choose_Email_Types_UiId put)

        Email.Types.MessageViewport ->
            ModelTree.variant "MessageViewport" 0 (args_Email_Types_UiId put value) names_Email_Types_UiId (choose_Email_Types_UiId put)


args_Email_Types_UiId put value i =
    case value of
        Email.Types.OpenButton ->
            ModelTree.noChild i

        Email.Types.CloseButton ->
            ModelTree.noChild i

        Email.Types.InputField a0 ->
            tree_Email_Types_Field (ModelTree.Put (\new -> ModelTree.apply put (Email.Types.InputField new))) a0

        Email.Types.LinkButton ->
            ModelTree.noChild i

        Email.Types.RefreshButton ->
            ModelTree.noChild i

        Email.Types.SignOutButton ->
            ModelTree.noChild i

        Email.Types.BackButton ->
            ModelTree.noChild i

        Email.Types.MessageButton a0 ->
            ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (Email.Types.MessageButton new))) a0

        Email.Types.ListViewport ->
            ModelTree.noChild i

        Email.Types.MessageViewport ->
            ModelTree.noChild i


names_Email_Types_UiId =
    [ "OpenButton"
    , "CloseButton"
    , "LinkButton"
    , "RefreshButton"
    , "SignOutButton"
    , "BackButton"
    , "ListViewport"
    , "MessageViewport"
    ]


choose_Email_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put Email.Types.OpenButton

        1 ->
            ModelTree.apply put Email.Types.CloseButton

        2 ->
            ModelTree.apply put Email.Types.LinkButton

        3 ->
            ModelTree.apply put Email.Types.RefreshButton

        4 ->
            ModelTree.apply put Email.Types.SignOutButton

        5 ->
            ModelTree.apply put Email.Types.BackButton

        6 ->
            ModelTree.apply put Email.Types.ListViewport

        _ ->
            ModelTree.apply put Email.Types.MessageViewport


tree_HackerNews_HackerNewsState put value =
    case value of
        HackerNews.NotLoading ->
            ModelTree.variant "NotLoading" 0 (args_HackerNews_HackerNewsState put value) names_HackerNews_HackerNewsState (choose_HackerNews_HackerNewsState put)

        HackerNews.Loading _ ->
            ModelTree.variant "Loading" 1 (args_HackerNews_HackerNewsState put value) names_HackerNews_HackerNewsState (choose_HackerNews_HackerNewsState put)

        HackerNews.Loaded _ ->
            ModelTree.variant "Loaded" 1 (args_HackerNews_HackerNewsState put value) names_HackerNews_HackerNewsState (choose_HackerNews_HackerNewsState put)

        HackerNews.LoadFailed _ ->
            ModelTree.variant "LoadFailed" 1 (args_HackerNews_HackerNewsState put value) names_HackerNews_HackerNewsState (choose_HackerNews_HackerNewsState put)


args_HackerNews_HackerNewsState put value i =
    case value of
        HackerNews.NotLoading ->
            ModelTree.noChild i

        HackerNews.Loading a0 ->
            ModelTree.maybe (ModelTree.list tree_HackerNews_Types_Post) (ModelTree.Put (\new -> ModelTree.apply put (HackerNews.Loading new))) a0

        HackerNews.Loaded a0 ->
            ModelTree.list tree_HackerNews_Types_Post (ModelTree.Put (\new -> ModelTree.apply put (HackerNews.Loaded new))) a0

        HackerNews.LoadFailed a0 ->
            tree_Effect_HttpError (ModelTree.Put (\new -> ModelTree.apply put (HackerNews.LoadFailed new))) a0


names_HackerNews_HackerNewsState =
    [ "NotLoading"
    ]


choose_HackerNews_HackerNewsState put _ =
    ModelTree.apply put HackerNews.NotLoading


tree_HackerNews_Model put value =
    ModelTree.record [ "data", "page", "comments", "openCount", "isOpen" ] (field_HackerNews_Model put value)


field_HackerNews_Model put value i =
    case i of
        0 ->
            tree_HackerNews_HackerNewsState (ModelTree.Put (\x -> ModelTree.apply put { value | data = x })) value.data

        1 ->
            ModelTree.opaqueTree "HackerNews.Page" (ModelTree.Put (\x -> ModelTree.apply put { value | page = x })) value.page

        2 ->
            ModelTree.seqDict tree_HackerNews_Types_PostId (\put1 value1 -> ModelTree.fields [ ( "opened", \() -> ModelTree.int (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | opened = x1 })) value1.opened ), ( "state", \() -> ModelTree.opaqueTree "HackerNews.CommentsState" (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | state = x1 })) value1.state ) ]) (ModelTree.Put (\x -> ModelTree.apply put { value | comments = x })) value.comments

        3 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | openCount = x })) value.openCount

        _ ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | isOpen = x })) value.isOpen


tree_HackerNews_Types_Post put value =
    ModelTree.record [ "id", "title", "comments" ] (field_HackerNews_Types_Post put value)


field_HackerNews_Types_Post put value i =
    case i of
        0 ->
            tree_HackerNews_Types_PostId (ModelTree.Put (\x -> ModelTree.apply put { value | id = x })) value.id

        1 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | title = x })) value.title

        _ ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | comments = x })) value.comments


tree_HackerNews_Types_PostId put value =
    case value of
        HackerNews.Types.PostId _ ->
            ModelTree.variant "PostId" 1 (args_HackerNews_Types_PostId put value) [] (ModelTree.unchanged put value)


args_HackerNews_Types_PostId put value i =
    case value of
        HackerNews.Types.PostId a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (HackerNews.Types.PostId new))) a0


tree_HackerNews_Types_UiId put value =
    case value of
        HackerNews.Types.PostButton _ ->
            ModelTree.variant "PostButton" 1 (args_HackerNews_Types_UiId put value) names_HackerNews_Types_UiId (choose_HackerNews_Types_UiId put)

        HackerNews.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 (args_HackerNews_Types_UiId put value) names_HackerNews_Types_UiId (choose_HackerNews_Types_UiId put)

        HackerNews.Types.PostsViewport ->
            ModelTree.variant "PostsViewport" 0 (args_HackerNews_Types_UiId put value) names_HackerNews_Types_UiId (choose_HackerNews_Types_UiId put)

        HackerNews.Types.CommentsViewport _ ->
            ModelTree.variant "CommentsViewport" 1 (args_HackerNews_Types_UiId put value) names_HackerNews_Types_UiId (choose_HackerNews_Types_UiId put)

        HackerNews.Types.BackButton ->
            ModelTree.variant "BackButton" 0 (args_HackerNews_Types_UiId put value) names_HackerNews_Types_UiId (choose_HackerNews_Types_UiId put)

        HackerNews.Types.CommentToggle _ ->
            ModelTree.variant "CommentToggle" 1 (args_HackerNews_Types_UiId put value) names_HackerNews_Types_UiId (choose_HackerNews_Types_UiId put)

        HackerNews.Types.CommentLink ->
            ModelTree.variant "CommentLink" 0 (args_HackerNews_Types_UiId put value) names_HackerNews_Types_UiId (choose_HackerNews_Types_UiId put)


args_HackerNews_Types_UiId put value i =
    case value of
        HackerNews.Types.PostButton a0 ->
            tree_HackerNews_Types_PostId (ModelTree.Put (\new -> ModelTree.apply put (HackerNews.Types.PostButton new))) a0

        HackerNews.Types.OpenButton ->
            ModelTree.noChild i

        HackerNews.Types.PostsViewport ->
            ModelTree.noChild i

        HackerNews.Types.CommentsViewport a0 ->
            tree_HackerNews_Types_PostId (ModelTree.Put (\new -> ModelTree.apply put (HackerNews.Types.CommentsViewport new))) a0

        HackerNews.Types.BackButton ->
            ModelTree.noChild i

        HackerNews.Types.CommentToggle a0 ->
            ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (HackerNews.Types.CommentToggle new))) a0

        HackerNews.Types.CommentLink ->
            ModelTree.noChild i


names_HackerNews_Types_UiId =
    [ "OpenButton"
    , "PostsViewport"
    , "BackButton"
    , "CommentLink"
    ]


choose_HackerNews_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put HackerNews.Types.OpenButton

        1 ->
            ModelTree.apply put HackerNews.Types.PostsViewport

        2 ->
            ModelTree.apply put HackerNews.Types.BackButton

        _ ->
            ModelTree.apply put HackerNews.Types.CommentLink


tree_History_Detail put value =
    case value of
        History.DetailLoading ->
            ModelTree.variant "DetailLoading" 0 (args_History_Detail put value) names_History_Detail (choose_History_Detail put)

        History.DetailFailed _ ->
            ModelTree.variant "DetailFailed" 1 (args_History_Detail put value) names_History_Detail (choose_History_Detail put)

        History.DetailFiles _ ->
            ModelTree.variant "DetailFiles" 1 (args_History_Detail put value) names_History_Detail (choose_History_Detail put)


args_History_Detail put value i =
    case value of
        History.DetailLoading ->
            ModelTree.noChild i

        History.DetailFailed a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (History.DetailFailed new))) a0

        History.DetailFiles a0 ->
            ModelTree.list tree_History_Types_FileChange (ModelTree.Put (\new -> ModelTree.apply put (History.DetailFiles new))) a0


names_History_Detail =
    [ "DetailLoading"
    ]


choose_History_Detail put _ =
    ModelTree.apply put History.DetailLoading


tree_History_Head put value =
    ModelTree.record [ "name", "sha" ] (field_History_Head put value)


field_History_Head put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | name = x })) value.name

        _ ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | sha = x })) value.sha


tree_History_Model put value =
    ModelTree.record [ "isOpen", "generation", "waiting", "heads", "commits", "error", "selected", "details", "baseCommit", "bases", "baseGeneration", "baseWaiting" ] (field_History_Model put value)


field_History_Model put value i =
    case i of
        0 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | isOpen = x })) value.isOpen

        1 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | generation = x })) value.generation

        2 ->
            ModelTree.list (ModelTree.tuple2 ModelTree.int ModelTree.string) (ModelTree.Put (\x -> ModelTree.apply put { value | waiting = x })) value.waiting

        3 ->
            ModelTree.list tree_History_Head (ModelTree.Put (\x -> ModelTree.apply put { value | heads = x })) value.heads

        4 ->
            ModelTree.seqDict ModelTree.string tree_History_Types_Commit (ModelTree.Put (\x -> ModelTree.apply put { value | commits = x })) value.commits

        5 ->
            ModelTree.maybe ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | error = x })) value.error

        6 ->
            ModelTree.maybe ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | selected = x })) value.selected

        7 ->
            ModelTree.seqDict ModelTree.string tree_History_Detail (ModelTree.Put (\x -> ModelTree.apply put { value | details = x })) value.details

        8 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | baseCommit = x })) value.baseCommit

        9 ->
            ModelTree.seqDict ModelTree.string (ModelTree.maybe ModelTree.string) (ModelTree.Put (\x -> ModelTree.apply put { value | bases = x })) value.bases

        10 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | baseGeneration = x })) value.baseGeneration

        _ ->
            ModelTree.list (ModelTree.tuple2 ModelTree.int ModelTree.string) (ModelTree.Put (\x -> ModelTree.apply put { value | baseWaiting = x })) value.baseWaiting


tree_History_Types_Commit put value =
    ModelTree.record [ "sha", "parents", "subject", "description", "author", "time" ] (field_History_Types_Commit put value)


field_History_Types_Commit put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | sha = x })) value.sha

        1 ->
            ModelTree.list ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | parents = x })) value.parents

        2 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | subject = x })) value.subject

        3 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | description = x })) value.description

        4 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | author = x })) value.author

        _ ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | time = x })) value.time


tree_History_Types_FileChange put value =
    ModelTree.record [ "filename", "status", "patch" ] (field_History_Types_FileChange put value)


field_History_Types_FileChange put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | filename = x })) value.filename

        1 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | status = x })) value.status

        _ ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | patch = x })) value.patch


tree_History_Types_UiId put value =
    case value of
        History.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 (args_History_Types_UiId put value) names_History_Types_UiId (choose_History_Types_UiId put)

        History.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 (args_History_Types_UiId put value) names_History_Types_UiId (choose_History_Types_UiId put)

        History.Types.RefreshButton ->
            ModelTree.variant "RefreshButton" 0 (args_History_Types_UiId put value) names_History_Types_UiId (choose_History_Types_UiId put)

        History.Types.ListViewport ->
            ModelTree.variant "ListViewport" 0 (args_History_Types_UiId put value) names_History_Types_UiId (choose_History_Types_UiId put)

        History.Types.RowButton _ ->
            ModelTree.variant "RowButton" 1 (args_History_Types_UiId put value) names_History_Types_UiId (choose_History_Types_UiId put)

        History.Types.DetailViewport ->
            ModelTree.variant "DetailViewport" 0 (args_History_Types_UiId put value) names_History_Types_UiId (choose_History_Types_UiId put)


args_History_Types_UiId put value i =
    case value of
        History.Types.OpenButton ->
            ModelTree.noChild i

        History.Types.CloseButton ->
            ModelTree.noChild i

        History.Types.RefreshButton ->
            ModelTree.noChild i

        History.Types.ListViewport ->
            ModelTree.noChild i

        History.Types.RowButton a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (History.Types.RowButton new))) a0

        History.Types.DetailViewport ->
            ModelTree.noChild i


names_History_Types_UiId =
    [ "OpenButton"
    , "CloseButton"
    , "RefreshButton"
    , "ListViewport"
    , "DetailViewport"
    ]


choose_History_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put History.Types.OpenButton

        1 ->
            ModelTree.apply put History.Types.CloseButton

        2 ->
            ModelTree.apply put History.Types.RefreshButton

        3 ->
            ModelTree.apply put History.Types.ListViewport

        _ ->
            ModelTree.apply put History.Types.DetailViewport


tree_Image_Chunk put value =
    ModelTree.record [ "hash", "pixels" ] (field_Image_Chunk put value)


field_Image_Chunk put value i =
    case i of
        0 ->
            ModelTree.tuple2 ModelTree.int ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | hash = x })) value.hash

        _ ->
            ModelTree.bytes (ModelTree.Put (\x -> ModelTree.apply put { value | pixels = x })) value.pixels


tree_Image_Image put value =
    ModelTree.record [ "across", "chunks" ] (field_Image_Image put value)


field_Image_Image put value i =
    case i of
        0 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | across = x })) value.across

        _ ->
            ModelTree.array tree_Image_Chunk (ModelTree.Put (\x -> ModelTree.apply put { value | chunks = x })) value.chunks


tree_Install_Choice put value =
    case value of
        Install.InstallOn _ _ ->
            ModelTree.variant "InstallOn" 2 (args_Install_Choice put value) [] (ModelTree.unchanged put value)

        Install.UpdateOn _ ->
            ModelTree.variant "UpdateOn" 1 (args_Install_Choice put value) [] (ModelTree.unchanged put value)


args_Install_Choice put value i =
    case value of
        Install.InstallOn a0 a1 ->
            case i of
                0 ->
                    ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Install.InstallOn new a1))) a0

                _ ->
                    tree_Install_Types_Target (ModelTree.Put (\new -> ModelTree.apply put (Install.InstallOn a0 new))) a1

        Install.UpdateOn a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Install.UpdateOn new))) a0


tree_Install_Model put value =
    ModelTree.record [ "isOpen", "disks", "chosen", "keepData", "confirming", "status" ] (field_Install_Model put value)


field_Install_Model put value i =
    case i of
        0 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | isOpen = x })) value.isOpen

        1 ->
            ModelTree.maybe (ModelTree.list tree_Install_Types_Disk) (ModelTree.Put (\x -> ModelTree.apply put { value | disks = x })) value.disks

        2 ->
            ModelTree.maybe tree_Install_Choice (ModelTree.Put (\x -> ModelTree.apply put { value | chosen = x })) value.chosen

        3 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | keepData = x })) value.keepData

        4 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | confirming = x })) value.confirming

        _ ->
            ModelTree.maybe tree_Install_Types_Status (ModelTree.Put (\x -> ModelTree.apply put { value | status = x })) value.status


tree_Install_Types_Contents put value =
    case value of
        Install.Types.EfiSystem ->
            ModelTree.variant "EfiSystem" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)

        Install.Types.Ntfs ->
            ModelTree.variant "Ntfs" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)

        Install.Types.BitLocker ->
            ModelTree.variant "BitLocker" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)

        Install.Types.Ext4 ->
            ModelTree.variant "Ext4" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)

        Install.Types.Btrfs ->
            ModelTree.variant "Btrfs" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)

        Install.Types.Fat ->
            ModelTree.variant "Fat" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)

        Install.Types.Swap ->
            ModelTree.variant "Swap" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)

        Install.Types.Luks ->
            ModelTree.variant "Luks" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)

        Install.Types.MicrosoftReserved ->
            ModelTree.variant "MicrosoftReserved" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)

        Install.Types.WindowsRecovery ->
            ModelTree.variant "WindowsRecovery" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)

        Install.Types.ElmOsData ->
            ModelTree.variant "ElmOsData" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)

        Install.Types.ElmOsTools ->
            ModelTree.variant "ElmOsTools" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)

        Install.Types.Empty ->
            ModelTree.variant "Empty" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)

        Install.Types.Other ->
            ModelTree.variant "Other" 0 ModelTree.noChild names_Install_Types_Contents (choose_Install_Types_Contents put)


names_Install_Types_Contents =
    [ "EfiSystem"
    , "Ntfs"
    , "BitLocker"
    , "Ext4"
    , "Btrfs"
    , "Fat"
    , "Swap"
    , "Luks"
    , "MicrosoftReserved"
    , "WindowsRecovery"
    , "ElmOsData"
    , "ElmOsTools"
    , "Empty"
    , "Other"
    ]


choose_Install_Types_Contents put i =
    case i of
        0 ->
            ModelTree.apply put Install.Types.EfiSystem

        1 ->
            ModelTree.apply put Install.Types.Ntfs

        2 ->
            ModelTree.apply put Install.Types.BitLocker

        3 ->
            ModelTree.apply put Install.Types.Ext4

        4 ->
            ModelTree.apply put Install.Types.Btrfs

        5 ->
            ModelTree.apply put Install.Types.Fat

        6 ->
            ModelTree.apply put Install.Types.Swap

        7 ->
            ModelTree.apply put Install.Types.Luks

        8 ->
            ModelTree.apply put Install.Types.MicrosoftReserved

        9 ->
            ModelTree.apply put Install.Types.WindowsRecovery

        10 ->
            ModelTree.apply put Install.Types.ElmOsData

        11 ->
            ModelTree.apply put Install.Types.ElmOsTools

        12 ->
            ModelTree.apply put Install.Types.Empty

        _ ->
            ModelTree.apply put Install.Types.Other


tree_Install_Types_Disk put value =
    ModelTree.record [ "name", "model", "bytes", "usb", "booted", "busy", "installed", "layout", "table", "regions" ] (field_Install_Types_Disk put value)


field_Install_Types_Disk put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | name = x })) value.name

        1 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | model = x })) value.model

        2 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | bytes = x })) value.bytes

        3 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | usb = x })) value.usb

        4 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | booted = x })) value.booted

        5 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | busy = x })) value.busy

        6 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | installed = x })) value.installed

        7 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | layout = x })) value.layout

        8 ->
            tree_Install_Types_Table (ModelTree.Put (\x -> ModelTree.apply put { value | table = x })) value.table

        _ ->
            ModelTree.list tree_Install_Types_Region (ModelTree.Put (\x -> ModelTree.apply put { value | regions = x })) value.regions


tree_Install_Types_Partition put value =
    ModelTree.record [ "number", "name", "contents" ] (field_Install_Types_Partition put value)


field_Install_Types_Partition put value i =
    case i of
        0 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | number = x })) value.number

        1 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | name = x })) value.name

        _ ->
            tree_Install_Types_Contents (ModelTree.Put (\x -> ModelTree.apply put { value | contents = x })) value.contents


tree_Install_Types_Region put value =
    ModelTree.record [ "start", "bytes", "partition" ] (field_Install_Types_Region put value)


field_Install_Types_Region put value i =
    case i of
        0 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | start = x })) value.start

        1 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | bytes = x })) value.bytes

        _ ->
            ModelTree.maybe tree_Install_Types_Partition (ModelTree.Put (\x -> ModelTree.apply put { value | partition = x })) value.partition


tree_Install_Types_Status put value =
    case value of
        Install.Types.Running _ ->
            ModelTree.variant "Running" 1 (args_Install_Types_Status put value) [] (ModelTree.unchanged put value)

        Install.Types.Failed _ ->
            ModelTree.variant "Failed" 1 (args_Install_Types_Status put value) [] (ModelTree.unchanged put value)

        Install.Types.Installed _ ->
            ModelTree.variant "Installed" 1 (args_Install_Types_Status put value) [] (ModelTree.unchanged put value)


args_Install_Types_Status put value i =
    case value of
        Install.Types.Running a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "step", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | step = x1 })) value1.step ), ( "done", \() -> ModelTree.float (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | done = x1 })) value1.done ) ]) (ModelTree.Put (\new -> ModelTree.apply put (Install.Types.Running new))) a0

        Install.Types.Failed a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "step", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | step = x1 })) value1.step ), ( "message", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | message = x1 })) value1.message ), ( "wrote", \() -> ModelTree.bool (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | wrote = x1 })) value1.wrote ) ]) (ModelTree.Put (\new -> ModelTree.apply put (Install.Types.Failed new))) a0

        Install.Types.Installed a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "grub", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | grub = x1 })) value1.grub ) ]) (ModelTree.Put (\new -> ModelTree.apply put (Install.Types.Installed new))) a0


tree_Install_Types_Table put value =
    case value of
        Install.Types.Gpt ->
            ModelTree.variant "Gpt" 0 ModelTree.noChild names_Install_Types_Table (choose_Install_Types_Table put)

        Install.Types.Mbr ->
            ModelTree.variant "Mbr" 0 ModelTree.noChild names_Install_Types_Table (choose_Install_Types_Table put)

        Install.Types.NoTable ->
            ModelTree.variant "NoTable" 0 ModelTree.noChild names_Install_Types_Table (choose_Install_Types_Table put)


names_Install_Types_Table =
    [ "Gpt"
    , "Mbr"
    , "NoTable"
    ]


choose_Install_Types_Table put i =
    case i of
        0 ->
            ModelTree.apply put Install.Types.Gpt

        1 ->
            ModelTree.apply put Install.Types.Mbr

        _ ->
            ModelTree.apply put Install.Types.NoTable


tree_Install_Types_Target put value =
    case value of
        Install.Types.FreeSpace _ ->
            ModelTree.variant "FreeSpace" 1 (args_Install_Types_Target put value) names_Install_Types_Target (choose_Install_Types_Target put)

        Install.Types.InPartition _ ->
            ModelTree.variant "InPartition" 1 (args_Install_Types_Target put value) names_Install_Types_Target (choose_Install_Types_Target put)

        Install.Types.WholeDisk ->
            ModelTree.variant "WholeDisk" 0 (args_Install_Types_Target put value) names_Install_Types_Target (choose_Install_Types_Target put)


args_Install_Types_Target put value i =
    case value of
        Install.Types.FreeSpace a0 ->
            ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (Install.Types.FreeSpace new))) a0

        Install.Types.InPartition a0 ->
            ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (Install.Types.InPartition new))) a0

        Install.Types.WholeDisk ->
            ModelTree.noChild i


names_Install_Types_Target =
    [ "WholeDisk"
    ]


choose_Install_Types_Target put _ =
    ModelTree.apply put Install.Types.WholeDisk


tree_Install_Types_UiId put value =
    case value of
        Install.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 (args_Install_Types_UiId put value) names_Install_Types_UiId (choose_Install_Types_UiId put)

        Install.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 (args_Install_Types_UiId put value) names_Install_Types_UiId (choose_Install_Types_UiId put)

        Install.Types.RefreshButton ->
            ModelTree.variant "RefreshButton" 0 (args_Install_Types_UiId put value) names_Install_Types_UiId (choose_Install_Types_UiId put)

        Install.Types.RegionButton _ _ ->
            ModelTree.variant "RegionButton" 2 (args_Install_Types_UiId put value) names_Install_Types_UiId (choose_Install_Types_UiId put)

        Install.Types.WholeDiskButton _ ->
            ModelTree.variant "WholeDiskButton" 1 (args_Install_Types_UiId put value) names_Install_Types_UiId (choose_Install_Types_UiId put)

        Install.Types.UpdateButton _ ->
            ModelTree.variant "UpdateButton" 1 (args_Install_Types_UiId put value) names_Install_Types_UiId (choose_Install_Types_UiId put)

        Install.Types.KeepDataButton ->
            ModelTree.variant "KeepDataButton" 0 (args_Install_Types_UiId put value) names_Install_Types_UiId (choose_Install_Types_UiId put)

        Install.Types.InstallButton ->
            ModelTree.variant "InstallButton" 0 (args_Install_Types_UiId put value) names_Install_Types_UiId (choose_Install_Types_UiId put)

        Install.Types.ConfirmButton ->
            ModelTree.variant "ConfirmButton" 0 (args_Install_Types_UiId put value) names_Install_Types_UiId (choose_Install_Types_UiId put)

        Install.Types.CancelButton ->
            ModelTree.variant "CancelButton" 0 (args_Install_Types_UiId put value) names_Install_Types_UiId (choose_Install_Types_UiId put)

        Install.Types.DoneButton ->
            ModelTree.variant "DoneButton" 0 (args_Install_Types_UiId put value) names_Install_Types_UiId (choose_Install_Types_UiId put)

        Install.Types.ListViewport ->
            ModelTree.variant "ListViewport" 0 (args_Install_Types_UiId put value) names_Install_Types_UiId (choose_Install_Types_UiId put)


args_Install_Types_UiId put value i =
    case value of
        Install.Types.OpenButton ->
            ModelTree.noChild i

        Install.Types.CloseButton ->
            ModelTree.noChild i

        Install.Types.RefreshButton ->
            ModelTree.noChild i

        Install.Types.RegionButton a0 a1 ->
            case i of
                0 ->
                    ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Install.Types.RegionButton new a1))) a0

                _ ->
                    ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (Install.Types.RegionButton a0 new))) a1

        Install.Types.WholeDiskButton a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Install.Types.WholeDiskButton new))) a0

        Install.Types.UpdateButton a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Install.Types.UpdateButton new))) a0

        Install.Types.KeepDataButton ->
            ModelTree.noChild i

        Install.Types.InstallButton ->
            ModelTree.noChild i

        Install.Types.ConfirmButton ->
            ModelTree.noChild i

        Install.Types.CancelButton ->
            ModelTree.noChild i

        Install.Types.DoneButton ->
            ModelTree.noChild i

        Install.Types.ListViewport ->
            ModelTree.noChild i


names_Install_Types_UiId =
    [ "OpenButton"
    , "CloseButton"
    , "RefreshButton"
    , "KeepDataButton"
    , "InstallButton"
    , "ConfirmButton"
    , "CancelButton"
    , "DoneButton"
    , "ListViewport"
    ]


choose_Install_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put Install.Types.OpenButton

        1 ->
            ModelTree.apply put Install.Types.CloseButton

        2 ->
            ModelTree.apply put Install.Types.RefreshButton

        3 ->
            ModelTree.apply put Install.Types.KeepDataButton

        4 ->
            ModelTree.apply put Install.Types.InstallButton

        5 ->
            ModelTree.apply put Install.Types.ConfirmButton

        6 ->
            ModelTree.apply put Install.Types.CancelButton

        7 ->
            ModelTree.apply put Install.Types.DoneButton

        _ ->
            ModelTree.apply put Install.Types.ListViewport


tree_Main_Model put value =
    ModelTree.record [ "displays", "appDisplays", "mouse", "colorIndex", "pressed", "renderer", "stats", "lastFrame", "frameIntervals", "frames", "lazyCache", "imageCache", "shift", "ctrl", "alt", "clipboard", "selectingText", "network", "weather", "lastSnapshot", "time", "utcOffsetMinutes", "geoUrl", "weatherUrl", "system", "bootInfo", "brightness", "aboutOpen", "newsOpen", "news", "hackerNews", "email", "webViewer", "asciiCollab", "calculator", "calculatorOpen", "ticTacToe", "ticTacToeOpen", "paint", "confirmPower", "editorOpen", "code", "debugOpen", "networkOpen", "weatherOpen", "upgradingTo", "reflashNeeded", "uiState", "showUiBorders", "inspected", "screenshotViewer", "install", "history", "modelViewer", "takingScreenshot", "screenshots", "testFacts" ] (field_Main_Model put value)


field_Main_Model put value i =
    case i of
        0 ->
            ModelTree.list tree_Display_Display (ModelTree.Put (\x -> ModelTree.apply put { value | displays = x })) value.displays

        1 ->
            ModelTree.seqDict (ModelTree.opaqueTree "Main.App") ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | appDisplays = x })) value.appDisplays

        2 ->
            tree_Coord_Coord (ModelTree.Put (\x -> ModelTree.apply put { value | mouse = x })) value.mouse

        3 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | colorIndex = x })) value.colorIndex

        4 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | pressed = x })) value.pressed

        5 ->
            ModelTree.maybe tree_DebugInfo_Types_RendererInfo (ModelTree.Put (\x -> ModelTree.apply put { value | renderer = x })) value.renderer

        6 ->
            ModelTree.maybe tree_DebugInfo_Types_SystemStats (ModelTree.Put (\x -> ModelTree.apply put { value | stats = x })) value.stats

        7 ->
            ModelTree.maybe ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | lastFrame = x })) value.lastFrame

        8 ->
            ModelTree.list ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | frameIntervals = x })) value.frameIntervals

        9 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | frames = x })) value.frames

        10 ->
            ModelTree.opaqueTree "Ui.LazyCache (not saved)" (ModelTree.Put (\x -> ModelTree.apply put { value | lazyCache = x })) value.lazyCache

        11 ->
            ModelTree.opaqueTree "ImageCache.ImageCache (not saved)" (ModelTree.Put (\x -> ModelTree.apply put { value | imageCache = x })) value.imageCache

        12 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | shift = x })) value.shift

        13 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | ctrl = x })) value.ctrl

        14 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | alt = x })) value.alt

        15 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | clipboard = x })) value.clipboard

        16 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | selectingText = x })) value.selectingText

        17 ->
            tree_Network_Network (ModelTree.Put (\x -> ModelTree.apply put { value | network = x })) value.network

        18 ->
            tree_Weather_WeatherState (ModelTree.Put (\x -> ModelTree.apply put { value | weather = x })) value.weather

        19 ->
            ModelTree.maybe (\put1 value1 -> ModelTree.fields [ ( "bytes", \() -> ModelTree.int (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | bytes = x1 })) value1.bytes ), ( "time", \() -> ModelTree.maybe ModelTree.posix (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | time = x1 })) value1.time ) ]) (ModelTree.Put (\x -> ModelTree.apply put { value | lastSnapshot = x })) value.lastSnapshot

        20 ->
            ModelTree.maybe ModelTree.posix (ModelTree.Put (\x -> ModelTree.apply put { value | time = x })) value.time

        21 ->
            ModelTree.maybe ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | utcOffsetMinutes = x })) value.utcOffsetMinutes

        22 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | geoUrl = x })) value.geoUrl

        23 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | weatherUrl = x })) value.weatherUrl

        24 ->
            ModelTree.maybe tree_About_Types_SystemInfo (ModelTree.Put (\x -> ModelTree.apply put { value | system = x })) value.system

        25 ->
            tree_BootInfo_Model (ModelTree.Put (\x -> ModelTree.apply put { value | bootInfo = x })) value.bootInfo

        26 ->
            tree_Brightness_Model (ModelTree.Put (\x -> ModelTree.apply put { value | brightness = x })) value.brightness

        27 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | aboutOpen = x })) value.aboutOpen

        28 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | newsOpen = x })) value.newsOpen

        29 ->
            tree_News_Types_NewsState (ModelTree.Put (\x -> ModelTree.apply put { value | news = x })) value.news

        30 ->
            tree_HackerNews_Model (ModelTree.Put (\x -> ModelTree.apply put { value | hackerNews = x })) value.hackerNews

        31 ->
            tree_Email_Model (ModelTree.Put (\x -> ModelTree.apply put { value | email = x })) value.email

        32 ->
            tree_WebViewer_Model (ModelTree.Put (\x -> ModelTree.apply put { value | webViewer = x })) value.webViewer

        33 ->
            tree_AsciiCollab_Model (ModelTree.Put (\x -> ModelTree.apply put { value | asciiCollab = x })) value.asciiCollab

        34 ->
            tree_Calculator_Model (ModelTree.Put (\x -> ModelTree.apply put { value | calculator = x })) value.calculator

        35 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | calculatorOpen = x })) value.calculatorOpen

        36 ->
            tree_TicTacToe_Model (ModelTree.Put (\x -> ModelTree.apply put { value | ticTacToe = x })) value.ticTacToe

        37 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | ticTacToeOpen = x })) value.ticTacToeOpen

        38 ->
            tree_Paint_Model (ModelTree.Put (\x -> ModelTree.apply put { value | paint = x })) value.paint

        39 ->
            ModelTree.maybe (ModelTree.opaqueTree "Main.PowerAction") (ModelTree.Put (\x -> ModelTree.apply put { value | confirmPower = x })) value.confirmPower

        40 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | editorOpen = x })) value.editorOpen

        41 ->
            tree_Code_Model (ModelTree.Put (\x -> ModelTree.apply put { value | code = x })) value.code

        42 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | debugOpen = x })) value.debugOpen

        43 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | networkOpen = x })) value.networkOpen

        44 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | weatherOpen = x })) value.weatherOpen

        45 ->
            ModelTree.maybe ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | upgradingTo = x })) value.upgradingTo

        46 ->
            ModelTree.maybe ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | reflashNeeded = x })) value.reflashNeeded

        47 ->
            tree_Ui_Model tree_UiId_UiId (ModelTree.Put (\x -> ModelTree.apply put { value | uiState = x })) value.uiState

        48 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | showUiBorders = x })) value.showUiBorders

        49 ->
            ModelTree.maybe (\put1 value1 -> ModelTree.fields [ ( "display", \() -> ModelTree.int (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | display = x1 })) value1.display ), ( "sources", \() -> ModelTree.list tree_Ui_Source (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | sources = x1 })) value1.sources ) ]) (ModelTree.Put (\x -> ModelTree.apply put { value | inspected = x })) value.inspected

        50 ->
            tree_ScreenshotViewer_Model (ModelTree.Put (\x -> ModelTree.apply put { value | screenshotViewer = x })) value.screenshotViewer

        51 ->
            tree_Install_Model (ModelTree.Put (\x -> ModelTree.apply put { value | install = x })) value.install

        52 ->
            tree_History_Model (ModelTree.Put (\x -> ModelTree.apply put { value | history = x })) value.history

        53 ->
            tree_ModelViewer_Model (ModelTree.Put (\x -> ModelTree.apply put { value | modelViewer = x })) value.modelViewer

        54 ->
            ModelTree.maybe tree_Main_ScreenshotPreview (ModelTree.Put (\x -> ModelTree.apply put { value | takingScreenshot = x })) value.takingScreenshot

        55 ->
            ModelTree.list tree_Ui_Screenshot (ModelTree.Put (\x -> ModelTree.apply put { value | screenshots = x })) value.screenshots

        _ ->
            ModelTree.maybe (ModelTree.list (ModelTree.tuple2 ModelTree.string ModelTree.string)) (ModelTree.Put (\x -> ModelTree.apply put { value | testFacts = x })) value.testFacts


tree_Main_ScreenshotPreview put value =
    ModelTree.record [ "mouse", "bounds", "depth" ] (field_Main_ScreenshotPreview put value)


field_Main_ScreenshotPreview put value i =
    case i of
        0 ->
            tree_Coord_Coord (ModelTree.Put (\x -> ModelTree.apply put { value | mouse = x })) value.mouse

        1 ->
            tree_Bounds_Bounds (ModelTree.Put (\x -> ModelTree.apply put { value | bounds = x })) value.bounds

        _ ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | depth = x })) value.depth


tree_ModelViewer_Model put value =
    ModelTree.record [ "isOpen", "expanded", "editing" ] (field_ModelViewer_Model put value)


field_ModelViewer_Model put value i =
    case i of
        0 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | isOpen = x })) value.isOpen

        1 ->
            ModelTree.set (ModelTree.list ModelTree.int) (ModelTree.Put (\x -> ModelTree.apply put { value | expanded = x })) value.expanded

        _ ->
            ModelTree.maybe (\put1 value1 -> ModelTree.fields [ ( "path", \() -> ModelTree.list ModelTree.int (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | path = x1 })) value1.path ), ( "refused", \() -> ModelTree.bool (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | refused = x1 })) value1.refused ) ]) (ModelTree.Put (\x -> ModelTree.apply put { value | editing = x })) value.editing


tree_ModelViewer_Types_UiId put value =
    case value of
        ModelViewer.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 (args_ModelViewer_Types_UiId put value) names_ModelViewer_Types_UiId (choose_ModelViewer_Types_UiId put)

        ModelViewer.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 (args_ModelViewer_Types_UiId put value) names_ModelViewer_Types_UiId (choose_ModelViewer_Types_UiId put)

        ModelViewer.Types.ListViewport ->
            ModelTree.variant "ListViewport" 0 (args_ModelViewer_Types_UiId put value) names_ModelViewer_Types_UiId (choose_ModelViewer_Types_UiId put)

        ModelViewer.Types.Row _ ->
            ModelTree.variant "Row" 1 (args_ModelViewer_Types_UiId put value) names_ModelViewer_Types_UiId (choose_ModelViewer_Types_UiId put)

        ModelViewer.Types.Choice _ _ ->
            ModelTree.variant "Choice" 2 (args_ModelViewer_Types_UiId put value) names_ModelViewer_Types_UiId (choose_ModelViewer_Types_UiId put)

        ModelViewer.Types.EditInput ->
            ModelTree.variant "EditInput" 0 (args_ModelViewer_Types_UiId put value) names_ModelViewer_Types_UiId (choose_ModelViewer_Types_UiId put)

        ModelViewer.Types.SaveButton ->
            ModelTree.variant "SaveButton" 0 (args_ModelViewer_Types_UiId put value) names_ModelViewer_Types_UiId (choose_ModelViewer_Types_UiId put)

        ModelViewer.Types.CancelButton ->
            ModelTree.variant "CancelButton" 0 (args_ModelViewer_Types_UiId put value) names_ModelViewer_Types_UiId (choose_ModelViewer_Types_UiId put)


args_ModelViewer_Types_UiId put value i =
    case value of
        ModelViewer.Types.OpenButton ->
            ModelTree.noChild i

        ModelViewer.Types.CloseButton ->
            ModelTree.noChild i

        ModelViewer.Types.ListViewport ->
            ModelTree.noChild i

        ModelViewer.Types.Row a0 ->
            ModelTree.list ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (ModelViewer.Types.Row new))) a0

        ModelViewer.Types.Choice a0 a1 ->
            case i of
                0 ->
                    ModelTree.list ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (ModelViewer.Types.Choice new a1))) a0

                _ ->
                    ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (ModelViewer.Types.Choice a0 new))) a1

        ModelViewer.Types.EditInput ->
            ModelTree.noChild i

        ModelViewer.Types.SaveButton ->
            ModelTree.noChild i

        ModelViewer.Types.CancelButton ->
            ModelTree.noChild i


names_ModelViewer_Types_UiId =
    [ "OpenButton"
    , "CloseButton"
    , "ListViewport"
    , "EditInput"
    , "SaveButton"
    , "CancelButton"
    ]


choose_ModelViewer_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put ModelViewer.Types.OpenButton

        1 ->
            ModelTree.apply put ModelViewer.Types.CloseButton

        2 ->
            ModelTree.apply put ModelViewer.Types.ListViewport

        3 ->
            ModelTree.apply put ModelViewer.Types.EditInput

        4 ->
            ModelTree.apply put ModelViewer.Types.SaveButton

        _ ->
            ModelTree.apply put ModelViewer.Types.CancelButton


tree_Network_Network put value =
    ModelTree.record [ "wifiDevice", "networks", "scanning", "wifiStatus", "wired", "selected", "savedWifiPasswords", "showPassword" ] (field_Network_Network put value)


field_Network_Network put value i =
    case i of
        0 ->
            tree_Network_WifiDevice (ModelTree.Put (\x -> ModelTree.apply put { value | wifiDevice = x })) value.wifiDevice

        1 ->
            ModelTree.list tree_Network_WifiNetwork (ModelTree.Put (\x -> ModelTree.apply put { value | networks = x })) value.networks

        2 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | scanning = x })) value.scanning

        3 ->
            tree_Network_WifiStatus (ModelTree.Put (\x -> ModelTree.apply put { value | wifiStatus = x })) value.wifiStatus

        4 ->
            ModelTree.list tree_Network_WiredLink (ModelTree.Put (\x -> ModelTree.apply put { value | wired = x })) value.wired

        5 ->
            ModelTree.maybe tree_Network_WifiNetwork (ModelTree.Put (\x -> ModelTree.apply put { value | selected = x })) value.selected

        6 ->
            ModelTree.seqDict (ModelTree.opaqueTree "Network.Types.Ssid") (ModelTree.opaqueTree "Network.Wpa2Password.Wpa2Password") (ModelTree.Put (\x -> ModelTree.apply put { value | savedWifiPasswords = x })) value.savedWifiPasswords

        _ ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | showPassword = x })) value.showPassword


tree_Network_WifiDevice put value =
    case value of
        Network.Unknown ->
            ModelTree.variant "Unknown" 0 (args_Network_WifiDevice put value) names_Network_WifiDevice (choose_Network_WifiDevice put)

        Network.NoCard ->
            ModelTree.variant "NoCard" 0 (args_Network_WifiDevice put value) names_Network_WifiDevice (choose_Network_WifiDevice put)

        Network.Card _ ->
            ModelTree.variant "Card" 1 (args_Network_WifiDevice put value) names_Network_WifiDevice (choose_Network_WifiDevice put)


args_Network_WifiDevice put value i =
    case value of
        Network.Unknown ->
            ModelTree.noChild i

        Network.NoCard ->
            ModelTree.noChild i

        Network.Card a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (Network.Card new))) a0


names_Network_WifiDevice =
    [ "Unknown"
    , "NoCard"
    ]


choose_Network_WifiDevice put i =
    case i of
        0 ->
            ModelTree.apply put Network.Unknown

        _ ->
            ModelTree.apply put Network.NoCard


tree_Network_WifiNetwork put value =
    ModelTree.record [ "ssid", "signal", "security" ] (field_Network_WifiNetwork put value)


field_Network_WifiNetwork put value i =
    case i of
        0 ->
            ModelTree.opaqueTree "Network.Types.Ssid" (ModelTree.Put (\x -> ModelTree.apply put { value | ssid = x })) value.ssid

        1 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | signal = x })) value.signal

        _ ->
            tree_Network_WifiSecurity (ModelTree.Put (\x -> ModelTree.apply put { value | security = x })) value.security


tree_Network_WifiSecurity put value =
    case value of
        Network.Open ->
            ModelTree.variant "Open" 0 ModelTree.noChild names_Network_WifiSecurity (choose_Network_WifiSecurity put)

        Network.Wpa ->
            ModelTree.variant "Wpa" 0 ModelTree.noChild names_Network_WifiSecurity (choose_Network_WifiSecurity put)

        Network.Enterprise ->
            ModelTree.variant "Enterprise" 0 ModelTree.noChild names_Network_WifiSecurity (choose_Network_WifiSecurity put)

        Network.Wep ->
            ModelTree.variant "Wep" 0 ModelTree.noChild names_Network_WifiSecurity (choose_Network_WifiSecurity put)

        Network.Wpa3 ->
            ModelTree.variant "Wpa3" 0 ModelTree.noChild names_Network_WifiSecurity (choose_Network_WifiSecurity put)


names_Network_WifiSecurity =
    [ "Open"
    , "Wpa"
    , "Enterprise"
    , "Wep"
    , "Wpa3"
    ]


choose_Network_WifiSecurity put i =
    case i of
        0 ->
            ModelTree.apply put Network.Open

        1 ->
            ModelTree.apply put Network.Wpa

        2 ->
            ModelTree.apply put Network.Enterprise

        3 ->
            ModelTree.apply put Network.Wep

        _ ->
            ModelTree.apply put Network.Wpa3


tree_Network_WifiState put value =
    case value of
        Network.Idle ->
            ModelTree.variant "Idle" 0 ModelTree.noChild names_Network_WifiState (choose_Network_WifiState put)

        Network.Connecting ->
            ModelTree.variant "Connecting" 0 ModelTree.noChild names_Network_WifiState (choose_Network_WifiState put)

        Network.Dhcp ->
            ModelTree.variant "Dhcp" 0 ModelTree.noChild names_Network_WifiState (choose_Network_WifiState put)

        Network.Connected ->
            ModelTree.variant "Connected" 0 ModelTree.noChild names_Network_WifiState (choose_Network_WifiState put)

        Network.Failed ->
            ModelTree.variant "Failed" 0 ModelTree.noChild names_Network_WifiState (choose_Network_WifiState put)


names_Network_WifiState =
    [ "Idle"
    , "Connecting"
    , "Dhcp"
    , "Connected"
    , "Failed"
    ]


choose_Network_WifiState put i =
    case i of
        0 ->
            ModelTree.apply put Network.Idle

        1 ->
            ModelTree.apply put Network.Connecting

        2 ->
            ModelTree.apply put Network.Dhcp

        3 ->
            ModelTree.apply put Network.Connected

        _ ->
            ModelTree.apply put Network.Failed


tree_Network_WifiStatus put value =
    ModelTree.record [ "state", "ssid", "ip", "error" ] (field_Network_WifiStatus put value)


field_Network_WifiStatus put value i =
    case i of
        0 ->
            tree_Network_WifiState (ModelTree.Put (\x -> ModelTree.apply put { value | state = x })) value.state

        1 ->
            ModelTree.opaqueTree "Network.Types.Ssid" (ModelTree.Put (\x -> ModelTree.apply put { value | ssid = x })) value.ssid

        2 ->
            ModelTree.maybe (ModelTree.opaqueTree "Network.Ipv4.Ipv4") (ModelTree.Put (\x -> ModelTree.apply put { value | ip = x })) value.ip

        _ ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | error = x })) value.error


tree_Network_WiredLink put value =
    ModelTree.record [ "name", "state", "ip" ] (field_Network_WiredLink put value)


field_Network_WiredLink put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | name = x })) value.name

        1 ->
            tree_Network_WiredState (ModelTree.Put (\x -> ModelTree.apply put { value | state = x })) value.state

        _ ->
            ModelTree.maybe (ModelTree.opaqueTree "Network.Ipv4.Ipv4") (ModelTree.Put (\x -> ModelTree.apply put { value | ip = x })) value.ip


tree_Network_WiredState put value =
    case value of
        Network.WiredNoCable ->
            ModelTree.variant "WiredNoCable" 0 ModelTree.noChild names_Network_WiredState (choose_Network_WiredState put)

        Network.WiredDhcp ->
            ModelTree.variant "WiredDhcp" 0 ModelTree.noChild names_Network_WiredState (choose_Network_WiredState put)

        Network.WiredConnected ->
            ModelTree.variant "WiredConnected" 0 ModelTree.noChild names_Network_WiredState (choose_Network_WiredState put)

        Network.WiredFailed ->
            ModelTree.variant "WiredFailed" 0 ModelTree.noChild names_Network_WiredState (choose_Network_WiredState put)


names_Network_WiredState =
    [ "WiredNoCable"
    , "WiredDhcp"
    , "WiredConnected"
    , "WiredFailed"
    ]


choose_Network_WiredState put i =
    case i of
        0 ->
            ModelTree.apply put Network.WiredNoCable

        1 ->
            ModelTree.apply put Network.WiredDhcp

        2 ->
            ModelTree.apply put Network.WiredConnected

        _ ->
            ModelTree.apply put Network.WiredFailed


tree_Network_Types_UiId put value =
    case value of
        Network.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 (args_Network_Types_UiId put value) names_Network_Types_UiId (choose_Network_Types_UiId put)

        Network.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 (args_Network_Types_UiId put value) names_Network_Types_UiId (choose_Network_Types_UiId put)

        Network.Types.RefreshButton ->
            ModelTree.variant "RefreshButton" 0 (args_Network_Types_UiId put value) names_Network_Types_UiId (choose_Network_Types_UiId put)

        Network.Types.NetworkButton _ ->
            ModelTree.variant "NetworkButton" 1 (args_Network_Types_UiId put value) names_Network_Types_UiId (choose_Network_Types_UiId put)

        Network.Types.PasswordInput ->
            ModelTree.variant "PasswordInput" 0 (args_Network_Types_UiId put value) names_Network_Types_UiId (choose_Network_Types_UiId put)

        Network.Types.ShowPasswordButton ->
            ModelTree.variant "ShowPasswordButton" 0 (args_Network_Types_UiId put value) names_Network_Types_UiId (choose_Network_Types_UiId put)

        Network.Types.ConnectButton ->
            ModelTree.variant "ConnectButton" 0 (args_Network_Types_UiId put value) names_Network_Types_UiId (choose_Network_Types_UiId put)

        Network.Types.DisconnectButton ->
            ModelTree.variant "DisconnectButton" 0 (args_Network_Types_UiId put value) names_Network_Types_UiId (choose_Network_Types_UiId put)

        Network.Types.NetworkListViewport ->
            ModelTree.variant "NetworkListViewport" 0 (args_Network_Types_UiId put value) names_Network_Types_UiId (choose_Network_Types_UiId put)


args_Network_Types_UiId put value i =
    case value of
        Network.Types.OpenButton ->
            ModelTree.noChild i

        Network.Types.CloseButton ->
            ModelTree.noChild i

        Network.Types.RefreshButton ->
            ModelTree.noChild i

        Network.Types.NetworkButton a0 ->
            ModelTree.opaqueTree "Network.Types.Ssid" (ModelTree.Put (\new -> ModelTree.apply put (Network.Types.NetworkButton new))) a0

        Network.Types.PasswordInput ->
            ModelTree.noChild i

        Network.Types.ShowPasswordButton ->
            ModelTree.noChild i

        Network.Types.ConnectButton ->
            ModelTree.noChild i

        Network.Types.DisconnectButton ->
            ModelTree.noChild i

        Network.Types.NetworkListViewport ->
            ModelTree.noChild i


names_Network_Types_UiId =
    [ "OpenButton"
    , "CloseButton"
    , "RefreshButton"
    , "PasswordInput"
    , "ShowPasswordButton"
    , "ConnectButton"
    , "DisconnectButton"
    , "NetworkListViewport"
    ]


choose_Network_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put Network.Types.OpenButton

        1 ->
            ModelTree.apply put Network.Types.CloseButton

        2 ->
            ModelTree.apply put Network.Types.RefreshButton

        3 ->
            ModelTree.apply put Network.Types.PasswordInput

        4 ->
            ModelTree.apply put Network.Types.ShowPasswordButton

        5 ->
            ModelTree.apply put Network.Types.ConnectButton

        6 ->
            ModelTree.apply put Network.Types.DisconnectButton

        _ ->
            ModelTree.apply put Network.Types.NetworkListViewport


tree_News_Types_Day put value =
    ModelTree.record [ "date", "topics" ] (field_News_Types_Day put value)


field_News_Types_Day put value i =
    case i of
        0 ->
            ModelTree.date (ModelTree.Put (\x -> ModelTree.apply put { value | date = x })) value.date

        _ ->
            ModelTree.list tree_News_Types_Topic (ModelTree.Put (\x -> ModelTree.apply put { value | topics = x })) value.topics


tree_News_Types_Emphasis put value =
    case value of
        News.Types.ToggleItalic ->
            ModelTree.variant "ToggleItalic" 0 ModelTree.noChild names_News_Types_Emphasis (choose_News_Types_Emphasis put)

        News.Types.ToggleBold ->
            ModelTree.variant "ToggleBold" 0 ModelTree.noChild names_News_Types_Emphasis (choose_News_Types_Emphasis put)

        News.Types.ToggleBoldItalic ->
            ModelTree.variant "ToggleBoldItalic" 0 ModelTree.noChild names_News_Types_Emphasis (choose_News_Types_Emphasis put)


names_News_Types_Emphasis =
    [ "ToggleItalic"
    , "ToggleBold"
    , "ToggleBoldItalic"
    ]


choose_News_Types_Emphasis put i =
    case i of
        0 ->
            ModelTree.apply put News.Types.ToggleItalic

        1 ->
            ModelTree.apply put News.Types.ToggleBold

        _ ->
            ModelTree.apply put News.Types.ToggleBoldItalic


tree_News_Types_Inline put value =
    case value of
        News.Types.Text _ ->
            ModelTree.variant "Text" 1 (args_News_Types_Inline put value) [] (ModelTree.unchanged put value)

        News.Types.WikiLink _ ->
            ModelTree.variant "WikiLink" 1 (args_News_Types_Inline put value) [] (ModelTree.unchanged put value)

        News.Types.ExternalLink _ ->
            ModelTree.variant "ExternalLink" 1 (args_News_Types_Inline put value) [] (ModelTree.unchanged put value)

        News.Types.Toggle _ ->
            ModelTree.variant "Toggle" 1 (args_News_Types_Inline put value) [] (ModelTree.unchanged put value)


args_News_Types_Inline put value i =
    case value of
        News.Types.Text a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (News.Types.Text new))) a0

        News.Types.WikiLink a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "article", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | article = x1 })) value1.article ), ( "label", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | label = x1 })) value1.label ) ]) (ModelTree.Put (\new -> ModelTree.apply put (News.Types.WikiLink new))) a0

        News.Types.ExternalLink a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "url", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | url = x1 })) value1.url ), ( "label", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | label = x1 })) value1.label ) ]) (ModelTree.Put (\new -> ModelTree.apply put (News.Types.ExternalLink new))) a0

        News.Types.Toggle a0 ->
            tree_News_Types_Emphasis (ModelTree.Put (\new -> ModelTree.apply put (News.Types.Toggle new))) a0


tree_News_Types_Item put value =
    case value of
        News.Types.Item _ ->
            ModelTree.variant "Item" 1 (args_News_Types_Item put value) [] (ModelTree.unchanged put value)


args_News_Types_Item put value i =
    case value of
        News.Types.Item a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "content", \() -> ModelTree.list tree_News_Types_Inline (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | content = x1 })) value1.content ), ( "children", \() -> ModelTree.list tree_News_Types_Item (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | children = x1 })) value1.children ) ]) (ModelTree.Put (\new -> ModelTree.apply put (News.Types.Item new))) a0


tree_News_Types_NewsState put value =
    case value of
        News.Types.NewsNotRequested ->
            ModelTree.variant "NewsNotRequested" 0 (args_News_Types_NewsState put value) names_News_Types_NewsState (choose_News_Types_NewsState put)

        News.Types.LoadingNews _ ->
            ModelTree.variant "LoadingNews" 1 (args_News_Types_NewsState put value) names_News_Types_NewsState (choose_News_Types_NewsState put)

        News.Types.LoadedNews _ ->
            ModelTree.variant "LoadedNews" 1 (args_News_Types_NewsState put value) names_News_Types_NewsState (choose_News_Types_NewsState put)

        News.Types.NewsFailed _ ->
            ModelTree.variant "NewsFailed" 1 (args_News_Types_NewsState put value) names_News_Types_NewsState (choose_News_Types_NewsState put)


args_News_Types_NewsState put value i =
    case value of
        News.Types.NewsNotRequested ->
            ModelTree.noChild i

        News.Types.LoadingNews a0 ->
            ModelTree.maybe (ModelTree.list tree_News_Types_Day) (ModelTree.Put (\new -> ModelTree.apply put (News.Types.LoadingNews new))) a0

        News.Types.LoadedNews a0 ->
            ModelTree.list tree_News_Types_Day (ModelTree.Put (\new -> ModelTree.apply put (News.Types.LoadedNews new))) a0

        News.Types.NewsFailed a0 ->
            tree_Effect_HttpError (ModelTree.Put (\new -> ModelTree.apply put (News.Types.NewsFailed new))) a0


names_News_Types_NewsState =
    [ "NewsNotRequested"
    ]


choose_News_Types_NewsState put _ =
    ModelTree.apply put News.Types.NewsNotRequested


tree_News_Types_Topic put value =
    ModelTree.record [ "heading", "items" ] (field_News_Types_Topic put value)


field_News_Types_Topic put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | heading = x })) value.heading

        _ ->
            ModelTree.list tree_News_Types_Item (ModelTree.Put (\x -> ModelTree.apply put { value | items = x })) value.items


tree_News_Types_UiId put value =
    case value of
        News.Types.Viewport ->
            ModelTree.variant "Viewport" 0 ModelTree.noChild names_News_Types_UiId (choose_News_Types_UiId put)


names_News_Types_UiId =
    [ "Viewport"
    ]


choose_News_Types_UiId put _ =
    ModelTree.apply put News.Types.Viewport


tree_Paint_Model put value =
    ModelTree.record [ "isOpen", "canvas", "color", "brush", "tool", "undoable", "redoable", "stroke", "zoom", "offset", "panning" ] (field_Paint_Model put value)


field_Paint_Model put value i =
    case i of
        0 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | isOpen = x })) value.isOpen

        1 ->
            tree_Image_Image (ModelTree.Put (\x -> ModelTree.apply put { value | canvas = x })) value.canvas

        2 ->
            ModelTree.opaqueTree "Color.Color" (ModelTree.Put (\x -> ModelTree.apply put { value | color = x })) value.color

        3 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | brush = x })) value.brush

        4 ->
            tree_Paint_Types_Tool (ModelTree.Put (\x -> ModelTree.apply put { value | tool = x })) value.tool

        5 ->
            ModelTree.list tree_Image_Image (ModelTree.Put (\x -> ModelTree.apply put { value | undoable = x })) value.undoable

        6 ->
            ModelTree.list tree_Image_Image (ModelTree.Put (\x -> ModelTree.apply put { value | redoable = x })) value.redoable

        7 ->
            ModelTree.maybe tree_Paint_Stroke (ModelTree.Put (\x -> ModelTree.apply put { value | stroke = x })) value.stroke

        8 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | zoom = x })) value.zoom

        9 ->
            ModelTree.tuple2 ModelTree.float ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | offset = x })) value.offset

        _ ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | panning = x })) value.panning


tree_Paint_Stroke put value =
    ModelTree.record [ "at", "exact", "target", "filled" ] (field_Paint_Stroke put value)


field_Paint_Stroke put value i =
    case i of
        0 ->
            ModelTree.tuple2 ModelTree.int ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | at = x })) value.at

        1 ->
            ModelTree.tuple2 ModelTree.float ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | exact = x })) value.exact

        2 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | target = x })) value.target

        _ ->
            ModelTree.set ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | filled = x })) value.filled


tree_Paint_Types_Tool put value =
    case value of
        Paint.Types.Pen ->
            ModelTree.variant "Pen" 0 ModelTree.noChild names_Paint_Types_Tool (choose_Paint_Types_Tool put)

        Paint.Types.Fill ->
            ModelTree.variant "Fill" 0 ModelTree.noChild names_Paint_Types_Tool (choose_Paint_Types_Tool put)


names_Paint_Types_Tool =
    [ "Pen"
    , "Fill"
    ]


choose_Paint_Types_Tool put i =
    case i of
        0 ->
            ModelTree.apply put Paint.Types.Pen

        _ ->
            ModelTree.apply put Paint.Types.Fill


tree_Paint_Types_UiId put value =
    case value of
        Paint.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 (args_Paint_Types_UiId put value) names_Paint_Types_UiId (choose_Paint_Types_UiId put)

        Paint.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 (args_Paint_Types_UiId put value) names_Paint_Types_UiId (choose_Paint_Types_UiId put)

        Paint.Types.ClearButton ->
            ModelTree.variant "ClearButton" 0 (args_Paint_Types_UiId put value) names_Paint_Types_UiId (choose_Paint_Types_UiId put)

        Paint.Types.UndoButton ->
            ModelTree.variant "UndoButton" 0 (args_Paint_Types_UiId put value) names_Paint_Types_UiId (choose_Paint_Types_UiId put)

        Paint.Types.RedoButton ->
            ModelTree.variant "RedoButton" 0 (args_Paint_Types_UiId put value) names_Paint_Types_UiId (choose_Paint_Types_UiId put)

        Paint.Types.Canvas ->
            ModelTree.variant "Canvas" 0 (args_Paint_Types_UiId put value) names_Paint_Types_UiId (choose_Paint_Types_UiId put)

        Paint.Types.ColorButton _ ->
            ModelTree.variant "ColorButton" 1 (args_Paint_Types_UiId put value) names_Paint_Types_UiId (choose_Paint_Types_UiId put)

        Paint.Types.BrushButton _ ->
            ModelTree.variant "BrushButton" 1 (args_Paint_Types_UiId put value) names_Paint_Types_UiId (choose_Paint_Types_UiId put)

        Paint.Types.ToolButton _ ->
            ModelTree.variant "ToolButton" 1 (args_Paint_Types_UiId put value) names_Paint_Types_UiId (choose_Paint_Types_UiId put)


args_Paint_Types_UiId put value i =
    case value of
        Paint.Types.OpenButton ->
            ModelTree.noChild i

        Paint.Types.CloseButton ->
            ModelTree.noChild i

        Paint.Types.ClearButton ->
            ModelTree.noChild i

        Paint.Types.UndoButton ->
            ModelTree.noChild i

        Paint.Types.RedoButton ->
            ModelTree.noChild i

        Paint.Types.Canvas ->
            ModelTree.noChild i

        Paint.Types.ColorButton a0 ->
            ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (Paint.Types.ColorButton new))) a0

        Paint.Types.BrushButton a0 ->
            ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (Paint.Types.BrushButton new))) a0

        Paint.Types.ToolButton a0 ->
            tree_Paint_Types_Tool (ModelTree.Put (\new -> ModelTree.apply put (Paint.Types.ToolButton new))) a0


names_Paint_Types_UiId =
    [ "OpenButton"
    , "CloseButton"
    , "ClearButton"
    , "UndoButton"
    , "RedoButton"
    , "Canvas"
    ]


choose_Paint_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put Paint.Types.OpenButton

        1 ->
            ModelTree.apply put Paint.Types.CloseButton

        2 ->
            ModelTree.apply put Paint.Types.ClearButton

        3 ->
            ModelTree.apply put Paint.Types.UndoButton

        4 ->
            ModelTree.apply put Paint.Types.RedoButton

        _ ->
            ModelTree.apply put Paint.Types.Canvas


tree_ScreenshotViewer_Model put value =
    ModelTree.record [ "isOpen", "selected", "zoom", "offset", "dragging" ] (field_ScreenshotViewer_Model put value)


field_ScreenshotViewer_Model put value i =
    case i of
        0 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | isOpen = x })) value.isOpen

        1 ->
            ModelTree.maybe ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | selected = x })) value.selected

        2 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | zoom = x })) value.zoom

        3 ->
            ModelTree.tuple2 ModelTree.float ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | offset = x })) value.offset

        _ ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | dragging = x })) value.dragging


tree_ScreenshotViewer_Types_UiId put value =
    case value of
        ScreenshotViewer.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 (args_ScreenshotViewer_Types_UiId put value) names_ScreenshotViewer_Types_UiId (choose_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 (args_ScreenshotViewer_Types_UiId put value) names_ScreenshotViewer_Types_UiId (choose_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.PreviewList ->
            ModelTree.variant "PreviewList" 0 (args_ScreenshotViewer_Types_UiId put value) names_ScreenshotViewer_Types_UiId (choose_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.Preview _ ->
            ModelTree.variant "Preview" 1 (args_ScreenshotViewer_Types_UiId put value) names_ScreenshotViewer_Types_UiId (choose_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.ImageArea ->
            ModelTree.variant "ImageArea" 0 (args_ScreenshotViewer_Types_UiId put value) names_ScreenshotViewer_Types_UiId (choose_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.ZoomInButton ->
            ModelTree.variant "ZoomInButton" 0 (args_ScreenshotViewer_Types_UiId put value) names_ScreenshotViewer_Types_UiId (choose_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.ZoomOutButton ->
            ModelTree.variant "ZoomOutButton" 0 (args_ScreenshotViewer_Types_UiId put value) names_ScreenshotViewer_Types_UiId (choose_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.ActualSizeButton ->
            ModelTree.variant "ActualSizeButton" 0 (args_ScreenshotViewer_Types_UiId put value) names_ScreenshotViewer_Types_UiId (choose_ScreenshotViewer_Types_UiId put)

        ScreenshotViewer.Types.FitButton ->
            ModelTree.variant "FitButton" 0 (args_ScreenshotViewer_Types_UiId put value) names_ScreenshotViewer_Types_UiId (choose_ScreenshotViewer_Types_UiId put)


args_ScreenshotViewer_Types_UiId put value i =
    case value of
        ScreenshotViewer.Types.OpenButton ->
            ModelTree.noChild i

        ScreenshotViewer.Types.CloseButton ->
            ModelTree.noChild i

        ScreenshotViewer.Types.PreviewList ->
            ModelTree.noChild i

        ScreenshotViewer.Types.Preview a0 ->
            ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (ScreenshotViewer.Types.Preview new))) a0

        ScreenshotViewer.Types.ImageArea ->
            ModelTree.noChild i

        ScreenshotViewer.Types.ZoomInButton ->
            ModelTree.noChild i

        ScreenshotViewer.Types.ZoomOutButton ->
            ModelTree.noChild i

        ScreenshotViewer.Types.ActualSizeButton ->
            ModelTree.noChild i

        ScreenshotViewer.Types.FitButton ->
            ModelTree.noChild i


names_ScreenshotViewer_Types_UiId =
    [ "OpenButton"
    , "CloseButton"
    , "PreviewList"
    , "ImageArea"
    , "ZoomInButton"
    , "ZoomOutButton"
    , "ActualSizeButton"
    , "FitButton"
    ]


choose_ScreenshotViewer_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put ScreenshotViewer.Types.OpenButton

        1 ->
            ModelTree.apply put ScreenshotViewer.Types.CloseButton

        2 ->
            ModelTree.apply put ScreenshotViewer.Types.PreviewList

        3 ->
            ModelTree.apply put ScreenshotViewer.Types.ImageArea

        4 ->
            ModelTree.apply put ScreenshotViewer.Types.ZoomInButton

        5 ->
            ModelTree.apply put ScreenshotViewer.Types.ZoomOutButton

        6 ->
            ModelTree.apply put ScreenshotViewer.Types.ActualSizeButton

        _ ->
            ModelTree.apply put ScreenshotViewer.Types.FitButton


tree_TextInput_Click put value =
    ModelTree.record [ "time", "clicks", "index" ] (field_TextInput_Click put value)


field_TextInput_Click put value i =
    case i of
        0 ->
            ModelTree.posix (ModelTree.Put (\x -> ModelTree.apply put { value | time = x })) value.time

        1 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | clicks = x })) value.clicks

        _ ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | index = x })) value.index


tree_TextInput_Model put value =
    ModelTree.record [ "current", "undoHistory", "redoHistory", "lastClick" ] (field_TextInput_Model put value)


field_TextInput_Model put value i =
    case i of
        0 ->
            tree_TextInput_State (ModelTree.Put (\x -> ModelTree.apply put { value | current = x })) value.current

        1 ->
            ModelTree.list tree_TextInput_State (ModelTree.Put (\x -> ModelTree.apply put { value | undoHistory = x })) value.undoHistory

        2 ->
            ModelTree.list tree_TextInput_State (ModelTree.Put (\x -> ModelTree.apply put { value | redoHistory = x })) value.redoHistory

        _ ->
            ModelTree.maybe tree_TextInput_Click (ModelTree.Put (\x -> ModelTree.apply put { value | lastClick = x })) value.lastClick


tree_TextInput_State put value =
    ModelTree.record [ "cursorPosition", "cursorSize", "text" ] (field_TextInput_State put value)


field_TextInput_State put value i =
    case i of
        0 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | cursorPosition = x })) value.cursorPosition

        1 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | cursorSize = x })) value.cursorSize

        _ ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | text = x })) value.text


tree_TextInputMultiline_Glide put value =
    case value of
        TextInputMultiline.Still ->
            ModelTree.variant "Still" 0 (args_TextInputMultiline_Glide put value) names_TextInputMultiline_Glide (choose_TextInputMultiline_Glide put)

        TextInputMultiline.Fingers _ ->
            ModelTree.variant "Fingers" 1 (args_TextInputMultiline_Glide put value) names_TextInputMultiline_Glide (choose_TextInputMultiline_Glide put)

        TextInputMultiline.Easing _ ->
            ModelTree.variant "Easing" 1 (args_TextInputMultiline_Glide put value) names_TextInputMultiline_Glide (choose_TextInputMultiline_Glide put)


args_TextInputMultiline_Glide put value i =
    case value of
        TextInputMultiline.Still ->
            ModelTree.noChild i

        TextInputMultiline.Fingers a0 ->
            ModelTree.float (ModelTree.Put (\new -> ModelTree.apply put (TextInputMultiline.Fingers new))) a0

        TextInputMultiline.Easing a0 ->
            ModelTree.float (ModelTree.Put (\new -> ModelTree.apply put (TextInputMultiline.Easing new))) a0


names_TextInputMultiline_Glide =
    [ "Still"
    ]


choose_TextInputMultiline_Glide put _ =
    ModelTree.apply put TextInputMultiline.Still


tree_TextInputMultiline_Model put value =
    ModelTree.record [ "input", "scroll", "position", "glide", "goalX", "grab", "scrollbarShown", "scrollbarWidened" ] (field_TextInputMultiline_Model put value)


field_TextInputMultiline_Model put value i =
    case i of
        0 ->
            tree_TextInput_Model (ModelTree.Put (\x -> ModelTree.apply put { value | input = x })) value.input

        1 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | scroll = x })) value.scroll

        2 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | position = x })) value.position

        3 ->
            tree_TextInputMultiline_Glide (ModelTree.Put (\x -> ModelTree.apply put { value | glide = x })) value.glide

        4 ->
            ModelTree.maybe ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | goalX = x })) value.goalX

        5 ->
            ModelTree.maybe ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | grab = x })) value.grab

        6 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | scrollbarShown = x })) value.scrollbarShown

        _ ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | scrollbarWidened = x })) value.scrollbarWidened


tree_TicTacToe_Mark put value =
    case value of
        TicTacToe.X ->
            ModelTree.variant "X" 0 ModelTree.noChild names_TicTacToe_Mark (choose_TicTacToe_Mark put)

        TicTacToe.O ->
            ModelTree.variant "O" 0 ModelTree.noChild names_TicTacToe_Mark (choose_TicTacToe_Mark put)


names_TicTacToe_Mark =
    [ "X"
    , "O"
    ]


choose_TicTacToe_Mark put i =
    case i of
        0 ->
            ModelTree.apply put TicTacToe.X

        _ ->
            ModelTree.apply put TicTacToe.O


tree_TicTacToe_Model put value =
    ModelTree.record [ "squares", "next" ] (field_TicTacToe_Model put value)


field_TicTacToe_Model put value i =
    case i of
        0 ->
            ModelTree.list (ModelTree.maybe tree_TicTacToe_Mark) (ModelTree.Put (\x -> ModelTree.apply put { value | squares = x })) value.squares

        _ ->
            tree_TicTacToe_Mark (ModelTree.Put (\x -> ModelTree.apply put { value | next = x })) value.next


tree_TicTacToe_Types_UiId put value =
    case value of
        TicTacToe.Types.Square _ ->
            ModelTree.variant "Square" 1 (args_TicTacToe_Types_UiId put value) names_TicTacToe_Types_UiId (choose_TicTacToe_Types_UiId put)

        TicTacToe.Types.NewGameButton ->
            ModelTree.variant "NewGameButton" 0 (args_TicTacToe_Types_UiId put value) names_TicTacToe_Types_UiId (choose_TicTacToe_Types_UiId put)

        TicTacToe.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 (args_TicTacToe_Types_UiId put value) names_TicTacToe_Types_UiId (choose_TicTacToe_Types_UiId put)

        TicTacToe.Types.Panel ->
            ModelTree.variant "Panel" 0 (args_TicTacToe_Types_UiId put value) names_TicTacToe_Types_UiId (choose_TicTacToe_Types_UiId put)


args_TicTacToe_Types_UiId put value i =
    case value of
        TicTacToe.Types.Square a0 ->
            ModelTree.int (ModelTree.Put (\new -> ModelTree.apply put (TicTacToe.Types.Square new))) a0

        TicTacToe.Types.NewGameButton ->
            ModelTree.noChild i

        TicTacToe.Types.CloseButton ->
            ModelTree.noChild i

        TicTacToe.Types.Panel ->
            ModelTree.noChild i


names_TicTacToe_Types_UiId =
    [ "NewGameButton"
    , "CloseButton"
    , "Panel"
    ]


choose_TicTacToe_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put TicTacToe.Types.NewGameButton

        1 ->
            ModelTree.apply put TicTacToe.Types.CloseButton

        _ ->
            ModelTree.apply put TicTacToe.Types.Panel


tree_Ui_ElementState put value =
    case value of
        Ui.TextInputState _ ->
            ModelTree.variant "TextInputState" 1 (args_Ui_ElementState put value) [] (ModelTree.unchanged put value)

        Ui.TextInputMultilineState _ ->
            ModelTree.variant "TextInputMultilineState" 1 (args_Ui_ElementState put value) [] (ModelTree.unchanged put value)

        Ui.ViewportState _ ->
            ModelTree.variant "ViewportState" 1 (args_Ui_ElementState put value) [] (ModelTree.unchanged put value)

        Ui.ButtonState _ ->
            ModelTree.variant "ButtonState" 1 (args_Ui_ElementState put value) [] (ModelTree.unchanged put value)


args_Ui_ElementState put value i =
    case value of
        Ui.TextInputState a0 ->
            tree_TextInput_Model (ModelTree.Put (\new -> ModelTree.apply put (Ui.TextInputState new))) a0

        Ui.TextInputMultilineState a0 ->
            tree_TextInputMultiline_Model (ModelTree.Put (\new -> ModelTree.apply put (Ui.TextInputMultilineState new))) a0

        Ui.ViewportState a0 ->
            tree_Ui_ViewportModel (ModelTree.Put (\new -> ModelTree.apply put (Ui.ViewportState new))) a0

        Ui.ButtonState a0 ->
            tree_Button_Model (ModelTree.Put (\new -> ModelTree.apply put (Ui.ButtonState new))) a0


tree_Ui_Model tree_id put value =
    ModelTree.record [ "focus", "uiState", "mouseStill" ] (field_Ui_Model tree_id put value)


field_Ui_Model tree_id put value i =
    case i of
        0 ->
            ModelTree.maybe tree_id (ModelTree.Put (\x -> ModelTree.apply put { value | focus = x })) value.focus

        1 ->
            ModelTree.seqDict tree_id tree_Ui_ElementState (ModelTree.Put (\x -> ModelTree.apply put { value | uiState = x })) value.uiState

        _ ->
            (\put1 value1 -> ModelTree.fields [ ( "at", \() -> tree_Coord_Coord (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | at = x1 })) value1.at ), ( "seconds", \() -> ModelTree.quantity ModelTree.float (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | seconds = x1 })) value1.seconds ) ]) (ModelTree.Put (\x -> ModelTree.apply put { value | mouseStill = x })) value.mouseStill


tree_Ui_Screenshot put value =
    ModelTree.record [ "time", "uiState", "uiScale", "screenshot" ] (field_Ui_Screenshot put value)


field_Ui_Screenshot put value i =
    case i of
        0 ->
            ModelTree.posix (ModelTree.Put (\x -> ModelTree.apply put { value | time = x })) value.time

        1 ->
            tree_Ui_Model ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | uiState = x })) value.uiState

        2 ->
            tree_Units_UiScale (ModelTree.Put (\x -> ModelTree.apply put { value | uiScale = x })) value.uiScale

        _ ->
            ModelTree.opaqueTree "Ui.ElementFull" (ModelTree.Put (\x -> ModelTree.apply put { value | screenshot = x })) value.screenshot


tree_Ui_Source put value =
    ModelTree.record [ "module_", "line", "function" ] (field_Ui_Source put value)


field_Ui_Source put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | module_ = x })) value.module_

        1 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | line = x })) value.line

        _ ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | function = x })) value.function


tree_Ui_ViewportModel put value =
    ModelTree.record [ "offset", "target", "momentum", "bottom", "grab", "scrollbarShown", "scrollbarWidened" ] (field_Ui_ViewportModel put value)


field_Ui_ViewportModel put value i =
    case i of
        0 ->
            ModelTree.quantity ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | offset = x })) value.offset

        1 ->
            ModelTree.quantity ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | target = x })) value.target

        2 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | momentum = x })) value.momentum

        3 ->
            ModelTree.quantity ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | bottom = x })) value.bottom

        4 ->
            ModelTree.maybe ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | grab = x })) value.grab

        5 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | scrollbarShown = x })) value.scrollbarShown

        _ ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | scrollbarWidened = x })) value.scrollbarWidened


tree_UiId_UiId put value =
    case value of
        UiId.About _ ->
            ModelTree.variant "About" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.DebugInfo _ ->
            ModelTree.variant "DebugInfo" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.Editor _ ->
            ModelTree.variant "Editor" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.Weather _ ->
            ModelTree.variant "Weather" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.NewsButton ->
            ModelTree.variant "NewsButton" 0 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.CalculatorButton ->
            ModelTree.variant "CalculatorButton" 0 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.TicTacToeButton ->
            ModelTree.variant "TicTacToeButton" 0 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.PowerOffButton ->
            ModelTree.variant "PowerOffButton" 0 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.RestartButton ->
            ModelTree.variant "RestartButton" 0 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.ConfirmPowerButton ->
            ModelTree.variant "ConfirmPowerButton" 0 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.CancelPowerButton ->
            ModelTree.variant "CancelPowerButton" 0 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.BrightnessDownButton ->
            ModelTree.variant "BrightnessDownButton" 0 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.BrightnessUpButton ->
            ModelTree.variant "BrightnessUpButton" 0 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.Network _ ->
            ModelTree.variant "Network" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.Calculator _ ->
            ModelTree.variant "Calculator" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.TicTacToe _ ->
            ModelTree.variant "TicTacToe" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.Paint _ ->
            ModelTree.variant "Paint" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.Code _ ->
            ModelTree.variant "Code" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.News _ ->
            ModelTree.variant "News" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.HackerNews _ ->
            ModelTree.variant "HackerNews" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.AsciiCollab _ ->
            ModelTree.variant "AsciiCollab" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.Email _ ->
            ModelTree.variant "Email" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.WebViewer _ ->
            ModelTree.variant "WebViewer" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.ScreenshotViewer _ ->
            ModelTree.variant "ScreenshotViewer" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.Install _ ->
            ModelTree.variant "Install" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.History _ ->
            ModelTree.variant "History" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.ModelViewer _ ->
            ModelTree.variant "ModelViewer" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)

        UiId.Lazy _ ->
            ModelTree.variant "Lazy" 1 (args_UiId_UiId put value) names_UiId_UiId (choose_UiId_UiId put)


args_UiId_UiId put value i =
    case value of
        UiId.About a0 ->
            tree_About_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.About new))) a0

        UiId.DebugInfo a0 ->
            tree_DebugInfo_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.DebugInfo new))) a0

        UiId.Editor a0 ->
            tree_Editor_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.Editor new))) a0

        UiId.Weather a0 ->
            tree_Weather_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.Weather new))) a0

        UiId.NewsButton ->
            ModelTree.noChild i

        UiId.CalculatorButton ->
            ModelTree.noChild i

        UiId.TicTacToeButton ->
            ModelTree.noChild i

        UiId.PowerOffButton ->
            ModelTree.noChild i

        UiId.RestartButton ->
            ModelTree.noChild i

        UiId.ConfirmPowerButton ->
            ModelTree.noChild i

        UiId.CancelPowerButton ->
            ModelTree.noChild i

        UiId.BrightnessDownButton ->
            ModelTree.noChild i

        UiId.BrightnessUpButton ->
            ModelTree.noChild i

        UiId.Network a0 ->
            tree_Network_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.Network new))) a0

        UiId.Calculator a0 ->
            tree_Calculator_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.Calculator new))) a0

        UiId.TicTacToe a0 ->
            tree_TicTacToe_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.TicTacToe new))) a0

        UiId.Paint a0 ->
            tree_Paint_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.Paint new))) a0

        UiId.Code a0 ->
            tree_Code_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.Code new))) a0

        UiId.News a0 ->
            tree_News_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.News new))) a0

        UiId.HackerNews a0 ->
            tree_HackerNews_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.HackerNews new))) a0

        UiId.AsciiCollab a0 ->
            tree_AsciiCollab_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.AsciiCollab new))) a0

        UiId.Email a0 ->
            tree_Email_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.Email new))) a0

        UiId.WebViewer a0 ->
            tree_WebViewer_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.WebViewer new))) a0

        UiId.ScreenshotViewer a0 ->
            tree_ScreenshotViewer_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.ScreenshotViewer new))) a0

        UiId.Install a0 ->
            tree_Install_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.Install new))) a0

        UiId.History a0 ->
            tree_History_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.History new))) a0

        UiId.ModelViewer a0 ->
            tree_ModelViewer_Types_UiId (ModelTree.Put (\new -> ModelTree.apply put (UiId.ModelViewer new))) a0

        UiId.Lazy a0 ->
            ModelTree.opaqueTree "UiId.LazyKey (not saved)" (ModelTree.Put (\new -> ModelTree.apply put (UiId.Lazy new))) a0


names_UiId_UiId =
    [ "NewsButton"
    , "CalculatorButton"
    , "TicTacToeButton"
    , "PowerOffButton"
    , "RestartButton"
    , "ConfirmPowerButton"
    , "CancelPowerButton"
    , "BrightnessDownButton"
    , "BrightnessUpButton"
    ]


choose_UiId_UiId put i =
    case i of
        0 ->
            ModelTree.apply put UiId.NewsButton

        1 ->
            ModelTree.apply put UiId.CalculatorButton

        2 ->
            ModelTree.apply put UiId.TicTacToeButton

        3 ->
            ModelTree.apply put UiId.PowerOffButton

        4 ->
            ModelTree.apply put UiId.RestartButton

        5 ->
            ModelTree.apply put UiId.ConfirmPowerButton

        6 ->
            ModelTree.apply put UiId.CancelPowerButton

        7 ->
            ModelTree.apply put UiId.BrightnessDownButton

        _ ->
            ModelTree.apply put UiId.BrightnessUpButton


tree_Units_UiScale put value =
    ModelTree.quantity ModelTree.int put value


tree_Weather_Day put value =
    ModelTree.record [ "date", "code", "high", "low" ] (field_Weather_Day put value)


field_Weather_Day put value i =
    case i of
        0 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | date = x })) value.date

        1 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | code = x })) value.code

        2 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | high = x })) value.high

        _ ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | low = x })) value.low


tree_Weather_Forecast put value =
    ModelTree.record [ "temperature", "humidity", "wind", "code", "time", "days", "utcOffsetSeconds" ] (field_Weather_Forecast put value)


field_Weather_Forecast put value i =
    case i of
        0 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | temperature = x })) value.temperature

        1 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | humidity = x })) value.humidity

        2 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | wind = x })) value.wind

        3 ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | code = x })) value.code

        4 ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | time = x })) value.time

        5 ->
            ModelTree.list tree_Weather_Day (ModelTree.Put (\x -> ModelTree.apply put { value | days = x })) value.days

        _ ->
            ModelTree.maybe ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | utcOffsetSeconds = x })) value.utcOffsetSeconds


tree_Weather_Place put value =
    ModelTree.record [ "latitude", "longitude", "name" ] (field_Weather_Place put value)


field_Weather_Place put value i =
    case i of
        0 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | latitude = x })) value.latitude

        1 ->
            ModelTree.float (ModelTree.Put (\x -> ModelTree.apply put { value | longitude = x })) value.longitude

        _ ->
            ModelTree.string (ModelTree.Put (\x -> ModelTree.apply put { value | name = x })) value.name


tree_Weather_WeatherState put value =
    case value of
        Weather.NoWeather ->
            ModelTree.variant "NoWeather" 0 (args_Weather_WeatherState put value) names_Weather_WeatherState (choose_Weather_WeatherState put)

        Weather.FindingPlace ->
            ModelTree.variant "FindingPlace" 0 (args_Weather_WeatherState put value) names_Weather_WeatherState (choose_Weather_WeatherState put)

        Weather.LoadingForecast _ ->
            ModelTree.variant "LoadingForecast" 1 (args_Weather_WeatherState put value) names_Weather_WeatherState (choose_Weather_WeatherState put)

        Weather.GotWeather _ _ ->
            ModelTree.variant "GotWeather" 2 (args_Weather_WeatherState put value) names_Weather_WeatherState (choose_Weather_WeatherState put)

        Weather.WeatherFailed _ ->
            ModelTree.variant "WeatherFailed" 1 (args_Weather_WeatherState put value) names_Weather_WeatherState (choose_Weather_WeatherState put)


args_Weather_WeatherState put value i =
    case value of
        Weather.NoWeather ->
            ModelTree.noChild i

        Weather.FindingPlace ->
            ModelTree.noChild i

        Weather.LoadingForecast a0 ->
            tree_Weather_Place (ModelTree.Put (\new -> ModelTree.apply put (Weather.LoadingForecast new))) a0

        Weather.GotWeather a0 a1 ->
            case i of
                0 ->
                    tree_Weather_Place (ModelTree.Put (\new -> ModelTree.apply put (Weather.GotWeather new a1))) a0

                _ ->
                    tree_Weather_Forecast (ModelTree.Put (\new -> ModelTree.apply put (Weather.GotWeather a0 new))) a1

        Weather.WeatherFailed a0 ->
            tree_Effect_HttpError (ModelTree.Put (\new -> ModelTree.apply put (Weather.WeatherFailed new))) a0


names_Weather_WeatherState =
    [ "NoWeather"
    , "FindingPlace"
    ]


choose_Weather_WeatherState put i =
    case i of
        0 ->
            ModelTree.apply put Weather.NoWeather

        _ ->
            ModelTree.apply put Weather.FindingPlace


tree_Weather_Types_UiId put value =
    case value of
        Weather.Types.RefreshButton ->
            ModelTree.variant "RefreshButton" 0 ModelTree.noChild names_Weather_Types_UiId (choose_Weather_Types_UiId put)

        Weather.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 ModelTree.noChild names_Weather_Types_UiId (choose_Weather_Types_UiId put)

        Weather.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 ModelTree.noChild names_Weather_Types_UiId (choose_Weather_Types_UiId put)


names_Weather_Types_UiId =
    [ "RefreshButton"
    , "OpenButton"
    , "CloseButton"
    ]


choose_Weather_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put Weather.Types.RefreshButton

        1 ->
            ModelTree.apply put Weather.Types.OpenButton

        _ ->
            ModelTree.apply put Weather.Types.CloseButton


tree_WebViewer_Mode put value =
    case value of
        WebViewer.TextMode ->
            ModelTree.variant "TextMode" 0 ModelTree.noChild names_WebViewer_Mode (choose_WebViewer_Mode put)

        WebViewer.HtmlMode ->
            ModelTree.variant "HtmlMode" 0 ModelTree.noChild names_WebViewer_Mode (choose_WebViewer_Mode put)


names_WebViewer_Mode =
    [ "TextMode"
    , "HtmlMode"
    ]


choose_WebViewer_Mode put i =
    case i of
        0 ->
            ModelTree.apply put WebViewer.TextMode

        _ ->
            ModelTree.apply put WebViewer.HtmlMode


tree_WebViewer_Model put value =
    ModelTree.record [ "isOpen", "mode", "page", "requestCount" ] (field_WebViewer_Model put value)


field_WebViewer_Model put value i =
    case i of
        0 ->
            ModelTree.bool (ModelTree.Put (\x -> ModelTree.apply put { value | isOpen = x })) value.isOpen

        1 ->
            tree_WebViewer_Mode (ModelTree.Put (\x -> ModelTree.apply put { value | mode = x })) value.mode

        2 ->
            tree_WebViewer_Page (ModelTree.Put (\x -> ModelTree.apply put { value | page = x })) value.page

        _ ->
            ModelTree.int (ModelTree.Put (\x -> ModelTree.apply put { value | requestCount = x })) value.requestCount


tree_WebViewer_Page put value =
    case value of
        WebViewer.NoPage ->
            ModelTree.variant "NoPage" 0 (args_WebViewer_Page put value) names_WebViewer_Page (choose_WebViewer_Page put)

        WebViewer.Loading _ ->
            ModelTree.variant "Loading" 1 (args_WebViewer_Page put value) names_WebViewer_Page (choose_WebViewer_Page put)

        WebViewer.Loaded _ ->
            ModelTree.variant "Loaded" 1 (args_WebViewer_Page put value) names_WebViewer_Page (choose_WebViewer_Page put)

        WebViewer.Failed _ ->
            ModelTree.variant "Failed" 1 (args_WebViewer_Page put value) names_WebViewer_Page (choose_WebViewer_Page put)


args_WebViewer_Page put value i =
    case value of
        WebViewer.NoPage ->
            ModelTree.noChild i

        WebViewer.Loading a0 ->
            ModelTree.string (ModelTree.Put (\new -> ModelTree.apply put (WebViewer.Loading new))) a0

        WebViewer.Loaded a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "url", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | url = x1 })) value1.url ), ( "status", \() -> ModelTree.int (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | status = x1 })) value1.status ), ( "html", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | html = x1 })) value1.html ), ( "text", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | text = x1 })) value1.text ) ]) (ModelTree.Put (\new -> ModelTree.apply put (WebViewer.Loaded new))) a0

        WebViewer.Failed a0 ->
            (\put1 value1 -> ModelTree.fields [ ( "url", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | url = x1 })) value1.url ), ( "error", \() -> ModelTree.string (ModelTree.Put (\x1 -> ModelTree.apply put1 { value1 | error = x1 })) value1.error ) ]) (ModelTree.Put (\new -> ModelTree.apply put (WebViewer.Failed new))) a0


names_WebViewer_Page =
    [ "NoPage"
    ]


choose_WebViewer_Page put _ =
    ModelTree.apply put WebViewer.NoPage


tree_WebViewer_Types_UiId put value =
    case value of
        WebViewer.Types.OpenButton ->
            ModelTree.variant "OpenButton" 0 ModelTree.noChild names_WebViewer_Types_UiId (choose_WebViewer_Types_UiId put)

        WebViewer.Types.CloseButton ->
            ModelTree.variant "CloseButton" 0 ModelTree.noChild names_WebViewer_Types_UiId (choose_WebViewer_Types_UiId put)

        WebViewer.Types.UrlInput ->
            ModelTree.variant "UrlInput" 0 ModelTree.noChild names_WebViewer_Types_UiId (choose_WebViewer_Types_UiId put)

        WebViewer.Types.GoButton ->
            ModelTree.variant "GoButton" 0 ModelTree.noChild names_WebViewer_Types_UiId (choose_WebViewer_Types_UiId put)

        WebViewer.Types.TextModeButton ->
            ModelTree.variant "TextModeButton" 0 ModelTree.noChild names_WebViewer_Types_UiId (choose_WebViewer_Types_UiId put)

        WebViewer.Types.HtmlModeButton ->
            ModelTree.variant "HtmlModeButton" 0 ModelTree.noChild names_WebViewer_Types_UiId (choose_WebViewer_Types_UiId put)

        WebViewer.Types.TextViewport ->
            ModelTree.variant "TextViewport" 0 ModelTree.noChild names_WebViewer_Types_UiId (choose_WebViewer_Types_UiId put)

        WebViewer.Types.HtmlViewport ->
            ModelTree.variant "HtmlViewport" 0 ModelTree.noChild names_WebViewer_Types_UiId (choose_WebViewer_Types_UiId put)


names_WebViewer_Types_UiId =
    [ "OpenButton"
    , "CloseButton"
    , "UrlInput"
    , "GoButton"
    , "TextModeButton"
    , "HtmlModeButton"
    , "TextViewport"
    , "HtmlViewport"
    ]


choose_WebViewer_Types_UiId put i =
    case i of
        0 ->
            ModelTree.apply put WebViewer.Types.OpenButton

        1 ->
            ModelTree.apply put WebViewer.Types.CloseButton

        2 ->
            ModelTree.apply put WebViewer.Types.UrlInput

        3 ->
            ModelTree.apply put WebViewer.Types.GoButton

        4 ->
            ModelTree.apply put WebViewer.Types.TextModeButton

        5 ->
            ModelTree.apply put WebViewer.Types.HtmlModeButton

        6 ->
            ModelTree.apply put WebViewer.Types.TextViewport

        _ ->
            ModelTree.apply put WebViewer.Types.HtmlViewport
