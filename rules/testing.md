# Testing

## Before You Push

- Run the relevant test suite before every commit.
- All tests must pass before pushing to a shared branch.
- Never merge a PR with failing tests.
- Flaky tests get fixed immediately or quarantined with a tracking issue.

## Test Design

- Test behavior, not implementation details. Tests should survive refactoring.
- One logical assertion per test case.
- Tests must be independent. No shared mutable state, no execution order dependency.
- Use descriptive names: `BlockGemm_MPerBlock256_ReturnsCorrectOutput` over `test_3`.

## Organization

- Mirror source directory structure in test directories.
- Shared helpers and fixtures go in a common test utility directory.
- Tag slow tests (>30s) so they can be excluded from fast feedback loops.

## CI

- No `skip` or `todo` tests on main. Fix them or remove them.
- Run tests on every push and every PR.
- Set a timeout to catch hangs and infinite loops.

## Anti-Patterns

- A test that passes when the code under test is deleted is worthless.
- Do not test private methods directly. Go through the public interface.
- Do not mask failures by increasing timeouts.
- Do not copy-paste tests. Parameterize instead.
