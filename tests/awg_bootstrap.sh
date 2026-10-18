#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ucode -L "$root/anticheburnet/files/usr/lib" "$root/tests/awg_bootstrap.uc"
