# Contributing

Thanks for contributing to Git Scope.

## Local setup

1. Install dependencies:
   - `npm install`
2. Install Python `pre-commit`:
   - `pip install pre-commit`
3. Install git hooks:
   - `pre-commit install`

## Development workflow

1. Create a branch for your change.
2. Make focused commits with clear messages.
3. Run checks before pushing:
   - `npm test`
   - `pre-commit run -a`

## Test policy

Tests are required for all functionality changes.

- If you change TypeScript logic, update or add tests in `test/*.test.js`.
- If you change Neovim Lua logic, update or add tests in `test/lua/git_scope_test.lua`.
- If behavior changes, tests must verify the new behavior and any regression risk.

Pull requests that change behavior without tests are considered incomplete.

## Pull request checklist

- [ ] Code compiles locally
- [ ] `npm test` passes
- [ ] `pre-commit run -a` passes
- [ ] New behavior is covered by tests
- [ ] README or docs updated when user-facing behavior changes
