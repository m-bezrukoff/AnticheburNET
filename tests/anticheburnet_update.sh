#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
# Exercise the production decision and checksum functions with an isolated dispatcher.
awk '/^let mode = ARGV\[0\]/{exit} {print}' "$ROOT_DIR/anticheburnet/files/usr/lib/components/action.uc" > "$WORK_DIR/check.uc"
printf 'test package\n' > "$WORK_DIR/package.apk"
export UPDATE_TEST_FILE="$WORK_DIR/package.apk"
export UPDATE_TEST_HASH
UPDATE_TEST_HASH="$(sha256sum "$WORK_DIR/package.apk" | cut -d' ' -f1)"
cat >> "$WORK_DIR/check.uc" <<'UC'
let called = "";
let compare = "-1";
latest_anticheburnet_version = function() { return "1.0.2"; };
helper_success = function(mode, args) { return true; };
helper_output = function(mode, args) { return compare; };
install_anticheburnet = function(version) { called = "install:" + version; };
check_anticheburnet = function() { called = "check"; };
resolve_anticheburnet_release = function(version) { return { packages: [], cores_required: false }; };
check_and_update_anticheburnet();
if (called != "install:1.0.2") die("New release was not installed");
for (let value in [ "0", "1", "" ]) {
    compare = value;
    called = "";
    check_and_update_anticheburnet();
    if (called != "check") die("Current, development or failed comparison installed a release");
}
let path = getenv("UPDATE_TEST_FILE");
let digest = getenv("UPDATE_TEST_HASH");
if (!verify_release_package(path, "package.apk", digest + "  ./package.apk\n"))
    die("Valid release checksum rejected");
for (let manifest in [ digest + "  other.apk\n", "00  package.apk\n",
    digest + "  package.apk\n" + digest + "  package.apk\n" ]) {
    if (verify_release_package(path, "package.apk", manifest)) die("Invalid manifest accepted");
}
fs.writefile(path, "corrupted");
if (verify_release_package(path, "package.apk", digest + "  package.apk\n"))
    die("Corrupted package accepted");
print("AnticheburNET update decision and integrity checks passed\n");
UC
ANTICHEBURNET_VERSION=1.0.1 ucode -L "$ROOT_DIR/anticheburnet/files/usr/lib" "$WORK_DIR/check.uc"
