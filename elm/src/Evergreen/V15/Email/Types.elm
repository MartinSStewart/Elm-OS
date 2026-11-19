module Evergreen.V15.Email.Types exposing (..)

{-| The email app's ids, here rather than in Email.elm because UiId.elm imports them and
can't import a module that imports it.
-}


{-| The boxes in the form that links an account.
-}
type Field
    = AddressField
    | PasswordField
    | ServerField


type UiId
    = OpenButton
    | CloseButton
    | InputField Field
    | LinkButton
    | RefreshButton
    | SignOutButton
    | BackButton
      -- A message in the list, by its IMAP UID.
    | MessageButton Int
    | ListViewport
    | MessageViewport
