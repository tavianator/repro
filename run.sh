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
        results="$_dir/$(date '+%Y/%m/%d/%T')"
        if [ -e "$results" ]; then
            _die $EX_CANTCREAT '"%s" already exists' "$results"
        fi
    else
        results=$(mktemp -d)
        at-exit rm -r "$results"
    fi

    init="$results/init"
    setup="$results/setup"
    teardown="$results/teardown"
    as-user mkdir -p "$init" "$setup" "$teardown"

    # Make the EXIT trap output to the teardown log
    _before_exit _phase 'Tearing down ...'
    _before_exit _redirect "$(realpath -- "$teardown")" exec

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

    if ! is-function bench; then
        _die $EX_DATAERR '%s does not define the function bench()' "$script"
    fi

    if is-function setup; then
        export SETUP_DIR="$setup"
        _redirect "$SETUP_DIR" _phase 'Running setup() ...'
        _redirect "$SETUP_DIR" setup "$@"
    fi

    local run
    for run in $(seq -w "$_runs"); do
        export BENCH_DIR="$results/runs/$run"
        as-user mkdir -p "$BENCH_DIR"

        _redirect "$BENCH_DIR" _phase 'Running bench(), iteration %s ...' "$run"
        _redirect "$BENCH_DIR" as-user "$0" _bench "$script" "$@"
    done
}
