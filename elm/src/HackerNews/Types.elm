module HackerNews.Types exposing (Comment(..), Post, PostId(..), UiId(..))

{-| The Hacker News app's data that its `Ui.lazy` views take, and its ids need: here
rather than in HackerNews.elm, as UiId.elm can't import a module that imports it.
-}


type PostId
    = PostId String


{-| A post on the front page, with how many comments it has.
-}
type alias Post =
    { id : PostId
    , title : String
    , comments : Int
    }


{-| A comment and its replies. `index` is its place in the page (from 0), which tells
the buttons apart; `descendants` counts the replies at every depth under it. `date` is
when it was written, as the page gives it (UTC), if it does. `grey` is how light its text
is, from 0 (black) up: Hacker News fades the text of a comment that was voted down.
-}
type Comment
    = Comment
        { index : Int
        , author : String
        , date : Maybe String
        , grey : Int
        , content : String
        , children : List Comment
        , descendants : Int
        , isExpanded : Bool
        }


type UiId
    = PostButton PostId
    | OpenButton
    | PostsViewport
    | CommentsViewport PostId
    | BackButton
    | CommentToggle Int
