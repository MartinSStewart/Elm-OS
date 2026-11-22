module Paint exposing
    ( Model
    , Stroke
    , appSize
    , endStroke
    , init
    , onClick
    , pixelAt
    , startStroke
    , strokeBy
    , view
    )

{-| A paint program: pick a colour, a brush and a tool, and draw on the canvas with the mouse.

The fill tool fills the pixels of the colour under the mouse that are joined to it, but only
up to `fillRadiusFactor` times the brush's radius from the mouse. Dragging fills again from
wherever the mouse is, but only the colour that was under the mouse when it went down.

The canvas is a 640 x 384 pixel Image (one pixel per UI pixel): 32 x 32 pixel chunks.
A stroke rebuilds the chunks it touches; Sprite.image draws it.

-}

import App
import Array
import Color exposing (Color)
import Coord exposing (Coord)
import Dict exposing (Dict)
import Image exposing (Image)
import Paint.Types
import Set exposing (Set)
import Sprite
import Ui exposing (Element)
import UiId exposing (UiId(..))
import Units exposing (UiPixels)


type alias Model =
    { isOpen : Bool
    , canvas : Image
    , color : Color
    , brush : Int -- the brush's radius, in canvas pixels
    , tool : Paint.Types.Tool

    -- While the mouse is down on the canvas.
    , stroke : Maybe Stroke
    }


type alias Stroke =
    { -- The canvas pixel the mouse was last at.
      at : ( Int, Int )

    -- The colour under the mouse when it went down (0xRRGGBBAA), which the fill tool replaces.
    , target : Int
    }


init : Model
init =
    { isOpen = False
    , canvas = blank
    , color = Color.black
    , brush = 3
    , tool = Paint.Types.Pen
    , stroke = Nothing
    }


chunkSize : Int
chunkSize =
    Image.chunkSize


chunksAcross : Int
chunksAcross =
    20


chunksDown : Int
chunksDown =
    12


canvasWidth : Int
canvasWidth =
    chunkSize * chunksAcross


canvasHeight : Int
canvasHeight =
    chunkSize * chunksDown


{-| The radii of the brushes to pick from.
-}
brushes : List Int
brushes =
    [ 1, 3, 6, 12 ]


blank : Image
blank =
    Image.filled chunksAcross chunksDown (Color.toInt Color.white)



-- DRAWING


{-| The mouse went down on the canvas, at this pixel of it.
-}
startStroke : Coord UiPixels -> Model -> Model
startStroke point model =
    let
        at =
            Coord.toTuple point

        stroke =
            { at = at, target = pixelAt at model.canvas |> Maybe.withDefault 0 }
    in
    case model.tool of
        Paint.Types.Pen ->
            paint [ at ] { model | stroke = Just stroke }

        Paint.Types.Fill ->
            fill [ at ] { model | stroke = Just stroke }


{-| The mouse moved by this much while drawing: paints along the way.
-}
strokeBy : Coord UiPixels -> Model -> Model
strokeBy ( dx, dy ) model =
    case model.stroke of
        Just stroke ->
            let
                ( x, y ) =
                    stroke.at

                to =
                    ( x + Units.inUi dx, y + Units.inUi dy )

                moved =
                    { model | stroke = Just { stroke | at = to } }
            in
            if to == ( x, y ) then
                model

            else
                case model.tool of
                    Paint.Types.Pen ->
                        paint (line ( x, y ) to model.brush) moved

                    Paint.Types.Fill ->
                        fill (line ( x, y ) to (fillRadius model)) moved

        Nothing ->
            model


endStroke : Model -> Model
endStroke model =
    { model | stroke = Nothing }


