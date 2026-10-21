# Contributing to shipyard

Thank you for helping.
This page says how to report a problem, propose a change and build shipyard yourself.

## Reports and ideas

- **A bug:** open an issue with the bug template. Say what you did, what you expected and what happened, with your macOS version and `shipyard --version`.
- **An idea:** open an issue with the feature template. Say the problem first, then the change you have in mind.
- **A security problem:** do not open an issue. Follow [`SECURITY.md`](SECURITY.md).
- **A question about your configuration:** run `shipyard config check` first. It prints each problem in `config.toml` with its line.

## Building

You need macOS 14 or later and the Command Line Tools with Swift 6 (`xcode-select --install`).

```sh
git clone https://github.com/yahyabedirhan/shipyard.git
cd shipyard
make test       # runs the tests
make install    # builds, signs and copies Shipyard.app to /Applications, then opens it
```

The tests of the core and of the `shipyard` command also run on Linux with Swift 6.2: `swift test`.

## Pull requests

1. Open an issue first for anything larger than a small fix, so we agree on the change before you build it.
2. Branch from `main` and keep one change per pull request.
3. Add or change a test for each behaviour you change, and run `make test`.
4. Update the docs in the same pull request: `README.md`, `skills/shipyard/SKILL.md` for a configuration key, `schema/config.schema.json` for its schema, and `CHANGELOG.md` under Unreleased.
5. Write commit messages in lowercase, with a Conventional Commits type on the subject line, such as `fix(panel): keep the scroll position on refresh`.

The design of the code is in [`docs/low-level-design.md`](docs/low-level-design.md), the words the project uses are in [`GLOSSARY.md`](GLOSSARY.md), and the design of the `shipyard` command is in [`docs/cli-design.md`](docs/cli-design.md).

## Forks

A fork that signs in with GitHub needs its own OAuth App.
The README's Forks section says how.

## License

By contributing, you agree that your contribution is licensed under the [Apache License 2.0](LICENSE), as the rest of the code is.
