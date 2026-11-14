module Evergreen.Migrate.V12 exposing (model)

{-| How a Model saved by version 11 becomes one of version 12 (changed: HackerNews.Comment, HackerNews.HackerNewsState, HackerNews.UiId, Ui.Model; new: HackerNews.Post, Units.UiScale).

tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it
wrote `Unimplemented`, which doesn't compile: replace each one. The rest is
yours to change too; it's only ever written once.

-}

import Dict
import Evergreen.V11.BootInfo
import Evergreen.V11.Calculator
import Evergreen.V11.Coord
import Evergreen.V11.Effect
import Evergreen.V11.HackerNews
import Evergreen.V11.Main
import Evergreen.V11.News
import Evergreen.V11.TextInput
import Evergreen.V11.TextInputMultiline
import Evergreen.V11.Ui
import Evergreen.V11.Weather
import Evergreen.V11.Wifi
import Evergreen.V11.Wired
import Evergreen.V12.BootInfo
import Evergreen.V12.Calculator
import Evergreen.V12.Coord
import Evergreen.V12.Effect
import Evergreen.V12.HackerNews
import Evergreen.V12.Main
import Evergreen.V12.News
import Evergreen.V12.TextInput
import Evergreen.V12.TextInputMultiline
import Evergreen.V12.Ui
import Evergreen.V12.Weather
import Evergreen.V12.Wifi
import Evergreen.V12.Wired
import Quantity


model : Evergreen.V11.Main.Model -> Evergreen.V12.Main.Model
model old =
    migrate_Main_Model old


migrate_Main_Model : Evergreen.V11.Main.Model -> Evergreen.V12.Main.Model
migrate_Main_Model old =
    { screenSize = migrate_Coord_Coord old.screenSize
    , mouse = migrate_Coord_Coord old.mouse
    , colorIndex = old.colorIndex
    , pressed = old.pressed
    , renderer = Maybe.map migrate_Main_RendererInfo old.renderer
    , stats = Maybe.map migrate_Main_SystemStats old.stats
    , lastFrame = old.lastFrame
    , frameIntervals = old.frameIntervals
    , frames = old.frames
    , shift = old.shift
    , ctrl = old.ctrl
    , clipboard = old.clipboard
    , selectingText = old.selectingText
    , wifiDevice = migrate_Wifi_Device old.wifiDevice
    , networks = List.map migrate_Wifi_Network old.networks
    , scanning = old.scanning
    , wifiStatus = migrate_Wifi_Status old.wifiStatus
    , wired = List.map migrate_Wired_Link old.wired
    , selected = Maybe.map migrate_Wifi_Network old.selected
    , savedWifiPasswords = old.savedWifiPasswords
    , showPassword = old.showPassword
    , weather = migrate_Main_WeatherState old.weather
    , geoUrl = old.geoUrl
    , weatherUrl = old.weatherUrl
    , system = Maybe.map migrate_Main_SystemInfo old.system
    , bootInfo = migrate_BootInfo_Model old.bootInfo
    , aboutOpen = old.aboutOpen
    , newsOpen = old.newsOpen
    , news = migrate_News_NewsState old.news
    , hackerNews = migrate_HackerNews_Model old.hackerNews
    , calculator = migrate_Calculator_Model old.calculator
    , calculatorOpen = old.calculatorOpen
    , confirmPower = Maybe.map migrate_Main_PowerAction old.confirmPower
    , editorOpen = old.editorOpen
    , upgradingTo = old.upgradingTo
    , reflashNeeded = old.reflashNeeded
    , uiState = migrate_Ui_Model migrate_Main_UiId old.uiState
    , showUiBorders = old.showUiBorders
    }


migrate_BootInfo_Model : Evergreen.V11.BootInfo.Model -> Evergreen.V12.BootInfo.Model
migrate_BootInfo_Model old =
    { image = migrate_BootInfo_Image old.image
    , seconds = old.seconds
    , gptDisks = old.gptDisks
    , battery = Maybe.map migrate_BootInfo_Battery old.battery
    , cpufreqPolicies = old.cpufreqPolicies
    , clock = Maybe.map migrate_BootInfo_Clock old.clock
    , boot = Maybe.map migrate_BootInfo_BootTimes old.boot
    , firmwareMs = old.firmwareMs
    }


