module Paint exposing
    ( Model
    , endStroke
    , init
    , onClick
    , startStroke
    , strokeBy
    , view
    )

{-| A paint program: pick a colour and a brush, and draw on the canvas with the mouse.

The canvas is a 640 x 384 pixel Image (one pixel per UI pixel): 32 x 32 pixel chunks.
A stroke rebuilds the chunks it touches; Sprite.image draws it.

-}

import Array
import Color exposing (Color)
import Coord exposing (Coord)
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

    -- The canvas pixel the mouse was last at, while it draws.
    , stroke : Maybe ( Int, Int )
    }


init : Model
init =
    { isOpen = False
    , canvas = blank
    , color = Color.black
    , brush = 3
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
    in
    paint [ at ] { model | stroke = Just at }


{-| The mouse moved by this much while drawing: paints along the way.
-}
strokeBy : Coord UiPixels -> Model -> Model
strokeBy ( dx, dy ) model =
    case model.stroke of
        Just ( x, y ) ->
            let
                to =
                    ( x + Units.inUiPixels dx, y + Units.inUiPixels dy )
            in
            if to == ( x, y ) then
                model

            else
                paint (line ( x, y ) to model.brush) { model | stroke = Just to }

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



-- VIEW


view : Model -> Element UiId
view model =
    let
        width =
            Units.uiPixels canvasWidth

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
                (Ui.row 4 (List.map (brushButton model) brushes))

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
