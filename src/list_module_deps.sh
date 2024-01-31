#!/usr/bin/env bash

# Make Linux sort order match mac OS X
export LC_ALL=C
# Get all occurrences of use mod_... in .t files
# - The '.' is for Mac compatibility
# - The 'sort' is to ensure the order is identical on different systems
#deps="$(grep -r -e "^\s*use mod_" --include \*.t . | sort)"
deps="$(grep -r -e "^\s*use " --include \*.t . | sort)"

# Remove old_physics entries
deps=$(echo "$deps" | sed 's/^.*old_physics[/].*$//')

# Remove compiler provided modules entry
deps=$(echo "$deps" | sed 's/^.* iso_fortran_env.*$//')
deps=$(echo "$deps" | sed 's/^.* mpi$//')

# Remove amrvac.o entry (it is compiled later)
deps=$(echo "$deps" | sed 's/^amrvac[.]t.*$//')

# Remove comments
deps=$(echo "$deps" | sed 's/!.*$//')

# Remove 'only: ...'
deps=$(echo "$deps" | sed 's/, *only.*$//')

# Remove lines without dependencies
deps=$(echo "$deps" | sed 's/^.*: *$//')

# Remove directories
deps=$(echo "$deps" | sed 's/^.*[/]//')

# Fix spacing around ':'
deps=$(echo "$deps" | sed 's/ *: */:/')

# Replace extension
deps=$(echo "$deps" | sed 's/[.]t/.o/')

# Replace 'use mod_xxx' by ' mod_xxx.mod'
deps=$(echo "$deps" | sed 's/use \(.*\)$/ \1.mod/')

# Remove lines with ^M without dependencies
deps=$(echo "$deps" | sed 's/^.*:\r//')

# Sort lines and remove duplicates
deps=$(echo "$deps" | sort -u)

# Print results
echo "$deps"