migrate_Calculator_Model : Evergreen.V11.Calculator.Model -> Evergreen.V12.Calculator.Model
migrate_Calculator_Model old =
    { entry = migrate_Calculator_Entry old.entry
    , pending = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( w3_t2_0, migrate_Calculator_Operator w3_t2_1 )) old.pending
    , repeat = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( migrate_Calculator_Operator w3_t2_0, w3_t2_1 )) old.repeat
    }


migrate_Coord_Coord : Evergreen.V11.Coord.Coord old_units -> Evergreen.V12.Coord.Coord new_units
migrate_Coord_Coord old =
    (\( w3_t1_0, w3_t1_1 ) -> ( Quantity.unsafe (Quantity.unwrap w3_t1_0), Quantity.unsafe (Quantity.unwrap w3_t1_1) )) old


migrate_HackerNews_Model : Evergreen.V11.HackerNews.Model -> Evergreen.V12.HackerNews.Model
migrate_HackerNews_Model old =
    { data = migrate_HackerNews_HackerNewsState old.data
    , page = migrate_HackerNews_Page old.page
    , comments = Dict.map (\_ -> \w3_r2 -> { opened = w3_r2.opened, state = migrate_HackerNews_CommentsState w3_r2.state }) old.comments
    , openCount = old.openCount
    , isOpen = old.isOpen
    }


migrate_Main_PowerAction : Evergreen.V11.Main.PowerAction -> Evergreen.V12.Main.PowerAction
migrate_Main_PowerAction old =
    case old of
        Evergreen.V11.Main.PowerOff ->
            Evergreen.V12.Main.PowerOff

        Evergreen.V11.Main.Restart ->
            Evergreen.V12.Main.Restart


migrate_Main_RendererInfo : Evergreen.V11.Main.RendererInfo -> Evergreen.V12.Main.RendererInfo
migrate_Main_RendererInfo old =
    { gpu = old.gpu
    , name = old.name
    , hardwareCursor = old.hardwareCursor
    }


migrate_Main_SystemInfo : Evergreen.V11.Main.SystemInfo -> Evergreen.V12.Main.SystemInfo
migrate_Main_SystemInfo old =
    { kernel = old.kernel
    , cpu = old.cpu
    , commit = old.commit
    }


migrate_Main_SystemStats : Evergreen.V11.Main.SystemStats -> Evergreen.V12.Main.SystemStats
migrate_Main_SystemStats old =
    { cores = old.cores
    , cpu = old.cpu
    , cpuElm = old.cpuElm
    , cpuHost = old.cpuHost
    , cpuGpu = old.cpuGpu
    , memUsed = old.memUsed
    , memTotal = old.memTotal
    , gpuMs = old.gpuMs
    , elmMs = old.elmMs
    , drawMs = old.drawMs
    }


