module Evergreen.V19.Email exposing (..)

{-| The email app: link an account, then list the inbox and read messages. Read only:
nothing is sent, deleted or marked as read (it uses EXAMINE and BODY.PEEK).

It speaks IMAP over TLS (port 993) with a user name and an app password. The host only
moves bytes (Effect.TlsOpen, host/init/src/tls\_socket.rs); the protocol is here, parsed
by Email.Imap. There is no connection kept open: each refresh or message opened is a
short session that logs in, reads what it needs and leaves.

The password is kept in the Model, so it is saved with the rest of it on the data disk,
not encrypted. Gmail and Outlook only accept an app password, not the account's
own, and Outlook.com has turned that off for many accounts.

-}

import Bytes exposing (Bytes)
import Bytes.Encode as BE
import Evergreen.V19.Color
import Evergreen.V19.Coord exposing (Coord)
import Evergreen.V19.Effect
import Evergreen.V19.Email.Imap as Imap
import Evergreen.V19.Email.Types exposing (Field(..))
import Evergreen.V19.Sprite exposing (Font(..), FontSize(..), Style(..))
import Evergreen.V19.TextInput
import Evergreen.V19.Ui exposing (Element)
import Evergreen.V19.UiId exposing (UiId(..))
import Evergreen.V19.Units exposing (UiPixels)
import Quantity exposing (Quantity)


type alias Model =
    { isOpen : Bool
    , account : Maybe Account
    , inbox : List Summary
    , page : Page
    , session : Maybe Session
    , sessionCount : Int
    , error : Maybe String
    }


type alias Account =
    { server : String
    , address : String
    , password : String
    }


type alias Summary =
    { uid : Int
    , from : String
    , subject : String
    , date : String
    , seen : Bool
    }


type Page
    = InboxPage
    | MessagePage { uid : Int, state : MessageState }


type MessageState
    = MessageLoading
    | MessageLoaded String
    | MessageFailed String


{-| One trip to the server: connect, log in, read, leave.
-}
type alias Session =
    { id : String
    , job : Job
    , stage : Stage
    , buffer : String
    , exists : Int
    , results : List Imap.Fetched
    , startedAt : Maybe Int
    }


type Job
    = ListInbox
    | ReadMessage Int


type Stage
    = Connecting
    | WaitingForGreeting
    | LoggingIn
    | Selecting
    | Fetching



-- UPDATE
-- VIEW
