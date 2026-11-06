module ReviewConfig exposing (config)

{-| Do not rename the ReviewConfig module or the config function, because
`elm-review` will look for these.

Adapted from at-chat's review config. The Lamdera, elm-ui and at-chat specific
rules (BackendOnly, NoInvalidTypesInToBackend, NoUnhandledFileHashes,
OpaqueTypes, RunUnsafeAtStartup, NoRedundantUiAttributes) were left out.

To add packages that contain rules, add them to this review project using

    `elm install author/packagename`

when inside the directory containing this file.

-}

import Docs.ReviewAtDocs
import EncoderDecoderNaming
import ExposeAllRecordFields
import NoConfusingPrefixOperator
import NoDebug.TodoOrToString
import NoExposingEverything
import NoImportingEverything
import NoInconsistentAliases
import NoMissingTypeAnnotation
import NoMissingTypeConstructor
import NoMissingTypeExpose
import NoModuleOnExposedNames
import NoSimpleLetBody
import NoStaleReferences
import NoUnused.CustomTypeConstructors
import NoUnused.Dependencies
import NoUnused.Exports
import NoUnused.Modules
import NoUnused.Parameters
import NoUnused.Patterns
import NoUnused.Variables
import Review.Rule exposing (Rule)
import ReviewPipelineStyles
import ReviewPipelineStyles.Fixes
import Simplify


config : List Rule
config =
    [ ExposeAllRecordFields.rule
    , NoStaleReferences.rule
    , NoUnused.CustomTypeConstructors.rule []
    , NoUnused.Patterns.rule
    , Docs.ReviewAtDocs.rule
    , NoConfusingPrefixOperator.rule
    , NoDebug.TodoOrToString.rule
    , NoExposingEverything.rule
    , NoImportingEverything.rule []
    , NoMissingTypeAnnotation.rule
    , NoMissingTypeExpose.rule
    , NoSimpleLetBody.rule
    , NoUnused.Dependencies.rule
    , NoUnused.Exports.rule
    , NoUnused.Modules.rule
    , NoUnused.Parameters.rule
    , ReviewPipelineStyles.rule
        [ ReviewPipelineStyles.forbid ReviewPipelineStyles.leftPizzaPipelines
            |> ReviewPipelineStyles.andTryToFixThemBy ReviewPipelineStyles.Fixes.convertingToParentheticalApplication
            |> ReviewPipelineStyles.andCallThem "forbidden <| pipeline"
        , ReviewPipelineStyles.forbid ReviewPipelineStyles.leftCompositionPipelines
            |> ReviewPipelineStyles.andCallThem "forbidden << composition"
        , ReviewPipelineStyles.forbid ReviewPipelineStyles.rightCompositionPipelines
            |> ReviewPipelineStyles.andCallThem "forbidden >> composition"
        ]
    , Simplify.rule Simplify.defaults
    , NoInconsistentAliases.config
        [ ( "Json.Decode", "D" )
        , ( "Json.Encode", "E" )
        ]
        |> NoInconsistentAliases.noMissingAliases
        |> NoInconsistentAliases.rule
    , NoModuleOnExposedNames.rule
    , NoMissingTypeConstructor.rule
    , NoUnused.Variables.rule
    , EncoderDecoderNaming.rule
    ]