migrate_Main_UiId : Evergreen.V11.Main.UiId -> Evergreen.V12.Main.UiId
migrate_Main_UiId old =
    case old of
        Evergreen.V11.Main.RefreshButton ->
            Evergreen.V12.Main.RefreshButton

        Evergreen.V11.Main.NetworkButton w3_x0 ->
            Evergreen.V12.Main.NetworkButton w3_x0

        Evergreen.V11.Main.PasswordInput ->
            Evergreen.V12.Main.PasswordInput

        Evergreen.V11.Main.ShowPasswordButton ->
            Evergreen.V12.Main.ShowPasswordButton

        Evergreen.V11.Main.ConnectButton ->
            Evergreen.V12.Main.ConnectButton

        Evergreen.V11.Main.DisconnectButton ->
            Evergreen.V12.Main.DisconnectButton

        Evergreen.V11.Main.WeatherButton ->
            Evergreen.V12.Main.WeatherButton

        Evergreen.V11.Main.AboutButton ->
            Evergreen.V12.Main.AboutButton

        Evergreen.V11.Main.NewsButton ->
            Evergreen.V12.Main.NewsButton

        Evergreen.V11.Main.CloseAboutButton ->
            Evergreen.V12.Main.CloseAboutButton

        Evergreen.V11.Main.CalculatorButton ->
            Evergreen.V12.Main.CalculatorButton

        Evergreen.V11.Main.PowerOffButton ->
            Evergreen.V12.Main.PowerOffButton

        Evergreen.V11.Main.RestartButton ->
            Evergreen.V12.Main.RestartButton

        Evergreen.V11.Main.ConfirmPowerButton ->
            Evergreen.V12.Main.ConfirmPowerButton

        Evergreen.V11.Main.CancelPowerButton ->
            Evergreen.V12.Main.CancelPowerButton

        Evergreen.V11.Main.CalculatorUiId w3_x0 ->
            Evergreen.V12.Main.CalculatorUiId (migrate_Calculator_UiId w3_x0)

        Evergreen.V11.Main.EditorButton ->
            Evergreen.V12.Main.EditorButton

        Evergreen.V11.Main.EditorInput ->
            Evergreen.V12.Main.EditorInput

        Evergreen.V11.Main.EditorWindow ->
            Evergreen.V12.Main.EditorWindow

        Evergreen.V11.Main.CloseEditorButton ->
            Evergreen.V12.Main.CloseEditorButton

        Evergreen.V11.Main.NewsUiId w3_x0 ->
            Evergreen.V12.Main.NewsUiId (migrate_News_UiId w3_x0)

        Evergreen.V11.Main.HackerNewsUiId w3_x0 ->
            Evergreen.V12.Main.HackerNewsUiId (migrate_HackerNews_UiId w3_x0)


migrate_Main_WeatherState : Evergreen.V11.Main.WeatherState -> Evergreen.V12.Main.WeatherState
migrate_Main_WeatherState old =
    case old of
        Evergreen.V11.Main.NoWeather ->
            Evergreen.V12.Main.NoWeather

        Evergreen.V11.Main.FindingPlace ->
            Evergreen.V12.Main.FindingPlace

        Evergreen.V11.Main.LoadingForecast w3_x0 ->
            Evergreen.V12.Main.LoadingForecast (migrate_Weather_Place w3_x0)

        Evergreen.V11.Main.GotWeather w3_x0 w3_x1 ->
            Evergreen.V12.Main.GotWeather (migrate_Weather_Place w3_x0) (migrate_Weather_Forecast w3_x1)

        Evergreen.V11.Main.WeatherFailed w3_x0 ->
            Evergreen.V12.Main.WeatherFailed (migrate_Effect_HttpError w3_x0)


migrate_News_NewsState : Evergreen.V11.News.NewsState -> Evergreen.V12.News.NewsState
migrate_News_NewsState old =
    case old of
        Evergreen.V11.News.NewsNotRequested ->
            Evergreen.V12.News.NewsNotRequested

        Evergreen.V11.News.LoadingNews w3_x0 ->
            Evergreen.V12.News.LoadingNews (Maybe.map (List.map migrate_News_Day) w3_x0)

        Evergreen.V11.News.LoadedNews w3_x0 ->
            Evergreen.V12.News.LoadedNews (List.map migrate_News_Day w3_x0)

        Evergreen.V11.News.NewsFailed w3_x0 ->
            Evergreen.V12.News.NewsFailed (migrate_Effect_HttpError w3_x0)


migrate_Ui_Model : (old_id -> new_id) -> Evergreen.V11.Ui.Model old_id -> Evergreen.V12.Ui.Model new_id
migrate_Ui_Model migrate_id old =
    { focus = Maybe.map migrate_id old.focus
    , uiState = Dict.map (\_ -> migrate_Ui_ElementState) old.uiState
    , scale = Quantity.unsafe 1
    }


migrate_Wifi_Device : Evergreen.V11.Wifi.Device -> Evergreen.V12.Wifi.Device
migrate_Wifi_Device old =
    case old of
        Evergreen.V11.Wifi.Unknown ->
            Evergreen.V12.Wifi.Unknown

        Evergreen.V11.Wifi.NoCard ->
            Evergreen.V12.Wifi.NoCard

        Evergreen.V11.Wifi.Card w3_x0 ->
            Evergreen.V12.Wifi.Card w3_x0