{-| The points from one to the other (leaving out the first), close enough together
that the brush's dabs make a smooth line.
-}
line : ( Int, Int ) -> ( Int, Int ) -> Int -> List ( Int, Int )
line ( fromX, fromY ) ( toX, toY ) radius =
    let
        distance =
            max (abs (toX - fromX)) (abs (toY - fromY))

        steps =
            max 1 (ceiling (toFloat distance / toFloat (max 1 (radius // 2))))

        along i a b =
            a + round (toFloat (i * (b - a)) / toFloat steps)
    in
    List.map (\i -> ( along i fromX toX, along i fromY toY )) (List.range 1 steps)


{-| A dab of the brush at each point, in the brush's colour. Each chunk they touch is
rebuilt once.
-}
paint : List ( Int, Int ) -> Model -> Model
paint dabs model =
    let
        r =
            model.brush

        onCanvas =
            List.filter
                (\( x, y ) -> x + r >= 0 && y + r >= 0 && x - r < canvasWidth && y - r < canvasHeight)
                dabs

        touched : Set Int
        touched =
            List.foldl
                (\( x, y ) set ->
                    List.foldl
                        (\cy set2 ->
                            List.foldl (\cx -> Set.insert (cy * chunksAcross + cx))
                                set2
                                (List.range (max 0 (x - r) // chunkSize) (min (canvasWidth - 1) (x + r) // chunkSize))
                        )
                        set
                        (List.range (max 0 (y - r) // chunkSize) (min (canvasHeight - 1) (y + r) // chunkSize))
                )
                Set.empty
                onCanvas

        color =
            Color.toInt model.color

        canvas =
            model.canvas
    in
    { model
        | canvas =
            { canvas
                | chunks =
                    Set.foldl
                        (\index chunks ->
                            case Array.get index chunks of
                                Just chunk ->
                                    Array.set index (paintChunk index r color onCanvas chunk) chunks

                                Nothing ->
                                    chunks
                        )
                        canvas.chunks
                        touched
            }
    }


{-| The chunk with the dabs that reach it painted on.
-}
paintChunk : Int -> Int -> Int -> List ( Int, Int ) -> Image.Chunk -> Image.Chunk
paintChunk index r color dabs chunk =
    let
        left =
            modBy chunksAcross index * chunkSize

        top =
            index // chunksAcross * chunkSize

        dab ( x, y ) pixels =
            List.foldl
                (\py pixels2 ->
                    List.foldl
                        (\px pixels3 ->
                            if (px - x) * (px - x) + (py - y) * (py - y) <= r * r + r then
                                Array.set ((py - top) * chunkSize + (px - left)) color pixels3

                            else
                                pixels3
                        )
                        pixels2
                        (List.range (max left (x - r)) (min (left + chunkSize - 1) (x + r)))
                )
                pixels
                (List.range (max top (y - r)) (min (top + chunkSize - 1) (y + r)))
    in
    List.foldl dab (Image.chunkPixels chunk) dabs |> Image.chunkFromPixels


{-| The colour of a canvas pixel (0xRRGGBBAA).
-}
pixelAt : ( Int, Int ) -> Image -> Maybe Int
pixelAt ( x, y ) canvas =
    if x < 0 || y < 0 || x >= canvasWidth || y >= canvasHeight then
        Nothing

    else
        Array.get (chunkIndexOf x y) canvas.chunks
            |> Maybe.andThen (\chunk -> Array.get (inChunk x y) (Image.chunkPixels chunk))


chunkIndexOf : Int -> Int -> Int
chunkIndexOf x y =
    y // chunkSize * chunksAcross + x // chunkSize


inChunk : Int -> Int -> Int
inChunk x y =
    modBy chunkSize y * chunkSize + modBy chunkSize x


{-| How many times the brush's radius the fill tool's radius is.
-}
fillRadiusFactor : Int
fillRadiusFactor =
    5


fillRadius : Model -> Int
fillRadius model =
    model.brush * fillRadiusFactor


{-| The chunks being filled, as pixels, and which of them changed.
-}
type alias Work =
    { chunks : Dict Int (Array.Array Int)
    , changed : Set Int
    }


{-| Fill around each point, in the brush's colour: the pixels of the stroke's target colour
that are inside the fill radius and joined to the point.
-}
fill : List ( Int, Int ) -> Model -> Model
fill points model =
    case model.stroke of
        Just stroke ->
            let
                color =
                    Color.toInt model.color

                canvas =
                    model.canvas

                start : Work
                start =
                    { chunks = Dict.empty, changed = Set.empty }

                work =
                    List.foldl (fillAround canvas (fillRadius model) color stroke.target) start points
            in
            if color == stroke.target then
                model

            else
                { model
                    | canvas =
                        { canvas
                            | chunks =
                                Set.foldl
                                    (\index chunks ->
                                        case Dict.get index work.chunks of
                                            Just pixels ->
                                                Array.set index (Image.chunkFromPixels pixels) chunks

                                            Nothing ->
                                                chunks
                                    )
                                    canvas.chunks
                                    work.changed
                        }
                }

        Nothing ->
            model


fillAround : Image -> Int -> Int -> Int -> ( Int, Int ) -> Work -> Work
fillAround canvas r color target ( cx, cy ) work0 =
    let
        inCircle ( x, y ) =
            (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r + r

        reached =
            List.concatMap
                (\chunkY -> List.map (\chunkX -> chunkY * chunksAcross + chunkX) (List.range (max 0 (cx - r) // chunkSize) (min (canvasWidth - 1) (cx + r) // chunkSize)))
                (List.range (max 0 (cy - r) // chunkSize) (min (canvasHeight - 1) (cy + r) // chunkSize))

        work =
            List.foldl
                (\index w -> { w | chunks = Dict.update index (loadChunk canvas index) w.chunks })
                work0
                reached

        isTarget w ( x, y ) =
            Dict.get (chunkIndexOf x y) w.chunks
                |> Maybe.andThen (Array.get (inChunk x y))
                |> (==) (Just target)

        seeds =
            [ ( cx, cy ) ]

        spread : List ( Int, Int ) -> Work -> Work
        spread stack w =
            case stack of
                [] ->
                    w

                ( x, y ) :: rest ->
                    if x < 0 || y < 0 || x >= canvasWidth || y >= canvasHeight || not (inCircle ( x, y )) || not (isTarget w ( x, y )) then
                        spread rest w

                    else
                        spread
                            (( x - 1, y ) :: ( x + 1, y ) :: ( x, y - 1 ) :: ( x, y + 1 ) :: rest)
                            (setPixel color ( x, y ) w)
    in
    spread seeds work


loadChunk : Image -> Int -> Maybe (Array.Array Int) -> Maybe (Array.Array Int)
loadChunk canvas index loaded =
    case loaded of
        Just _ ->
            loaded

        Nothing ->
            Array.get index canvas.chunks |> Maybe.map Image.chunkPixels


setPixel : Int -> ( Int, Int ) -> Work -> Work
setPixel color ( x, y ) work =
    let
        index =
            chunkIndexOf x y
    in
    { chunks = Dict.update index (Maybe.map (Array.set (inChunk x y) color)) work.chunks
    , changed = Set.insert index work.changed
    }



-- CLICKS


onClick : Paint.Types.UiId -> Model -> Model
onClick id model =
    case id of
        Paint.Types.OpenButton ->
            { model | isOpen = not model.isOpen, stroke = Nothing }

        Paint.Types.CloseButton ->
            { model | isOpen = False, stroke = Nothing }

        Paint.Types.ClearButton ->
            { model | canvas = blank }

        Paint.Types.Canvas ->
            model

        Paint.Types.ColorButton index ->
            case List.drop index Color.paintPalette of
                color :: _ ->
                    { model | color = color }

                [] ->
                    model

        Paint.Types.BrushButton radius ->
            { model | brush = radius }

        Paint.Types.ToolButton tool ->
            { model | tool = tool }



-- VIEW


view : Model -> Element UiId
view model =
    let
        width =
            Units.ui canvasWidth

        title =
            Ui.leftAndRight width
                (Ui.text "Paint")
                (Ui.row 4
                    [ Ui.button { id = Paint Paint.Types.ClearButton, padding = Ui.paddingXY 8 0 } (Ui.text "Clear")
                    , Ui.button { id = Paint Paint.Types.CloseButton, padding = Ui.paddingXY 6 0 } (Ui.text "×")
                    ]
                )

        tools =
            Ui.leftAndRight width
                (Ui.row 4 (List.indexedMap (colorButton model) Color.paintPalette))
                (Ui.row 4 (List.map (toolButton model) [ ( Paint.Types.Pen, "Pen" ), ( Paint.Types.Fill, "Fill" ) ] ++ List.map (brushButton model) brushes))

        canvas =
            Ui.elWithId (Paint Paint.Types.Canvas)
                { padding = Ui.noPadding, borderAndFill = Ui.NoBorderOrFill }
                (Ui.quads
                    { size = Coord.xy canvasWidth canvasHeight
                    , triangles = Sprite.image model.canvas
                    }
                )
    in
    Ui.el
        { padding = Ui.paddingXY 8 8, borderAndFill = Ui.windowBorderAndFill }
        (Ui.column 6 [ title, tools, canvas ])


toolButton : Model -> ( Paint.Types.Tool, String ) -> Element UiId
toolButton model ( tool, name ) =
    Ui.selectableButton { id = Paint (Paint.Types.ToolButton tool), padding = Ui.paddingXY 6 3 }
        (tool == model.tool)
        (Ui.text name)


swatchSize : Int
swatchSize =
    20


colorButton : Model -> Int -> Color -> Element UiId
colorButton model index color =
    let
        s =
            toFloat swatchSize
    in
    Ui.selectableButton { id = Paint (Paint.Types.ColorButton index), padding = Ui.paddingXY 3 3 }
        (color == model.color)
        (Ui.quads
            { size = Coord.xy swatchSize swatchSize
            , triangles =
                [ Sprite.triangle color ( 0, 0 ) ( s, 0 ) ( s, s )
                , Sprite.triangle color ( 0, 0 ) ( s, s ) ( 0, s )
                ]
            }
        )


{-| A brush, shown as a dot its size (up to what fits).
-}
brushButton : Model -> Int -> Element UiId
brushButton model radius =
    let
        s =
            toFloat swatchSize
    in
    Ui.selectableButton { id = Paint (Paint.Types.BrushButton radius), padding = Ui.paddingXY 3 3 }
        (radius == model.brush)
        (Ui.quads
            { size = Coord.xy swatchSize swatchSize
            , triangles = Sprite.circle Color.textColor 1 ( s / 2, s / 2 ) (min (s / 2) (toFloat radius + 0.5))
            }
        )


{-| The window's size, worked out once.
-}
appSize : App.Limits
appSize =
    App.fixed (Ui.size (view init))
