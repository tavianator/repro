#!/hint/bash

# Copyright © Tavian Barnes <tavianator@tavianator.com>
# SPDX-License-Identifier: 0BSD

## Subcommands for running benchmarks

# tailfin _bench
# (internal subcommand for a single bench() run)
_bench() {
    # shellcheck source=./check.sh
    source "$@"
    shift
    (bench "$@")
    exit $?
}

# Describe a benchmarking run
_info() {
    _underline "${_args[*]}" >&2

    printf 'uname:   '
    uname -a
    printf 'uptime: '
    uptime
    printf 'cwd:     %s\n' "$PWD"
    printf 'results: %s\n' "$results"
    printf 'runs:    %s\n' "$_runs"
    printf 'user:    %s\n' "$_user"
    printf 'quiet:   %s\n' "$_quiet"
    printf 'script:  %s\n' "$script"
}

# tailfin run
_run() {
    local script="$1"
    shift

    # Set up the working directory
    local results
    if [ "$_dir" ]; then
        results="$_dir/$(date '+%Y/%m/%d/%H.%M.%S')"
        if [ -e "$results" ]; then
            _die $EX_CANTCREAT '"%s" already exists' "$results"
        fi
    else
        results=$(as-user mktemp -d)
        defer rm -r "$results"
    fi

    local init="$results/init"
    local setup="$results/setup"
    local teardown="$results/teardown"
    as-user mkdir -p "$init" "$setup" "$teardown"

    # Make the EXIT trap output to the teardown log
    teardown=$(realpath -- "$teardown")
    defer eval '_reap "$_logjob" || :'
    _early_defer _bg _logjob _logtail "$teardown/syslog"
    _early_defer _phase 'Tearing down ...'
    _early_defer _redirect "$teardown" exec

    # Save system logs separately for each phase
    local logjob
    _bg logjob _logtail "$init/syslog"

    # Describe the benchmarking run
    _redirect "$init" _info

    # Save the complete environment
    if [ "$init" ]; then
        as-user touch "$init/env"
        env >"$init/env"
    fi

    # Load and run the script
    _redirect "$init" _phase 'Loading "%s" ...' "$script"
    _redirect "$init" source "$script" "$@"

    _reap "$logjob" || :

    if ! is-function bench; then
        _die $EX_DATAERR '%s does not define the function bench()' "$script"
    fi

    if is-function setup; then
        export SETUP_DIR="$setup"

        _bg logjob _logtail "$SETUP_DIR/syslog"

        _redirect "$SETUP_DIR" _phase 'Running setup() ...'
        _redirect "$SETUP_DIR" setup "$@"

        _reap "$logjob" || :
    fi

    local run
    for run in $(seq -w "$_runs"); do
        export BENCH_DIR="$results/runs/$run"
        as-user mkdir -p "$BENCH_DIR"

        _bg logjob _logtail "$BENCH_DIR/syslog"

        _redirect "$BENCH_DIR" _phase 'Running bench(), iteration %s ...' "$run"
        _redirect "$BENCH_DIR" as-user "$0" _bench "$script" "$@"

        _reap "$logjob" || :
    done
}
