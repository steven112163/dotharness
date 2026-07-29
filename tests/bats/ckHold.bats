#!/usr/bin/env bats
# Regression test for the CPUS default ordering bug: ckHold must set its own
# CPUS=32 default before sourcing ckCommon (which defaults CPUS to 128 for
# builds), or the holder silently requests 128 CPUs for a GPU-bound job. 32
# matches the run/profile scripts (ckRun, ck*Profile) that overlap into it.

setup() {
    CKHOLD="${BATS_TEST_DIRNAME}/../../bin/ckHold"
}

@test "ckHold usage reports the 32-CPU holder default, not ckCommon's 128" {
    run bash "$CKHOLD" -h
    [[ "$output" == *"CPUS=32"* ]]
}

@test "ckHold honors an explicit CPUS override in usage output" {
    run bash -c "CPUS=32 bash '$CKHOLD' -h"
    [[ "$output" == *"CPUS=32"* ]]
}
