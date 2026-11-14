module Transient exposing (Transient, empty, get, wrap)

{-| A value that lives only in memory: the Model and Msgs can hold one, but it is
never saved. tools/wire writes a `Transient a` as `[]` and reads it back as `empty`,
whatever `a` is, without looking inside it, so `a` can be anything: a running game, a
file's bytes, a cache, even a type with functions in it. A frozen version of the
Model (elm/src/Evergreen) keeps it as a `Transient ()`.

After a restart (Persist.elm) every Transient is `empty`, and so is one in a Msg
replayed from the log. So put in a Transient only what the program can do without
after a restart: something it can make again (read the file again, start the game
again) or lose.

-}


type Transient a
    = Transient (Maybe a)


{-| Nothing in it, as after a restart.
-}
empty : Transient a
empty =
    Transient Nothing


wrap : a -> Transient a
wrap value =
    Transient (Just value)


{-| The value, or Nothing if it is `empty` (it never was there, or there was a
restart since).
-}
get : Transient a -> Maybe a
get (Transient value) =
    value
