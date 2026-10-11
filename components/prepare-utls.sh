#!/usr/bin/env bash
# Backport current Xray browser presets without changing subscription fingerprints.
set -euo pipefail
source_dir="$1"
work="$2"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$work"
cd "$source_dir"
go mod download github.com/metacubex/utls@v1.8.7
module_dir="$(go list -m -f '{{.Dir}}' github.com/metacubex/utls)"
# Fresh work directory per invocation; the Go module cache remains untouched.
utls_dir="$(mktemp -d "$work/anticheburnet-utls.XXXXXX")"
cp -a "$module_dir/." "$utls_dir/"
chmod -R u+w "$utls_dir"
git -C "$utls_dir" apply "$root/components/patches/utls-modern-browser-presets.patch"
cp "$root/components/tests/utls_browser_presets_test.go" "$utls_dir/anticheburnet_browser_presets_test.go"
cp go.mod "$work/sing-box.mod"
cp go.sum "$work/sing-box.sum"
go mod edit -modfile="$work/sing-box.mod" -replace="github.com/metacubex/utls=$utls_dir"
go test -modfile="$work/sing-box.mod" github.com/metacubex/utls -run '^TestAnticheburNETSubscriptionBrowserPresets$' -count=1
