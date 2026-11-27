"""Make the pruned eco sources build without eco's kernel modules and extra packages."""
import re, sys, os
out = sys.argv[1]
def sub(rel, old, new, count=1):
    p = os.path.join(out, rel); s = open(p).read()
    if old not in s: sys.exit(f"localize: {rel}: not found: {old[:60]!r}")
    open(p, 'w').write(s.replace(old, new, count))
def write(rel, text):
    p = os.path.join(out, rel); os.makedirs(os.path.dirname(p), exist_ok=True); open(p, 'w').write(text)

write('System/Crash.elm', '''module System.Crash exposing (crash)

{-| Stands in for eco's `System.Crash` in Elm OS's copy of eco's parser and formatter.
Reaching it is a bug in that copy.
-}


crash : String -> a
crash str =
    Debug.todo str
''')
for rel in ['Prelude.elm', 'Common/Format/Cheapskate/Parse.elm']:
    sub(rel, 'import List.Extra as List', 'import Extra.List as List')
for rel in ['Common/Format/Render/Box.elm', 'Common/Format/Render/Markdown.elm']:
    sub(rel, 'import Maybe.Extra as Maybe', 'import Extra.Maybe as Maybe')
for rel in ['Common/Format/Render/Box.elm', 'Common/Format/Box.elm']:
    sub(rel, 'import Basics.Extra exposing (flip)', 'import Extra.Basics exposing (flip)')
sub('Common/Format/Box.elm', 'import Result.Extra as Result', 'import Extra.Result as Result')
sub('Compiler/IR/Source/StringLiteral.elm', 'import Numeric.Integer as NI\n', '')
sub('Compiler/IR/Source/StringLiteral.elm', 'NI.divMod (code - 0x00010000) 0x0400', '( (code - 0x00010000) // 0x0400, modBy 0x0400 (code - 0x00010000) )')
# GLSL: the formatter only needs the text of a [glsl| ... |] literal, not its inputs
p = os.path.join(out, 'Compiler/Parse/Shader.elm'); s = open(p).read()
s = s.replace('import Language.GLSL.Parser as GLP\n', '').replace('import Language.GLSL.Syntax as GLS\n', '')
a = s.index('parseGlsl : Row -> Col -> String -> Parser E.Expr Shader.Types')
b = s.find('\n\n\n', a)
nxt = re.search(r'\n\n\n(?=[a-z{])', s[a:])
# drop parseGlsl's body and every later GLS helper, keep emptyTypes
s = s[:a] + '''parseGlsl : Row -> Col -> String -> Parser E.Expr Shader.Types
parseGlsl _ _ _ =
    P.pure emptyTypes
''' + re.sub(r'(?s)\n\n\n(\{-\|(?:(?!-\}).)*-\}\n)?(extractInputs|inputKind|addInput) :.*?(?=\n\n\n|\Z)', '', s[s.find('\n\n\n', a):])
open(p, 'w').write(s)
p = os.path.join(out, 'Compiler/IR/Source/Shader.elm'); s = open(p).read()
s = s.replace('import Regex\n', '')
a = s.index('unescape : String -> String'); b = s.find('\n\n\n', a)
s = s[:a] + '''unescape : String -> String
unescape str =
    unescapeHelp (String.toList str) []


unescapeHelp : List Char -> List Char -> String
unescapeHelp chars acc =
    case chars of
        '\\\\' :: c :: rest ->
            case c of
                'n' ->
                    unescapeHelp rest ('\\n' :: acc)

                '"' ->
                    unescapeHelp rest ('"' :: acc)

                '\\'' ->
                    unescapeHelp rest ('\\'' :: acc)

                '\\\\' ->
                    unescapeHelp rest ('\\\\' :: acc)

                _ ->
                    unescapeHelp (c :: rest) ('\\\\' :: acc)

        c :: rest ->
            unescapeHelp rest (c :: acc)

        [] ->
            String.fromList (List.reverse acc)''' + (s[b:] if b != -1 else '\n')
open(p, 'w').write(s)

write('Extra/Basics.elm', '''module Extra.Basics exposing (flip)


flip : (a -> b -> c) -> b -> a -> c
flip f b a =
    f a b
''')
write('Extra/Result.elm', '''module Extra.Result exposing (combine)


combine : List (Result x a) -> Result x (List a)
combine =
    List.foldr (Result.map2 (::)) (Ok [])
''')
write('Extra/Maybe.elm', '''module Extra.Maybe exposing (isJust, join, oneOf, toList, unwrap)


isJust : Maybe a -> Bool
isJust m =
    case m of
        Just _ ->
            True

        Nothing ->
            False


join : Maybe (Maybe a) -> Maybe a
join m =
    case m of
        Just inner ->
            inner

        Nothing ->
            Nothing


oneOf : List (a -> Maybe b) -> a -> Maybe b
oneOf fmbx a =
    case fmbx of
        [] ->
            Nothing

        f :: fs ->
            case f a of
                Just b ->
                    Just b

                Nothing ->
                    oneOf fs a


toList : Maybe a -> List a
toList m =
    case m of
        Just a ->
            [ a ]

        Nothing ->
            []


unwrap : b -> (a -> b) -> Maybe a -> b
unwrap default f m =
    case m of
        Just a ->
            f a

        Nothing ->
            default
''')
write('Extra/List.elm', '''module Extra.List exposing (dropWhile, init, last, span, splitWhen)


dropWhile : (a -> Bool) -> List a -> List a
dropWhile predicate list =
    case list of
        [] ->
            []

        x :: xs ->
            if predicate x then
                dropWhile predicate xs

            else
                list


init : List a -> Maybe (List a)
init items =
    case List.reverse items of
        [] ->
            Nothing

        _ :: rest ->
            Just (List.reverse rest)


last : List a -> Maybe a
last items =
    List.head (List.reverse items)


span : (a -> Bool) -> List a -> ( List a, List a )
span p xs =
    ( takeWhile p xs, dropWhile p xs )


takeWhile : (a -> Bool) -> List a -> List a
takeWhile predicate =
    let
        help acc list =
            case list of
                [] ->
                    List.reverse acc

                x :: xs ->
                    if predicate x then
                        help (x :: acc) xs

                    else
                        List.reverse acc
    in
    help []


splitWhen : (a -> Bool) -> List a -> Maybe ( List a, List a )
splitWhen predicate list =
    findIndex predicate 0 list
        |> Maybe.map (\\i -> ( List.take i list, List.drop i list ))


findIndex : (a -> Bool) -> Int -> List a -> Maybe Int
findIndex predicate i list =
    case list of
        [] ->
            Nothing

        x :: xs ->
            if predicate x then
                Just i

            else
                findIndex predicate (i + 1) xs
''')
