#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
launcher="$root/src/dis-estadistica"
tests_run=0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

pass() {
    tests_run=$((tests_run + 1))
    printf 'ok %d - %s\n' "$tests_run" "$1"
}

make_app() {
    local app_root=$1
    local payload_version=$2
    local content=$3
    local share="$app_root/usr/share/dis-estadistica"

    mkdir -p "$app_root/usr/bin" "$app_root/usr/lib/dosbox-staging/lib" "$share/payload"
    install -m 0755 "$launcher" "$app_root/usr/bin/dis-estadistica"
    printf 'test config\n' > "$share/dosbox.conf"
    printf 'test\n' > "$share/VERSION"
    for name in DIS.EXE GRAFDIS.EXE INVDIS.EXE; do
        printf '%s-%s\n' "$content" "$name" > "$share/payload/$name"
    done
    {
        printf 'schema=1\npayload_version=%s\n' "$payload_version"
        (cd "$share/payload" && sha256sum DIS.EXE GRAFDIS.EXE INVDIS.EXE)
    } > "$share/payload/payload.sha256"
}

make_fake_dosbox() {
    local path=$1
    cat > "$path" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${FAKE_DOSBOX_LOG:?}"
sleep "${FAKE_DOSBOX_SLEEP:-0}"
exit "${FAKE_DOSBOX_EXIT:-0}"
EOF
    chmod 0755 "$path"
}

run_launcher() {
    local app_root=$1
    local sandbox=$2
    shift 2
    DIS_APP_ROOT="$app_root" \
    DIS_DOSBOX_BIN="$sandbox/fake-dosbox" \
    DIS_DATA_HOME="$sandbox/data" \
    DIS_CONFIG_HOME="$sandbox/config" \
    DIS_STATE_HOME="$sandbox/state" \
    DIS_RUNTIME_HOME="$sandbox/runtime" \
    FAKE_DOSBOX_LOG="$sandbox/dosbox.args" \
        "$launcher" "$@"
}

sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
app_v1="$sandbox/app-v1"
app_v2="$sandbox/app-v2"
make_app "$app_v1" 1 v1
make_app "$app_v2" 2 v2
make_fake_dosbox "$sandbox/fake-dosbox"

run_launcher "$app_v1" "$sandbox" --prepare-only
[[ -f $sandbox/data/drive_c/DIS.EXE ]] || fail "fresh install did not create DIS.EXE"
cmp -s "$app_v1/usr/share/dis-estadistica/payload/DIS.EXE" "$sandbox/data/drive_c/DIS.EXE" || fail "fresh payload mismatch"
pass "fresh install provisions a validated drive C"

printf 'user output\n' > "$sandbox/data/drive_c/RESULT.TXT"
run_launcher "$app_v1" "$sandbox"
[[ -f $sandbox/data/drive_c/RESULT.TXT ]] || fail "second run removed user file"
grep -Fxq -- '--noprimaryconf' "$sandbox/dosbox.args" || fail "missing --noprimaryconf"
grep -Fxq -- '--nolocalconf' "$sandbox/dosbox.args" || fail "missing --nolocalconf"
pass "launch isolates DOSBox configuration and preserves user files"

run_launcher "$app_v2" "$sandbox" --prepare-only
grep -q '^v2-DIS.EXE$' "$sandbox/data/drive_c/DIS.EXE" || fail "upgrade did not replace managed file"
[[ -f $sandbox/data/drive_c/RESULT.TXT ]] || fail "upgrade removed unknown file"
[[ -d $sandbox/data/drive_c.backup ]] || fail "prepare-only upgrade did not retain backup"
pass "upgrade replaces managed payload and preserves unknown files"

printf 'corrupt\n' > "$sandbox/data/drive_c/DIS.EXE"
if run_launcher "$app_v2" "$sandbox" --prepare-only 2>/dev/null; then
    fail "corruption was accepted"
fi
run_launcher "$app_v2" "$sandbox" --repair --prepare-only
grep -q '^v2-DIS.EXE$' "$sandbox/data/drive_c/DIS.EXE" || fail "repair did not restore DIS.EXE"
grep -q '^corrupt$' "$sandbox/data/drive_c.backup/DIS.EXE" || fail "repair did not preserve divergent file"
pass "repair restores managed files and keeps a backup"

FAKE_DOSBOX_SLEEP=2 run_launcher "$app_v2" "$sandbox" &
first_pid=$!
sleep 0.2
if run_launcher "$app_v2" "$sandbox" --prepare-only 2>/dev/null; then
    kill "$first_pid" 2>/dev/null || true
    fail "concurrent launch acquired the lock"
fi
wait "$first_pid"
pass "session lock rejects a concurrent launch"

run_launcher "$app_v2" "$sandbox" --reset-data --yes
[[ ! -e $sandbox/data && ! -e $sandbox/config && ! -e $sandbox/state ]] || fail "reset left application data"
pass "reset removes only application-owned roots"

printf '1..%d\n' "$tests_run"
