#!/usr/bin/env bash

function log_info() {
  >&2 echo -e "[\\e[1;94mINFO\\e[0m] $*"
}

function log_warn() {
  >&2 echo -e "[\\e[1;93mWARN\\e[0m] $*"
}

function log_error() {
  >&2 echo -e "[\\e[1;91mERROR\\e[0m] $*"
}

# check number of arguments
if [[ "$#" -le 2 ]]; then
  log_error "Missing arguments"
  log_error "Usage: $0 <current version> <next version>"
  exit 1
fi

curVer=$1
nextVer=$2
relType=$3

versionFile="Sources/HimalayaMcpCLI/Commands/VersionCommand.swift"

if [[ "$curVer" ]]; then
  log_info "Bump version from \\e[33;1m${curVer}\\e[0m to \\e[33;1m${nextVer}\\e[0m (release type: $relType)..."

  # replace in README
  sed -e "s/from: *\"$curVer\"/from: \"$nextVer\"/" README.md > README.md.next
  mv -f README.md.next README.md
else
  log_info "Bump version to \\e[33;1m${nextVer}\\e[0m (release type: $relType): this is the first release (skip README)..."
fi

# replace in the CLI version file (also on the first release)
sed -e "s/^let appVersion = \".*\"/let appVersion = \"$nextVer\"/" "$versionFile" > "$versionFile.next"
mv -f "$versionFile.next" "$versionFile"
