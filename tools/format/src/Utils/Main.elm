module Utils.Main exposing (unlines)

{-| Stands in for the parts of Haskell's libraries that the compiler was ported
from, so that code written in their shape runs on the `Eco.*` modules that do
this program's IO.

Most names here are a Haskell name with a prefix saying where it comes from:
`fp` for file paths, `dir` for directories, `env` for the environment, `repl`
for line input, `http` for HTTP errors, and `dict`, `map`, `list` and so on for
helpers over those structures. Such a name says which Haskell function a value
stands in for, not that it behaves the same way. Where one differs from what
its name suggests, its docstring says so.

File paths are plain strings, and the `fp` functions work on their text alone:
they never ask the file system anything. They take `/` as the only separator.
`fpIsRelative`, which `fpCombine` uses, is the one place that also recognises
the Windows forms of an absolute path.

The `dir` and `env` functions, `lockWithFileLock` and the binary file functions
are tasks over `Eco.File` and `Eco.Env`, and none of them can fail. Where the
operation underneath can fail with an `IOError`, the failure crashes the program through
`System.IO.crashOnError`. `binaryDecodeFileOrFail` is the exception: there, a
failure to read the file becomes an `Err`.

An _MVar_ is a cell, held outside the program, that is either empty or holds
one value, as `Eco.MVar` describes. The MVar functions here take an encoder or
a decoder for what the MVar holds because `Eco.MVar`'s operations do. A
_channel_ (`Chan`) is an unbounded first-in, first-out queue built from MVars,
through which concurrent tasks hand values to one another.

The rest are pure helpers over `Dict`, `Data.Map`, `List`, `Maybe`, `Result`,
non-empty lists and `Compiler.Reporting.Result`, most of them traversals. Those
that take a function giving a `Task` perform the tasks one after another, in
the order each docstring gives. `find`, `dictFind`, `mapFindMin`, `foldl1_`
and `foldr1` crash the program, through `System.Crash.crash`, on a missing key
or an empty input.

The types `FilePath`, `MVar`, `ChItem`, `Stream` and `LockSharedExclusive` used
here are defined in `System.IO`.


# File Path Operations

@docs fpCombine, fpAddExtension, fpDropExtension, fpDropFileName, fpSplitExtension
@docs fpSplitFileName, fpSplitDirectories, fpJoinPath, fpMakeRelative, fpAddTrailingPathSeparator
@docs fpPathSeparator, fpIsRelative, fpTakeFileName, fpTakeExtension, fpTakeDirectory


# Directory Operations

@docs dirDoesFileExist, dirDoesDirectoryExist, dirCreateDirectoryIfMissing
@docs dirGetCurrentDirectory, dirGetAppUserDataDirectory, dirGetModificationTime, dirListDirectory
@docs dirRemoveFile, dirRemoveDirectoryRecursive, dirGetFileSize, dirCanonicalizePath


# Environment Operations

@docs envLookupEnv, envGetProgName, envGetArgs


# File Locking

@docs lockWithFileLock


# Binary Serialization

@docs binaryDecodeFileOrFail, binaryEncodeFile, builderHPutBuilder


# Concurrency Primitives

@docs ThreadId, forkIO


# MVar Operations

@docs newMVar, newEmptyMVar, readMVar, takeMVar, putMVar, dropMVar
@docs mVarEncoder, mVarDecoder


# Channel Operations

@docs Chan, newChan, readChan, writeChan


# Node.js Integration

@docs nodeGetDirname


# Dictionary Utilities

@docs mapFindMin
@docs dictMapKeys, find, dictFind


# Dictionary Traversal

@docs mapTraverse


# List Utilities

@docs eitherLefts, filterM, listGroupBy, listLookup, listMaximum, foldl1_, foldr1
@docs listTraverse, listTraverse_, unlines, zipWithM, mapM_


# Maybe Utilities

@docs maybeEncoder, maybeMapM


# NonEmptyList Traversal

@docs nonEmptyListTraverse


# Sequence Operations

@docs sequenceListMaybe, sequenceNonemptyListResult


# Stdlib Dict Utilities

@docs dictFromListWith, dictInsertWith, dictIntersectionWith, dictIntersectionWithKey, dictMapMaybe, dictSequenceResult, dictSequenceMaybe, dictTraverse, dictTraverseWithKey, dictTraverseResult, dictTraverseWithKeyResult, dictUnionWith, dictMapM__, dictFromKeysA

-}


{-| Joins the strings with newlines, and ends the result with one more newline.
-}
unlines : List String -> String
unlines xs =
    String.join "\n" xs ++ "\n"
