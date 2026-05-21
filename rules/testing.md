# Testing

## Before You Push

- Run the relevant test suite before every commit.
- All tests must pass before pushing to a shared branch.
- Never merge a PR with failing tests.
- Flaky tests get fixed immediately or quarantined with a tracking issue.

## Coverage

- 80% line coverage minimum on new code.
- 75% branch coverage minimum on new code.
- Coverage must not decrease on any PR.
- Exclude generated code, type definitions, and config files from metrics.

## Test Design

- Test behavior, not implementation details. Tests should survive refactoring.
- One logical assertion per test case.
- Tests must be independent. No shared mutable state, no execution order dependency.
- Use descriptive names: `should_reject_expired_token` over `test_token_3`.

## Organization

- Mirror source directory structure in test directories.
- Shared helpers and fixtures go in a `testutils` or `__tests__/helpers` directory.
- Tag slow tests (>30s) so they can be excluded from fast feedback loops.

## Mocking

- Mock at system boundaries: HTTP, database, filesystem, clock, randomness.
- Never mock the unit under test.
- Prefer fakes (in-memory implementations) over mocks for complex interfaces.
- Assert on behavior and outputs, not on call counts.

## CI

- No `skip` or `todo` tests on main. Fix them or remove them.
- Run tests on every push and every PR.
- Fail the build when coverage drops below thresholds.
- Run tests in parallel. Set a 10-minute timeout to catch infinite loops.

## Anti-Patterns

- A test that passes when the code under test is deleted is worthless.
- Do not test private methods directly. Go through the public interface.
- Do not mask failures by increasing timeouts.
- Do not copy-paste tests. Parameterize instead.