migrate_Wifi_Network : Evergreen.V11.Wifi.Network -> Evergreen.V12.Wifi.Network
migrate_Wifi_Network old =
    { ssid = old.ssid
    , signal = old.signal
    , security = migrate_Wifi_Security old.security
    }


migrate_Wifi_Status : Evergreen.V11.Wifi.Status -> Evergreen.V12.Wifi.Status
migrate_Wifi_Status old =
    { state = migrate_Wifi_State old.state
    , ssid = old.ssid
    , ip = old.ip
    , error = old.error
    }


migrate_Wired_Link : Evergreen.V11.Wired.Link -> Evergreen.V12.Wired.Link
migrate_Wired_Link old =
    { name = old.name
    , state = migrate_Wired_State old.state
    , ip = old.ip
    }


migrate_BootInfo_Battery : Evergreen.V11.BootInfo.Battery -> Evergreen.V12.BootInfo.Battery
migrate_BootInfo_Battery old =
    { batteries = old.batteries
    , percent = old.percent
    , status = old.status
    , minutes = old.minutes
    }


migrate_BootInfo_BootTimes : Evergreen.V11.BootInfo.BootTimes -> Evergreen.V12.BootInfo.BootTimes
migrate_BootInfo_BootTimes old =
    { initMs = old.initMs
    , elmMs = old.elmMs
    , frameMs = old.frameMs
    }


migrate_BootInfo_Clock : Evergreen.V11.BootInfo.Clock -> Evergreen.V12.BootInfo.Clock
migrate_BootInfo_Clock old =
    { minMhz = old.minMhz
    , maxMhz = old.maxMhz
    , limitMhz = old.limitMhz
    , governor = old.governor
    , hint = old.hint
    }


migrate_BootInfo_Image : Evergreen.V11.BootInfo.Image -> Evergreen.V12.BootInfo.Image
migrate_BootInfo_Image old =
    case old of
        Evergreen.V11.BootInfo.Hashing w3_x0 ->
            Evergreen.V12.BootInfo.Hashing w3_x0

        Evergreen.V11.BootInfo.LookingForStick ->
            Evergreen.V12.BootInfo.LookingForStick

        Evergreen.V11.BootInfo.Hashed w3_x0 w3_x1 ->
            Evergreen.V12.BootInfo.Hashed w3_x0 w3_x1

        Evergreen.V11.BootInfo.NoImage ->
            Evergreen.V12.BootInfo.NoImage


migrate_Calculator_Entry : Evergreen.V11.Calculator.Entry -> Evergreen.V12.Calculator.Entry
migrate_Calculator_Entry old =
    case old of
        Evergreen.V11.Calculator.Typed w3_x0 ->
            Evergreen.V12.Calculator.Typed w3_x0

        Evergreen.V11.Calculator.Shown w3_x0 ->
            Evergreen.V12.Calculator.Shown w3_x0

        Evergreen.V11.Calculator.Error ->
            Evergreen.V12.Calculator.Error


migrate_Calculator_Operator : Evergreen.V11.Calculator.Operator -> Evergreen.V12.Calculator.Operator
migrate_Calculator_Operator old =
    case old of
        Evergreen.V11.Calculator.Add ->
            Evergreen.V12.Calculator.Add

        Evergreen.V11.Calculator.Subtract ->
            Evergreen.V12.Calculator.Subtract

        Evergreen.V11.Calculator.Multiply ->
            Evergreen.V12.Calculator.Multiply

        Evergreen.V11.Calculator.Divide ->
            Evergreen.V12.Calculator.Divide


migrate_HackerNews_CommentsState : Evergreen.V11.HackerNews.CommentsState -> Evergreen.V12.HackerNews.CommentsState
migrate_HackerNews_CommentsState old =
    case old of
        Evergreen.V11.HackerNews.CommentsLoading ->
            Evergreen.V12.HackerNews.CommentsLoading

        Evergreen.V11.HackerNews.CommentsLoaded w3_x0 ->
            Evergreen.V12.HackerNews.CommentsLoaded (List.map migrate_HackerNews_Comment w3_x0)

        Evergreen.V11.HackerNews.CommentsLoadFailed w3_x0 ->
            Evergreen.V12.HackerNews.CommentsLoadFailed (migrate_Effect_HttpError w3_x0)


