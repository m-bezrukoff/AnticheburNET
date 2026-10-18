#!/bin/sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work=$(mktemp -d)
cleanup() {
    for pid_file in "$work"/*/*.pid; do
        [ -f "$pid_file" ] || continue
        kill "$(cat "$pid_file")" 2>/dev/null || true
    done
    rm -rf "$work"
}
trap cleanup EXIT

# Simulate setconf blocked in endpoint resolution, then the procd TERM deadline.
# Use real child processes and the production /bin/sh runner, without TUN or DNS.
for runner in \
    anticheburnet/files/usr/bin/anticheburnet-awg-subscription-run \
    components/awg/files/usr/bin/anticheburnet-awg-run; do
    case_dir="$work/$(basename "$runner")"
    mkdir -p "$case_dir/bin" "$case_dir/run/amneziawg" "$case_dir/run/anticheburnet"
    export AWG_TEST_DIR="$case_dir"
    sed -e "s|/var/run|$case_dir/run|g" -e 's/\[ -S /[ -f /g' "$root/$runner" > "$case_dir/runner"
    cat >"$case_dir/bin/ip" <<'EOF_IP'
#!/bin/sh
if [ "$1 $2" = 'link show' ]; then exit 1; fi
EOF_IP
    cat >"$case_dir/bin/ucode" <<'EOF_UCODE'
#!/bin/sh
case "$4" in
    extract) printf 'profile\n' > "$7" ;;
    prepare) printf 'device\n' > "$6"; printf '{}\n' ;;
esac
EOF_UCODE
    cat >"$case_dir/bin/amneziawg-go" <<'EOF_GO'
#!/bin/sh
echo $$ > "$AWG_TEST_DIR/go.pid"
trap 'rm -f "$AWG_TEST_DIR/run/amneziawg/acawg1.sock"' EXIT
trap 'exit 143' TERM
: > "$AWG_TEST_DIR/run/amneziawg/acawg1.sock"
while :; do sleep 1 & wait $!; done
EOF_GO
    cat >"$case_dir/bin/awg" <<'EOF_AWG'
#!/bin/sh
echo $$ > "$AWG_TEST_DIR/setconf.pid"
exec sleep 60
EOF_AWG
    chmod +x "$case_dir/bin/"*
    PATH="$case_dir/bin:$PATH" /bin/sh "$case_dir/runner" acawg1 "$case_dir/manifest" 312 1 >"$case_dir/output" 2>&1 &
    runner_pid=$!
    echo "$runner_pid" > "$case_dir/runner.pid"
    i=0
    while [ "$i" -lt 5 ]; do
        [ ! -f "$case_dir/setconf.pid" ] || break
        sleep 1
        i=$((i + 1))
    done
    [ -f "$case_dir/setconf.pid" ] || { cat "$case_dir/output" >&2; exit 1; }
    (
        sleep 5
        : > "$case_dir/forced"
        kill -KILL "$runner_pid" 2>/dev/null || true
    ) &
    watchdog=$!
    kill -TERM "$runner_pid"
    result=0
    wait "$runner_pid" || result=$?
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    [ "$result" = 143 ] && [ ! -e "$case_dir/forced" ] || {
        echo 'Runner must handle TERM before the procd kill deadline' >&2; exit 1;
    }
    for child in go setconf; do
        if kill -0 "$(cat "$case_dir/$child.pid")" 2>/dev/null; then
            echo "Orphaned $child process after stopping $runner" >&2; exit 1
        fi
    done
    [ ! -e "$case_dir/run/amneziawg/acawg1.sock" ]
    [ ! -e "$case_dir/run/anticheburnet/awg-acawg1.ready" ]
    [ -z "$(find "$case_dir/run" -maxdepth 1 -name 'anticheburnet-awg.*' -print)" ]
done
printf 'Both AWG runners clean up interrupted endpoint resolution before the stop deadline\n'
