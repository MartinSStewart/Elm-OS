module Paint exposing
    ( Model
    , Stroke
    , appSize
    , endStroke
    , init
    , onClick
    , pixelAt
    , redo
    , startStroke
    , strokeBy
    , undo
    , undoOrRedo
    , view
    )

{-| A paint program: pick a colour, a brush and a tool, and draw on the canvas with the mouse.

The fill tool fills the pixels of the colour under the mouse that are joined to it, but only
those within `fillRadiusFactor` times the brush's radius from the mouse by walking distance. Dragging fills again from
wherever the mouse is, but only the colour that was under the mouse when it went down, and the
pixels the stroke has already filled count as that colour.

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

    -- The canvases before the latest changes (newest first), and the ones undone.
    , undoable : List Image
    , redoable : List Image

    -- While the mouse is down on the canvas.
    , stroke : Maybe Stroke
    }


type alias Stroke =
    { -- The canvas pixel the mouse was last at.
      at : ( Int, Int )

    -- The colour under the mouse when it went down (0xRRGGBBAA), which the fill tool replaces.
    , target : Int

    -- The pixels the fill tool has filled so far in this stroke, as y * canvasWidth + x. The
    -- fill treats them as still being the target colour.
    , filled : Set Int
    }


init : Model
init =
    { isOpen = False
    , canvas = blank
    , color = Color.black
    , brush = 3
    , tool = Paint.Types.Pen
    , undoable = []
    , redoable = []
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
startStroke point model0 =
    let
        model =
            remember model0

        at =
            Coord.toTuple point

        stroke =
            { at = at, filled = Set.empty, target = pixelAt at model.canvas |> Maybe.withDefault 0 }
    in
    case model.tool of
        Paint.Types.Pen ->
            paint [ at ] { model | stroke = Just stroke }

        Paint.Types.Fill ->
            fill [ at ] { model | stroke = Just stroke }


{-| How many changes can be undone. A canvas is about 1 MB in a snapshot, so it's not many.
-}
historySize : Int
historySize =
    10


{-| Keeps the canvas as it is, to go back to, and forgets what was undone.
-}
remember : Model -> Model
remember model =
    { model | undoable = List.take historySize (model.canvas :: model.undoable), redoable = [] }


undo : Model -> Model
undo model =
    case model.undoable of
        image :: older ->
            { model | canvas = image, undoable = older, redoable = model.canvas :: model.redoable, stroke = Nothing }

        [] ->
            model


redo : Model -> Model
redo model =
    case model.redoable of
        image :: newer ->
            { model | canvas = image, redoable = newer, undoable = model.canvas :: model.undoable, stroke = Nothing }

        [] ->
            model


{-| Ctrl+Z, or with shift Ctrl+Shift+Z.
-}
undoOrRedo : Bool -> Model -> Model
undoOrRedo shift model =
    if shift then
        redo model

    else
        undo model


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


{-| The chunks being filled, as pixels, which of them changed, the pixels filled in the stroke
so far, and how far each pixel the current dab has reached is from its centre.
-}
type alias Work =
    { chunks : Dict Int (Array.Array Int)
    , changed : Set Int
    , filled : Set Int
    , distances : Dict Int Int
    }


{-| Fill around each point, in the brush's colour: the pixels of the stroke's target colour
that are within the fill radius of the point by walking (over pixels that are the target
colour, a step to any of the 8 pixels around one, diagonals costing the square root of 2).
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
                    { chunks = Dict.empty, changed = Set.empty, filled = stroke.filled, distances = Dict.empty }
            in
            if color == stroke.target then
                -- Nothing to do, and the fill would never stop: it would find its own pixels.
                model

            else
                let
                    work =
                        List.foldl (fillAround canvas (fillRadius model) color stroke.target) start points
                in
                { model
                    | stroke = Just { stroke | filled = work.filled }
                    , canvas =
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
fillAround canvas r color target ( cx, cy ) previous =
    let
        chunksReached =
            List.concatMap
                (\chunkY -> List.map (\chunkX -> chunkY * chunksAcross + chunkX) (List.range (max 0 (cx - r) // chunkSize) (min (canvasWidth - 1) (cx + r) // chunkSize)))
                (List.range (max 0 (cy - r) // chunkSize) (min (canvasHeight - 1) (cy + r) // chunkSize))

        start =
            List.foldl
                (\index w -> { w | chunks = Dict.update index (loadChunk canvas index) w.chunks })
                { previous | distances = Dict.empty }
                chunksReached

        -- The pixels the fill walks over: ones of the target colour, and ones filled already in
        -- this stroke.
        isWalkable w ( x, y ) =
            Set.member (y * canvasWidth + x) w.filled
                || (Dict.get (chunkIndexOf x y) w.chunks
                        |> Maybe.andThen (Array.get (inChunk x y))
                        |> (==) (Just target)
                   )

        -- Distances are in thousandths of a pixel.
        limit =
            r * straightCost

        -- Walks out from the mouse, a pixel at a time (the 8 pixels around it), to every
        -- walkable pixel that is within the limit, by the shortest walk. A pixel's distance
        -- can fall when a shorter way to it is found, and then it is walked on from again.
        spread : Queue -> Work -> Work
        spread queue w =
            case queue of
                Queue [] [] ->
                    w

                Queue [] back ->
                    spread (Queue (List.reverse back) []) w

                Queue (( x, y, distance ) :: front) back ->
                    if distance > (Dict.get (y * canvasWidth + x) w.distances |> Maybe.withDefault distance) then
                        spread (Queue front back) w

                    else
                        let
                            ( queue2, w2 ) =
                                List.foldl (step x y distance) ( Queue front back, w ) neighbours
                        in
                        spread queue2 w2

        step x y distance ( dx, dy, cost ) ( queue, w ) =
            let
                nx =
                    x + dx

                ny =
                    y + dy

                key =
                    ny * canvasWidth + nx

                nextDistance =
                    distance + cost

                -- Whether it was reached already, as quickly.
                alreadyReached =
                    nextDistance >= (Dict.get key w.distances |> Maybe.withDefault (nextDistance + 1))
            in
            if nx < 0 || ny < 0 || nx >= canvasWidth || ny >= canvasHeight || nextDistance > limit || alreadyReached || not (isWalkable w ( nx, ny )) then
                ( queue, w )

            else
                ( push ( nx, ny, nextDistance ) queue
                , setDistance nextDistance key (setPixel color ( nx, ny ) w)
                )
    in
    if isWalkable start ( cx, cy ) then
        spread (Queue [ ( cx, cy, 0 ) ] []) (setDistance 0 (cy * canvasWidth + cx) (setPixel color ( cx, cy ) start))

    else
        start


{-| A first in, first out queue: what to take next, and what was added since (newest first).
-}
type Queue
    = Queue (List ( Int, Int, Int )) (List ( Int, Int, Int ))


push : ( Int, Int, Int ) -> Queue -> Queue
push item (Queue front back) =
    Queue front (item :: back)


{-| What it costs to step to each of the 8 pixels around one, in thousandths of a pixel
(a diagonal step is the square root of 2 times as far).
-}
neighbours : List ( Int, Int, Int )
neighbours =
    [ ( -1, 0, straightCost )
    , ( 1, 0, straightCost )
    , ( 0, -1, straightCost )
    , ( 0, 1, straightCost )
    , ( -1, -1, diagonalCost )
    , ( 1, -1, diagonalCost )
    , ( -1, 1, diagonalCost )
    , ( 1, 1, diagonalCost )
    ]


straightCost : Int
straightCost =
    1000


diagonalCost : Int
diagonalCost =
    1414


setDistance : Int -> Int -> Work -> Work
setDistance distance key work =
    { work | distances = Dict.insert key distance work.distances }


loadChunk : Image -> Int -> Maybe (Array.Array Int) -> Maybe (Array.Array Int)
loadChunk canvas index loaded =
    case loaded of
        Just _ ->
            loaded

        Nothing ->
            Array.get index canvas.chunks |> Maybe.map Image.chunkPixels


{-| Paints the pixel and notes it as filled, unless it was filled already.
-}
setPixel : Int -> ( Int, Int ) -> Work -> Work
setPixel color ( x, y ) work =
    let
        index =
            chunkIndexOf x y

        key =
            y * canvasWidth + x
    in
    if Set.member key work.filled then
        work

    else
        { work
            | chunks = Dict.update index (Maybe.map (Array.set (inChunk x y) color)) work.chunks
            , changed = Set.insert index work.changed
            , filled = Set.insert key work.filled
        }



-- CLICKS


onClick : Paint.Types.UiId -> Model -> Model
onClick id model =
    case id of
        Paint.Types.OpenButton ->
            { model | isOpen = not model.isOpen, stroke = Nothing }

        Paint.Types.CloseButton ->
            { model | isOpen = False, stroke = Nothing }

        Paint.Types.UndoButton ->
            undo model

        Paint.Types.RedoButton ->
            redo model

        Paint.Types.ClearButton ->
            let
                remembered =
                    remember model
            in
            { remembered | canvas = blank }

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
                    [ Ui.button { id = Paint Paint.Types.UndoButton, pad = Ui.paddingXY 8 0 } (Ui.text "Undo")
                    , Ui.button { id = Paint Paint.Types.RedoButton, pad = Ui.paddingXY 8 0 } (Ui.text "Redo")
                    , Ui.button { id = Paint Paint.Types.ClearButton, pad = Ui.paddingXY 8 0 } (Ui.text "Clear")
                    , Ui.button { id = Paint Paint.Types.CloseButton, pad = Ui.paddingXY 6 0 } (Ui.text "×")
                    ]
                )

        tools =
            Ui.leftAndRight width
                (Ui.row 4 (List.indexedMap (colorButton model) Color.paintPalette))
                (Ui.row 4 (List.map (toolButton model) [ ( Paint.Types.Pen, "Pen" ), ( Paint.Types.Fill, "Fill" ) ] ++ List.map (brushButton model) brushes))

        canvas =
            Ui.elWithId (Paint Paint.Types.Canvas)
                { pad = Ui.noPadding, style = Ui.NoBorderOrFill }
                (Ui.quads
                    { size = Coord.xy canvasWidth canvasHeight
                    , triangles = Sprite.image model.canvas
                    }
                )
    in
    Ui.el
        { pad = Ui.paddingXY 8 8, style = Ui.windowBorderAndFill }
        (Ui.column 6 [ title, tools, canvas ])


toolButton : Model -> ( Paint.Types.Tool, String ) -> Element UiId
toolButton model ( tool, name ) =
    Ui.selectableButton { id = Paint (Paint.Types.ToolButton tool), pad = Ui.paddingXY 6 3 }
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
    Ui.selectableButton { id = Paint (Paint.Types.ColorButton index), pad = Ui.paddingXY 3 3 }
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
    Ui.selectableButton { id = Paint (Paint.Types.BrushButton radius), pad = Ui.paddingXY 3 3 }
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