migrate_HackerNews_HackerNewsState : Evergreen.V11.HackerNews.HackerNewsState -> Evergreen.V12.HackerNews.HackerNewsState
migrate_HackerNews_HackerNewsState old =
    case old of
        Evergreen.V11.HackerNews.NotLoading ->
            Evergreen.V12.HackerNews.NotLoading

        Evergreen.V11.HackerNews.Loading w3_x0 ->
            Evergreen.V12.HackerNews.NotLoading

        Evergreen.V11.HackerNews.Loaded w3_x0 ->
            Evergreen.V12.HackerNews.NotLoading

        Evergreen.V11.HackerNews.LoadFailed w3_x0 ->
            Evergreen.V12.HackerNews.LoadFailed (migrate_Effect_HttpError w3_x0)


migrate_HackerNews_Page : Evergreen.V11.HackerNews.Page -> Evergreen.V12.HackerNews.Page
migrate_HackerNews_Page old =
    case old of
        Evergreen.V11.HackerNews.PostsPage ->
            Evergreen.V12.HackerNews.PostsPage

        Evergreen.V11.HackerNews.CommentsPage w3_x0 w3_x1 ->
            Evergreen.V12.HackerNews.CommentsPage (migrate_HackerNews_PostId w3_x0) w3_x1


migrate_Calculator_UiId : Evergreen.V11.Calculator.UiId -> Evergreen.V12.Calculator.UiId
migrate_Calculator_UiId old =
    case old of
        Evergreen.V11.Calculator.KeyButton w3_x0 ->
            Evergreen.V12.Calculator.KeyButton (migrate_Calculator_Key w3_x0)

        Evergreen.V11.Calculator.CloseButton ->
            Evergreen.V12.Calculator.CloseButton

        Evergreen.V11.Calculator.Panel ->
            Evergreen.V12.Calculator.Panel


migrate_HackerNews_UiId : Evergreen.V11.HackerNews.UiId -> Evergreen.V12.HackerNews.UiId
migrate_HackerNews_UiId old =
    case old of
        Evergreen.V11.HackerNews.NewsPostButton w3_x0 ->
            Evergreen.V12.HackerNews.NewsPostButton (migrate_HackerNews_PostId w3_x0)

        Evergreen.V11.HackerNews.OpenButton ->
            Evergreen.V12.HackerNews.OpenButton

        Evergreen.V11.HackerNews.PostsViewport ->
            Evergreen.V12.HackerNews.PostsViewport

        Evergreen.V11.HackerNews.CommentsViewport ->
            Evergreen.V12.HackerNews.PostsViewport

        Evergreen.V11.HackerNews.BackButton ->
            Evergreen.V12.HackerNews.BackButton

        Evergreen.V11.HackerNews.CommentToggle w3_x0 ->
            Evergreen.V12.HackerNews.CommentToggle w3_x0


migrate_News_UiId : Evergreen.V11.News.UiId -> Evergreen.V12.News.UiId
migrate_News_UiId old =
    case old of
        Evergreen.V11.News.NewsViewport ->
            Evergreen.V12.News.NewsViewport


migrate_Effect_HttpError : Evergreen.V11.Effect.HttpError -> Evergreen.V12.Effect.HttpError
migrate_Effect_HttpError old =
    case old of
        Evergreen.V11.Effect.BadUrl w3_x0 ->
            Evergreen.V12.Effect.BadUrl w3_x0

        Evergreen.V11.Effect.Timeout ->
            Evergreen.V12.Effect.Timeout

        Evergreen.V11.Effect.NetworkError w3_x0 ->
            Evergreen.V12.Effect.NetworkError w3_x0

        Evergreen.V11.Effect.Interrupted ->
            Evergreen.V12.Effect.Interrupted

        Evergreen.V11.Effect.BadBody w3_x0 ->
            Evergreen.V12.Effect.BadBody w3_x0

        Evergreen.V11.Effect.FailedToDecodeBody w3_x0 ->
            Evergreen.V12.Effect.FailedToDecodeBody w3_x0


