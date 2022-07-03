#!/bin/bash

set -e

if (( $# < 3 )) ; then
  echo "$0 major minor revision" >&2
  exit 1
fi

oldfile=(*.rockspec)
oldfile=${oldfile[0]}

[[ $oldfile =~ (.*)'-'([0-9]+)'.'([0-9]+)'-'([0-9]+)'.rockspec'$ ]]

basename="${BASH_REMATCH[1]}"
oldmajor="${BASH_REMATCH[2]}"
oldminor="${BASH_REMATCH[3]}"
oldpatch="${BASH_REMATCH[4]}"

updated=("$oldfile" README.md cpp-compiler-pretty-output.lua)
newfile="$basename-$1.$2-$3.rockspec"

sed -i "s/$oldmajor\.$oldminor\([.-]\)$oldpatch/$1.$2\1$3/" "${updated[@]}"
mv "$oldfile" "$newfile"

git add "${updated[@]}" "$newfile"
git commit -vm "update version to $1.$2.$3"
git tag "v$1.$2.$3"
git push --tags
git push
