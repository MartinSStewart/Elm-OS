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

A screenshot is the UI as it was, so it is drawn again, as the screen it was taken on
drew it (with that screen's UI scale, so with the same glyphs), and then scaled: the
picture's pixels are that screen's pixels, and a zoom of 1 puts each on one pixel of the
screen showing it. From 2 up they are sampled by the nearest pixel, so they show as the
blocks they are; below that, they are blended (`Sprite.Linear`).

-}

import Color
import Coord exposing (Coord)
import ScreenshotViewer.Types as Types
import Sprite exposing (Sampling(..), Triangle)
import Ui exposing (Element)
import UiId exposing (UiId(..))
import Units exposing (UiPixels, UiScale)


type alias Model =
    { isOpen : Bool

    -- The picture shown: its place in Main's screenshots, newest first.
    , selected : Maybe Int

    -- Pixels of the screen showing it for each pixel of the picture: 1 is its actual size.
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


windowPadding : Int
windowPadding =
    8


gap : Int
gap =
    6


{-| How big the biggest preview is: its width and its height, in UI pixels.
-}
previewSize : Coord UiPixels
previewSize =
    Coord.xy 160 100


buttonPadding : Int
buttonPadding =
    4


{-| The list of previews is this wide, its viewport's outline and scroll bar and all.
-}
listWidth : Int
listWidth =
    Coord.xRaw previewSize + 2 * buttonPadding


headerHeight : Int
headerHeight =
    Coord.yRaw (Ui.size (headerButton Types.CloseButton "Close"))


{-| The size of the area the screenshot is shown in, in a window of the given size
(UI pixels).
-}
areaSize : Coord UiPixels -> Coord UiPixels
areaSize window =
    Coord.xy
        (max 1 (Coord.xRaw window - 2 * windowPadding - listWidth - gap))
        (max 1 (Coord.yRaw window - 2 * windowPadding - headerHeight - gap))



-- UPDATE


{-| A screenshot was added at the front of the list: the one shown is one place further on.
-}
screenshotAdded : Model -> Model
screenshotAdded model =
    { model | selected = Maybe.map ((+) 1) model.selected }


{-| A click on one of the viewer's buttons. Takes the UI scale of the screen the viewer is
on, the area the picture is in, and the screenshots.
-}
onClick : UiScale -> Coord UiPixels -> List Ui.Screenshot -> Types.UiId -> Model -> Model
onClick scale area screenshots id model =
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
                    fit scale area screenshot { model | selected = Just index }

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
                    fit scale area screenshot model

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


{-| Zooms to the whole picture in the area, in the middle, on a screen with the given UI
scale.
-}
fit : UiScale -> Coord UiPixels -> Ui.Screenshot -> Model -> Model
fit scale area screenshot model =
    let
        -- The picture's size in UI pixels of this screen at a zoom of 1.
        ( w, h ) =
            pictureSize screenshot |> Tuple.mapBoth (\x -> x * uiPerScreenPixel scale) (\y -> y * uiPerScreenPixel scale)

        ( areaW, areaH ) =
            Coord.toTuple area |> Tuple.mapBoth toFloat toFloat

        zoom =
            clamp minZoom maxZoom (min (areaW / max 1 w) (areaH / max 1 h))
    in
    { model
        | zoom = zoom
        , offset = ( toFloat (round ((areaW - w * zoom) / 2)), toFloat (round ((areaH - h * zoom) / 2)) )
    }


{-| A screenshot's size in pixels of the screen it was taken on.
-}
pictureSize : Ui.Screenshot -> ( Float, Float )
pictureSize screenshot =
    Coord.toTuple (Ui.screenshotSize screenshot.screenshot)
        |> Tuple.mapBoth
            (\w -> toFloat (w * Units.scaleInt screenshot.uiScale))
            (\h -> toFloat (h * Units.scaleInt screenshot.uiScale))


uiPerScreenPixel : UiScale -> Float
uiPerScreenPixel scale =
    1 / toFloat (Units.scaleInt scale)


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


{-| The viewer's window, filling a window of the given size (UI pixels).
-}
view : UiScale -> Coord UiPixels -> List Ui.Screenshot -> Model -> Element UiId
view scale window screenshots model =
    let
        area =
            areaSize window

        header =
            Ui.leftAndRight
                (Units.ui (Coord.xRaw area + listWidth + gap))
                (Ui.row
                    gap
                    [ headerButton Types.ZoomOutButton "-"
                    , headerButton Types.ZoomInButton "+"
                    , headerButton Types.ActualSizeButton "100%"
                    , headerButton Types.FitButton "Fit"
                    , Ui.el
                        { pad = Ui.paddingXY 6 3, style = Ui.NoBorderOrFill }
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
    Ui.el
        { pad = Ui.paddingXY windowPadding windowPadding, style = Ui.windowBorderAndFill }
        (Ui.column
            gap
            [ header
            , Ui.row
                gap
                [ previewList scale (Coord.yRaw area) screenshots model, imageArea scale area screenshots model ]
            ]
        )


headerButton : Types.UiId -> String -> Element UiId
headerButton id label =
    Ui.button { id = ScreenshotViewer id, pad = Ui.paddingXY 6 3 } (text label)


text : String -> Element UiId
text =
    Ui.text


previewList : UiScale -> Int -> List Ui.Screenshot -> Model -> Element UiId
previewList scale height screenshots model =
    Ui.viewport
        { id = ScreenshotViewer Types.PreviewList
        , viewportHeight = Units.ui height
        }
        (Ui.column
            gap
            (if List.isEmpty screenshots then
                [ Ui.el
                    { pad = Ui.paddingXY buttonPadding buttonPadding, style = Ui.NoBorderOrFill }
                    (Ui.customTextWrapped Sprite.Small
                        (Units.ui (Coord.xRaw previewSize))
                        [ { text = "No screenshots yet. Press Print Screen, then click what to capture.", color = Color.textColor, font = Sprite.Sans Sprite.Regular, decorations = [], link = Nothing } ]
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
            pictureSize screenshot

        -- The preview's biggest size in pixels of this screen.
        ( maxW, maxH ) =
            Coord.toTuple previewSize |> Tuple.mapBoth (\x -> toFloat (x * Units.scaleInt scale)) (\y -> toFloat (y * Units.scaleInt scale))

        zoom =
            min (maxW / max 1 w) (maxH / max 1 h)

        size =
            Coord.xy (ceiling (w * zoom * uiPerScreenPixel scale)) (ceiling (h * zoom * uiPerScreenPixel scale))
    in
    Ui.selectableButton
        { id = ScreenshotViewer (Types.Preview index), pad = Ui.paddingXY buttonPadding buttonPadding }
        (model.selected == Just index)
        (Ui.quads
            { size = size
            , triangles = pictureTriangles scale zoom ( 0, 0 ) size screenshot
            }
        )


imageArea : UiScale -> Coord UiPixels -> List Ui.Screenshot -> Model -> Element UiId
imageArea scale area screenshots model =
    let
        background : List (Triangle UiPixels)
        background =
            Sprite.rectangle (Color.rgb255 60 60 60) { topLeft = Coord.origin, bottomRight = area } Coord.origin area
    in
    Ui.elWithId
        (ScreenshotViewer Types.ImageArea)
        { pad = Ui.noPadding, style = Ui.NoBorderOrFill }
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


{-| A screenshot drawn on a screen with the given UI scale, `zoom` of its pixels for each of
the picture's, with its top left corner at the given point of a box of the given size, and
cut off at the box.
-}
pictureTriangles : UiScale -> Float -> ( Float, Float ) -> Coord UiPixels -> Ui.Screenshot -> List (Triangle UiPixels)
pictureTriangles scale zoom offset box screenshot =
    let
        ( boxW, boxH ) =
            Coord.toTuple box |> Tuple.mapBoth toFloat toFloat
    in
    -- The picture is in pixels of the screen it was taken on, the box in UI pixels of this one.
    Ui.screenshotView screenshot
        |> Sprite.scaleAndMove (zoom * uiPerScreenPixel scale) offset
        |> Sprite.clipTo { left = 0, top = 0, right = boxW, bottom = boxH }
        |> Sprite.sampled
            (if zoom >= 2 then
                Nearest

             else
                Linear
            )