migrate_Weather_Forecast : Evergreen.V11.Weather.Forecast -> Evergreen.V12.Weather.Forecast
migrate_Weather_Forecast old =
    { temperature = old.temperature
    , humidity = old.humidity
    , wind = old.wind
    , code = old.code
    , time = old.time
    , days = List.map migrate_Weather_Day old.days
    }


migrate_Weather_Place : Evergreen.V11.Weather.Place -> Evergreen.V12.Weather.Place
migrate_Weather_Place old =
    { latitude = old.latitude
    , longitude = old.longitude
    , name = old.name
    }


migrate_News_Day : Evergreen.V11.News.Day -> Evergreen.V12.News.Day
migrate_News_Day old =
    { date = old.date
    , topics = List.map migrate_News_Topic old.topics
    }


migrate_Ui_ElementState : Evergreen.V11.Ui.ElementState -> Evergreen.V12.Ui.ElementState
migrate_Ui_ElementState old =
    case old of
        Evergreen.V11.Ui.TextInputState w3_x0 ->
            Evergreen.V12.Ui.TextInputState (migrate_TextInput_Model w3_x0)

        Evergreen.V11.Ui.TextInputMultilineState w3_x0 ->
            Evergreen.V12.Ui.TextInputMultilineState (migrate_TextInputMultiline_Model w3_x0)

        Evergreen.V11.Ui.ViewportState w3_x0 ->
            Evergreen.V12.Ui.ViewportState (migrate_Ui_ViewportModel w3_x0)


migrate_Wifi_Security : Evergreen.V11.Wifi.Security -> Evergreen.V12.Wifi.Security
migrate_Wifi_Security old =
    case old of
        Evergreen.V11.Wifi.Open ->
            Evergreen.V12.Wifi.Open

        Evergreen.V11.Wifi.Wpa ->
            Evergreen.V12.Wifi.Wpa

        Evergreen.V11.Wifi.Enterprise ->
            Evergreen.V12.Wifi.Enterprise

        Evergreen.V11.Wifi.Wep ->
            Evergreen.V12.Wifi.Wep

        Evergreen.V11.Wifi.Wpa3 ->
            Evergreen.V12.Wifi.Wpa3


migrate_Wifi_State : Evergreen.V11.Wifi.State -> Evergreen.V12.Wifi.State
migrate_Wifi_State old =
    case old of
        Evergreen.V11.Wifi.Idle ->
            Evergreen.V12.Wifi.Idle

        Evergreen.V11.Wifi.Connecting ->
            Evergreen.V12.Wifi.Connecting

        Evergreen.V11.Wifi.Dhcp ->
            Evergreen.V12.Wifi.Dhcp

        Evergreen.V11.Wifi.Connected ->
            Evergreen.V12.Wifi.Connected

        Evergreen.V11.Wifi.Failed ->
            Evergreen.V12.Wifi.Failed


migrate_Wired_State : Evergreen.V11.Wired.State -> Evergreen.V12.Wired.State
migrate_Wired_State old =
    case old of
        Evergreen.V11.Wired.NoCable ->
            Evergreen.V12.Wired.NoCable

        Evergreen.V11.Wired.Dhcp ->
            Evergreen.V12.Wired.Dhcp

        Evergreen.V11.Wired.Connected ->
            Evergreen.V12.Wired.Connected

        Evergreen.V11.Wired.Failed ->
            Evergreen.V12.Wired.Failed


migrate_HackerNews_Comment : Evergreen.V11.HackerNews.Comment -> Evergreen.V12.HackerNews.Comment
migrate_HackerNews_Comment old =
    case old of
        Evergreen.V11.HackerNews.Comment w3_x0 ->
            Evergreen.V12.HackerNews.Comment
                ((\w3_r1 ->
                    { index = w3_r1.index
                    , author = w3_r1.author
                    , date = Nothing
                    , grey = 0
                    , content = w3_r1.content
                    , children = List.map migrate_HackerNews_Comment w3_r1.children
                    , descendants = w3_r1.descendants
                    , isExpanded = w3_r1.isExpanded
                    }
                 )
                    w3_x0
                )


