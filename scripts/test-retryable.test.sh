#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check() {
    expected=$1
    messages=$2
    if printf '%s\n' "$messages" | sh "$root/scripts/test-retryable.sh"; then actual=0; else actual=1; fi
    [ "$actual" = "$expected" ] || { printf 'unexpected retry classification: %s\n' "$messages" >&2; exit 1; }
}
check 1 ''
check 1 'testName()'
check 0 'testName()
    Failed to get screenshot'
check 0 'testName()
    Timed out while evaluating UI query
    Failed to terminate'
check 1 'testName()
    XCTAssertTrue failed - no curve'
check 1 'testName()
    Failed to get screenshot
    XCTAssertTrue failed - no curve'
check 0 'testName()
    Test exceeded execution time allowance of 1 minute'
check 0 'testName()
    Test exceeded execution time allowance of 10 minutes'
check 0 'firstTest()
    Failed to get screenshot
secondTest()
    Test exceeded execution time allowance of 10 minutes'
check 1 'firstTest()
    Test exceeded execution time allowance of 10 minutes
secondTest()
    XCTAssertEqual failed'
check 1 'testName()
    XCTAssertTrue failed - Test exceeded execution time allowance of 10 minutes'
check 1 'testName()
    Test crashed with signal kill'
printf 'retry classification checks passed\n'
