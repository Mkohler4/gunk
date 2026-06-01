# Contributing to gunk

Thanks for stopping by. Gunk is in **very early days** — we are still locking
the architecture and product shape. We're not ready for big PRs from strangers
yet, but we are absolutely ready for **issues, ideas, and small fixes**.

## What's helpful right now

- **Issues describing your gunk.** "Here's a project I'd want to extract auth
  from. Here's the file tree." Real examples drive the indexer/extractor design.
- **Issues calling out broken assumptions.** Did the README sell you something
  that isn't true? File it.
- **Naming bikeshed.** What's the right verb for "extract"? `salvage`? `lift`?
  Tell us.
- **Small docs PRs.** Typos, broken links, README clarifications.

## What's not helpful yet

- **Large feature PRs without a prior issue.** The roadmap is moving fast and we
  don't want to merge something we'll throw away in two weeks.
- **Adding new languages, runtimes, or frameworks** before ADR-0002 is settled.
- **Refactors of code that doesn't exist yet.**

## Process

1. **Open an issue first** for anything beyond a typo. Describe the use case in
   plain English, not the implementation.
2. **One commit, one logical change.** We use [Conventional
   Commits](https://www.conventionalcommits.org/en/v1.0.0/) (`feat:`, `fix:`,
   `docs:`, `chore:`, `refactor:`, `test:`).
3. **Keep PRs small.** A 50-line PR gets reviewed today; a 500-line PR gets
   reviewed someday.
4. **CI must be green.** Lint + typecheck + test all pass before merge.
5. **Update the CHANGELOG** under `[Unreleased]` for any user-visible change.

## Code of conduct

Be kind. See [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) for the formal version.

## License

By contributing, you agree your contribution is licensed under the MIT license
(see [`LICENSE`](LICENSE)).
