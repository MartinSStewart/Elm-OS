module ScreenshotViewer exposing
    ( Model
    , areaSize
    , dragged
    , init
    , onClick
    , screenshotAdded
    , scrolledBy
    , startDragging
    , stopDragging
    , view
    , wheel
    )

{-| The screenshot viewer app: a list of previews of the screenshots taken so far
(Main's `screenshots`, newest first), and the one picked, which can be dragged around and
zoomed.

A screenshot is the UI as it was, so it is drawn again, as a screen with the same UI scale
would draw it, and then scaled: the picture's pixels are device pixels, and a zoom of 1 puts
each on one pixel of the screen. Zoomed in, they are sampled by the nearest pixel, so they
show as the blocks they are; zoomed out, they are blended (`Sprite.Linear`).

-}

import Color
import Coord exposing (Coord)
import ScreenshotViewer.Types as Types
import SeqDict
import Sprite exposing (Sampling(..), Triangle)
import Ui exposing (Element)
import UiId exposing (UiId(..))
import Units exposing (UiPixels, UiScale)


type alias Model =
    { isOpen : Bool

    -- The picture shown: its place in Main's screenshots, newest first.
    , selected : Maybe Int

    -- Screen pixels for each pixel of the picture: 1 is its actual size.
    , zoom : Float

    -- Where the picture's top left corner is, from the top left corner of its area, in UI pixels.
    , offset : ( Float, Float )

    -- The mouse button is down on the picture, and moving the mouse moves the picture.
    , dragging : Bool
    }


init : Model
init =
    { isOpen = False, selected = Nothing, zoom = 1, offset = ( 0, 0 ), dragging = False }


minZoom : Float
minZoom =
    1 / 32


maxZoom : Float
maxZoom =
    32


{-| How much each wheel click, or press of a zoom button, zooms.
-}
zoomStep : Float
zoomStep =
    1.25



-- LAYOUT


windowMargin : Int
windowMargin =
    8


windowPadding : Int
windowPadding =
    8


spacing : Int
spacing =
    6


{-| How big the biggest preview is: its width and its height, in UI pixels.
-}
previewSize : Coord UiPixels
previewSize =
    Coord.xy 160 100


buttonPadding : Int
buttonPadding =
    4


{-| The list of previews is this wide, scroll bar room and all.
-}
listWidth : Int
listWidth =
    Coord.xRaw previewSize + 2 * buttonPadding


headerHeight : Int
headerHeight =
    Coord.yRaw (Ui.size (headerButton Types.CloseButton "Close"))


{-| The size of the area the screenshot is shown in, on a screen of the given size
(UI pixels) with the toolbar taking `top` of its height.
-}
areaSize : Coord UiPixels -> Int -> Coord UiPixels
areaSize screen top =
    Coord.xy
        (max 1 (Coord.xRaw screen - 2 * windowMargin - 2 * windowPadding - listWidth - spacing))
        (max 1 (Coord.yRaw screen - top - 2 * windowMargin - 2 * windowPadding - headerHeight - spacing))



-- UPDATE


{-| A screenshot was added at the front of the list: the one shown is one place further on.
-}
screenshotAdded : Model -> Model
screenshotAdded model =
    { model | selected = Maybe.map ((+) 1) model.selected }


{-| A click on one of the viewer's buttons. Takes the area the picture is in, and the
screenshots.
-}
onClick : Coord UiPixels -> List Ui.Screenshot -> Types.UiId -> Model -> Model
onClick area screenshots id model =
    case id of
        Types.OpenButton ->
            { model | isOpen = not model.isOpen, dragging = False }

        Types.CloseButton ->
            { model | isOpen = False, dragging = False }

        Types.PreviewList ->
            model

        Types.Preview index ->
            case nth index screenshots of
                Just screenshot ->
                    fit area screenshot { model | selected = Just index }

                Nothing ->
                    model

        Types.ImageArea ->
            model

        Types.ZoomInButton ->
            zoomAbout (centre area) zoomStep model

        Types.ZoomOutButton ->
            zoomAbout (centre area) (1 / zoomStep) model

        Types.ActualSizeButton ->
            zoomAbout (centre area) (1 / model.zoom) model

        Types.FitButton ->
            case Maybe.andThen (\index -> nth index screenshots) model.selected of
                Just screenshot ->
                    fit area screenshot model

                Nothing ->
                    model


{-| The wheel turned over the picture, with the mouse at the given point of its area:
zooms in for clicks up (positive), keeping the point under the mouse where it is.
-}
wheel : Coord UiPixels -> Int -> Model -> Model
wheel mouse clicks model =
    zoomAbout (Coord.toTuple mouse |> Tuple.mapBoth toFloat toFloat) (zoomStep ^ toFloat clicks) model


{-| Two fingers scrolled the touchpad over the picture by this many UI pixels (positive is
down, the picture following): moves it, across when `across` (shift is held).
-}
scrolledBy : Bool -> Float -> Model -> Model
scrolledBy across pixels model =
    let
        ( x, y ) =
            model.offset
    in
    { model
        | offset =
            if across then
                ( x - pixels, y )

            else
                ( x, y - pixels )
    }


startDragging : Model -> Model
startDragging model =
    { model | dragging = True }


stopDragging : Model -> Model
stopDragging model =
    { model | dragging = False }


{-| The mouse moved by this much (UI pixels): moves the picture with it, if it is held.
-}
dragged : Coord UiPixels -> Model -> Model
dragged by model =
    if model.dragging then
        { model | offset = Tuple.mapBoth ((+) (toFloat (Coord.xRaw by))) ((+) (toFloat (Coord.yRaw by))) model.offset }

    else
        model


{-| Zooms to the whole picture in the area, in the middle.
-}
fit : Coord UiPixels -> Ui.Screenshot -> Model -> Model
fit area screenshot model =
    let
        ( w, h ) =
            Coord.toTuple (Ui.screenshotSize screenshot) |> Tuple.mapBoth toFloat toFloat

        ( areaW, areaH ) =
            Coord.toTuple area |> Tuple.mapBoth toFloat toFloat

        zoom =
            clamp minZoom maxZoom (min (areaW / max 1 w) (areaH / max 1 h))

    in
    { model
        | zoom = zoom
        , offset = ( toFloat (round ((areaW - w * zoom) / 2)), toFloat (round ((areaH - h * zoom) / 2)) )
    }


centre : Coord UiPixels -> ( Float, Float )
centre area =
    ( toFloat (Coord.xRaw area) / 2, toFloat (Coord.yRaw area) / 2 )


{-| Zooms by a factor with the given point of the area staying where it is on the picture.
-}
zoomAbout : ( Float, Float ) -> Float -> Model -> Model
zoomAbout ( x, y ) factor model =
    let
        zoom =
            clamp minZoom maxZoom (model.zoom * factor)

        k =
            zoom / model.zoom

        ( offsetX, offsetY ) =
            model.offset
    in
    { model | zoom = zoom, offset = ( toFloat (round (x - (x - offsetX) * k)), toFloat (round (y - (y - offsetY) * k)) ) }


nth : Int -> List a -> Maybe a
nth index list =
    List.drop index list |> List.head



-- VIEW


{-| The viewer's window, under the toolbar (`top` UI pixels high), for a screen the
given size.
-}
view : UiScale -> Coord UiPixels -> Int -> Ui.Model UiId -> List Ui.Screenshot -> Model -> Element UiId
view scale screen top uiState screenshots model =
    let
        area =
            areaSize screen top

        header =
            Ui.leftAndRight
                (Units.uiPixels (Coord.xRaw area + listWidth + spacing))
                (Ui.row { spacing = spacing, padding = Ui.noPadding }
                    [ headerButton Types.ZoomOutButton "-"
                    , headerButton Types.ZoomInButton "+"
                    , headerButton Types.ActualSizeButton "100%"
                    , headerButton Types.FitButton "Fit"
                    , Ui.el { padding = Ui.paddingXY 6 3, inFront = [], borderAndFill = Ui.NoBorderOrFill }
                        (text
                            (case model.selected of
                                Just _ ->
                                    String.fromInt (round (model.zoom * 100)) ++ "%"

                                Nothing ->
                                    ""
                            )
                        )
                    ]
                )
                (headerButton Types.CloseButton "Close")
    in
    Ui.topLeft { size = screen }
        (Ui.el
            { padding = { topLeft = Coord.xy windowMargin (top + windowMargin), bottomRight = Coord.origin }
            , inFront = []
            , borderAndFill = Ui.NoBorderOrFill
            }
            (Ui.el
                { padding = Ui.paddingXY windowPadding windowPadding
                , inFront = []
                , borderAndFill = Ui.defaultElBorderAndFill
                }
                (Ui.column { spacing = spacing, padding = Ui.noPadding }
                    [ header
                    , Ui.row { spacing = spacing, padding = Ui.noPadding }
                        [ previewList scale uiState (Coord.yRaw area) screenshots model
                        , imageArea scale area screenshots model
                        ]
                    ]
                )
            )
        )


headerButton : Types.UiId -> String -> Element UiId
headerButton id label =
    Ui.button { id = ScreenshotViewer id, padding = Ui.paddingXY 6 3 } (text label)


text : String -> Element UiId
text =
    Ui.text Sprite.Small (Sprite.Sans Sprite.Regular)


previewList : UiScale -> Ui.Model UiId -> Int -> List Ui.Screenshot -> Model -> Element UiId
previewList scale uiState height screenshots model =
    Ui.viewport
        { id = ScreenshotViewer Types.PreviewList
        , viewportHeight = Units.uiPixels height
        , model =
            case SeqDict.get (ScreenshotViewer Types.PreviewList) uiState.uiState of
                Just (Ui.ViewportState viewport) ->
                    viewport

                _ ->
                    Ui.initViewportModel
        }
        (Ui.column { spacing = spacing, padding = Ui.noPadding }
            (if List.isEmpty screenshots then
                [ Ui.el
                    { padding = Ui.paddingXY buttonPadding buttonPadding, inFront = [], borderAndFill = Ui.NoBorderOrFill }
                    (Ui.customTextWrapped Sprite.Small
                        (Units.uiPixels (Coord.xRaw previewSize))
                        [ { text = "No screenshots yet. Press Print Screen, then click what to capture.", color = Color.black, font = Sprite.Sans Sprite.Regular } ]
                    )
                ]

             else
                List.indexedMap (preview scale model) screenshots
            )
        )


preview : UiScale -> Model -> Int -> Ui.Screenshot -> Element UiId
preview scale model index screenshot =
    let
        ( w, h ) =
            Coord.toTuple (Ui.screenshotSize screenshot) |> Tuple.mapBoth toFloat toFloat

        ( maxW, maxH ) =
            Coord.toTuple previewSize |> Tuple.mapBoth toFloat toFloat

        zoom =
            min (maxW / max 1 w) (maxH / max 1 h)
    in
    Ui.selectableButton
        { id = ScreenshotViewer (Types.Preview index), padding = Ui.paddingXY buttonPadding buttonPadding }
        (model.selected == Just index)
        (Ui.quads
            { size = Coord.xy (ceiling (w * zoom)) (ceiling (h * zoom))
            , triangles = pictureTriangles scale zoom ( 0, 0 ) (Coord.xy (ceiling (w * zoom)) (ceiling (h * zoom))) screenshot
            }
        )


imageArea : UiScale -> Coord UiPixels -> List Ui.Screenshot -> Model -> Element UiId
imageArea scale area screenshots model =
    let
        background : List (Triangle UiPixels)
        background =
            Sprite.rectangle (Color.rgb255 60 60 60) { topLeft = Coord.origin, bottomRight = area } Coord.origin area
    in
    Ui.elWithId (ScreenshotViewer Types.ImageArea)
        { padding = Ui.noPadding, inFront = [], borderAndFill = Ui.NoBorderOrFill }
        (Ui.quads
            { size = area
            , triangles =
                background
                    ++ (case Maybe.andThen (\index -> nth index screenshots) model.selected of
                            Just screenshot ->
                                pictureTriangles scale model.zoom model.offset area screenshot

                            Nothing ->
                                []
                       )
            }
        )


{-| A screenshot drawn `zoom` times as big as a screen of this UI scale shows it, with its
top left corner at the given point of a box of the given size, and cut off at the box.
-}
pictureTriangles : UiScale -> Float -> ( Float, Float ) -> Coord UiPixels -> Ui.Screenshot -> List (Triangle UiPixels)
pictureTriangles scale zoom offset box screenshot =
    let
        -- The picture is in device pixels, the box in UI pixels.
        uiPerDevice =
            1 / toFloat (Units.scaleInt scale)

        ( boxW, boxH ) =
            Coord.toTuple box |> Tuple.mapBoth toFloat toFloat
    in
    Ui.screenshotView scale screenshot
        |> Sprite.scaleAndMove (zoom * uiPerDevice) offset
        |> Sprite.clipTo { left = 0, top = 0, right = boxW, bottom = boxH }
        |> Sprite.sampled
            (if zoom >= 1 then
                Nearest

             else
                Linear
            )