migrate_HackerNews_PostId : Evergreen.V11.HackerNews.PostId -> Evergreen.V12.HackerNews.PostId
migrate_HackerNews_PostId old =
    case old of
        Evergreen.V11.HackerNews.PostId w3_x0 ->
            Evergreen.V12.HackerNews.PostId w3_x0


migrate_Calculator_Key : Evergreen.V11.Calculator.Key -> Evergreen.V12.Calculator.Key
migrate_Calculator_Key old =
    case old of
        Evergreen.V11.Calculator.Digit w3_x0 ->
            Evergreen.V12.Calculator.Digit w3_x0

        Evergreen.V11.Calculator.Point ->
            Evergreen.V12.Calculator.Point

        Evergreen.V11.Calculator.Operator w3_x0 ->
            Evergreen.V12.Calculator.Operator (migrate_Calculator_Operator w3_x0)

        Evergreen.V11.Calculator.Equals ->
            Evergreen.V12.Calculator.Equals

        Evergreen.V11.Calculator.Negate ->
            Evergreen.V12.Calculator.Negate

        Evergreen.V11.Calculator.Backspace ->
            Evergreen.V12.Calculator.Backspace

        Evergreen.V11.Calculator.Clear ->
            Evergreen.V12.Calculator.Clear


migrate_Weather_Day : Evergreen.V11.Weather.Day -> Evergreen.V12.Weather.Day
migrate_Weather_Day old =
    { date = old.date
    , code = old.code
    , high = old.high
    , low = old.low
    }


migrate_News_Topic : Evergreen.V11.News.Topic -> Evergreen.V12.News.Topic
migrate_News_Topic old =
    { heading = old.heading
    , items = List.map migrate_News_Item old.items
    }


migrate_TextInput_Model : Evergreen.V11.TextInput.Model -> Evergreen.V12.TextInput.Model
migrate_TextInput_Model old =
    { current = migrate_TextInput_State old.current
    , undoHistory = List.map migrate_TextInput_State old.undoHistory
    , redoHistory = List.map migrate_TextInput_State old.redoHistory
    }


migrate_TextInputMultiline_Model : Evergreen.V11.TextInputMultiline.Model -> Evergreen.V12.TextInputMultiline.Model
migrate_TextInputMultiline_Model old =
    { input = migrate_TextInput_Model old.input
    , scroll = old.scroll
    , goalX = old.goalX
    }


migrate_Ui_ViewportModel : Evergreen.V11.Ui.ViewportModel -> Evergreen.V12.Ui.ViewportModel
migrate_Ui_ViewportModel old =
    { offset = Quantity.unsafe (Quantity.unwrap old.offset)
    , target = Quantity.unsafe (Quantity.unwrap old.target)
    }


migrate_News_Item : Evergreen.V11.News.Item -> Evergreen.V12.News.Item
migrate_News_Item old =
    case old of
        Evergreen.V11.News.Item w3_x0 ->
            Evergreen.V12.News.Item ((\w3_r1 -> { content = List.map migrate_News_Inline w3_r1.content, children = List.map migrate_News_Item w3_r1.children }) w3_x0)


migrate_TextInput_State : Evergreen.V11.TextInput.State -> Evergreen.V12.TextInput.State
migrate_TextInput_State old =
    { cursorPosition = old.cursorPosition
    , cursorSize = old.cursorSize
    , text = old.text
    }


migrate_News_Inline : Evergreen.V11.News.Inline -> Evergreen.V12.News.Inline
migrate_News_Inline old =
    case old of
        Evergreen.V11.News.Text w3_x0 ->
            Evergreen.V12.News.Text w3_x0

        Evergreen.V11.News.WikiLink w3_x0 ->
            Evergreen.V12.News.WikiLink w3_x0

        Evergreen.V11.News.ExternalLink w3_x0 ->
            Evergreen.V12.News.ExternalLink w3_x0
