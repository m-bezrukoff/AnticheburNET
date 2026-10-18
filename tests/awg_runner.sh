#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Run both production scripts with isolated command/device doubles. The socket
# predicate uses a file marker so this regression also runs without Linux TUN.
for runner in \
    anticheburnet/files/usr/bin/anticheburnet-awg-subscription-run \
    components/awg/files/usr/bin/anticheburnet-awg-run; do
    for scenario in ready timeout config_failure; do
        case_dir="$work/$(basename "$runner")-$scenario"
        mkdir -p "$case_dir/run/amneziawg" "$case_dir/run/anticheburnet"
        sed -e "s|/var/run|$case_dir/run|g" -e 's/\[ -S /[ -f /g' "$root/$runner" > "$case_dir/runner"
        set +e
        (
            # Mock a BusyBox build without fractional sleep support.
            sleep() {
                case "$1" in *[!0-9]*) echo "sleep: invalid number '$1'" >&2; return 1 ;; esac
                command sleep "$@"
            }
            ip() {
                printf '%s\n' "$*" >> "$case_dir/ip.log"
                if [[ $1 == link && $2 == show ]]; then return 1; fi
            }
            awg() {
                printf '%s\n' "$*" >> "$case_dir/awg.log"
                if [[ $scenario == config_failure ]]; then return 7; fi
            }
            amneziawg-go() {
                while ! builtin [ -f "$case_dir/run/anticheburnet/awg-acawg1.ready" ]; do
                    command sleep 1
                done
            }
            ucode() {
                if [[ $1 == -e ]]; then
                    case "$2" in
                        'sleep(100);')
                            printf 'wait\n' >> "$case_dir/waits"
                            if [[ $scenario != timeout ]]; then
                                touch "$case_dir/run/amneziawg/acawg1.sock"
                            fi
                            ;;
                        *'.mtu);') printf 1376 ;;
                        *'.addresses)'*) printf '10.7.0.2/32\nfd00:7::2/128\n' ;;
                        *) echo "Unexpected ucode expression" >&2; return 2 ;;
                    esac
                elif [[ $4 == extract ]]; then
                    printf 'profile\n' > "$7"
                elif [[ $4 == prepare* ]]; then
                    printf 'device\n' > "$6"
                    printf '{}\n'
                else
                    echo "Unexpected ucode command" >&2; return 2
                fi
            }
            set -- acawg1 "$case_dir/manifest" 312 1
            # Keep errexit effective in the sourced production runner.
            source "$case_dir/runner"
        ) > "$case_dir/output" 2>&1
        status=$?
        set -e
        if [[ $scenario == ready ]]; then
            [[ $status == 0 ]] || { cat "$case_dir/output" >&2; exit 1; }
            [[ $(wc -l < "$case_dir/waits") == 1 ]]
            grep -Eq '^setconf acawg1 .*/device.conf$' "$case_dir/awg.log"
            grep -Fxq 'link set dev acawg1 mtu 1376 up' "$case_dir/ip.log"
            for family in 4 6; do
                grep -Fxq -- "-$family route add default dev acawg1 table 312" "$case_dir/ip.log"
                grep -Fxq -- "-$family rule del priority 10400 oif acawg1 table 312" "$case_dir/ip.log"
            done
        elif [[ $scenario == timeout ]]; then
            [[ $status == 1 ]]
            [[ $(wc -l < "$case_dir/waits") == 50 ]]
            grep -Fxq 'AWG socket readiness timeout' "$case_dir/output"
            [[ ! -e "$case_dir/awg.log" ]]
        else
            [[ $status == 7 ]]
            grep -Eq '^setconf acawg1 .*/device.conf$' "$case_dir/awg.log"
            ! grep -q '^link set' "$case_dir/ip.log"
        fi
        [[ ! -e "$case_dir/run/anticheburnet/awg-acawg1.ready" ]]
        [[ -z $(find "$case_dir/run" -maxdepth 1 -name 'anticheburnet-awg.*' -print) ]]
    done
done
printf 'Both AWG runners pass readiness, routing, configuration failure, timeout and cleanup checks\n'
