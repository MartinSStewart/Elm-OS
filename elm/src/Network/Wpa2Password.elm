module Network.Wpa2Password exposing (Wpa2Password, fromString, toString)


type Wpa2Password
    = Wpa2Password String


fromString : String -> Result String Wpa2Password
fromString string =
    if String.length string < 8 then
        Err "Too short"

    else if String.length string > 63 then
        Err "Too long"

    else
        Ok (Wpa2Password string)


toString : Wpa2Password -> String
toString (Wpa2Password wpa2Password) =
    wpa2Password
