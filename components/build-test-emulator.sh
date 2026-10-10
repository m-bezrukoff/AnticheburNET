#!/usr/bin/env bash
# CI only: QEMU 8.2 user mode lacks SO_MARK, required by router routing.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="$root/.build/test-qemu"
revision=11aa0b1ff115b86160c4d37e7c37e6a6b13b77ea
git init "$destination"
git -C "$destination" remote add origin https://github.com/qemu/qemu.git
git -C "$destination" fetch --depth 1 origin "$revision"
git -C "$destination" checkout --detach FETCH_HEAD
[[ "$(git -C "$destination" rev-parse HEAD)" == "$revision" ]]
python3 - "$destination" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
header = root / "linux-user/generic/sockbits.h"
text = header.read_text()
assert "#define TARGET_SO_PROTOCOL" in text
header.write_text(text.replace("#define TARGET_SO_PROTOCOL", "#define TARGET_SO_MARK                 36\n\n#define TARGET_SO_PROTOCOL", 1))
source = root / "linux-user/syscall.c"
text = source.read_text()
setter = "        case TARGET_SO_PRIORITY:\n\t\toptname = SO_PRIORITY;\n\t\tbreak;"
getter = "        case TARGET_SO_PRIORITY:\n            optname = SO_PRIORITY;\n            goto int_case;"
assert text.count(setter) == 1 and text.count(getter) == 1
text = text.replace(setter, setter + "\n        case TARGET_SO_MARK:\n                optname = SO_MARK;\n                break;")
text = text.replace(getter, getter + "\n        case TARGET_SO_MARK:\n            optname = SO_MARK;\n            goto int_case;")
source.write_text(text)
PY
mkdir -p "$destination/build"
cd "$destination/build"
../configure --target-list=aarch64-linux-user --without-default-features \
  --enable-linux-user --disable-system --disable-docs --disable-werror
make -j2
sudo install -m755 qemu-aarch64 /usr/local/bin/qemu-aarch64
qemu-aarch64 --version
