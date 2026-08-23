# Contributing

Bug reports and pull requests are welcome. Please open an issue before making a substantial API
or gesture-behavior change.

## Development

The package requires Swift 6.2 and a macOS host for the AppKit bridge tests. Before submitting a
change, run:

```sh
swiftlint lint --strict
swift test
```

Add tests for observable gesture and accessibility behavior when changing the coordinator. Update
DocC when changing public API.

## Prose

Markdown is linted with Vale (`ai-tells`). Prefer plain punctuation over em dashes and other
banned AI-prose patterns.
