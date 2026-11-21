#!/bin/sh
# Prints elm/src/BuildInfo.elm as it is in a build: the commit elm/src is at, and the
# branch checked out, for the Code app's commits. The commit is "" when elm/src has
# changes that aren't committed: then no commit has the code the build was made from.
#
#   usage: tools/build-info.sh > OUT.elm
set -eu
commit=$(git rev-parse HEAD 2>/dev/null || true)
if [ -n "$commit" ] && [ -n "$(git status --porcelain -- elm/src 2>/dev/null)" ]; then
    commit=
fi
branch=$(git symbolic-ref --short -q HEAD 2>/dev/null || true)
# CI checks a branch out by its commit; GitHub says which branch it was.
[ -n "$branch" ] || branch=${GITHUB_REF_NAME:-}
case $branch in *[!A-Za-z0-9._/-]*) branch= ;; esac
cat <<ELM
module BuildInfo exposing (branch, commit)

{-| Written by tools/build-info.sh. -}


commit : String
commit =
    "$commit"


branch : String
branch =
    "$branch"
ELM
