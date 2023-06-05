# Delorean.exchange

Delorean.exchange (https://delorean.exchange) is a protocol for buying and selling yield.

For more information, consult the [documentation](https://delorean.gitbook.io/delorean/).

## Running tests

First, set up the env:

```
cp .env.example .env
# Fill in variables as needed
```

Run tests using forge:

```
forge test
```

## Generate coverage report

You can generate coverage report like this:

```
forge coverage --report lcov
genhtml lcov.info
```

If on macOS you get an error like

```
genhtml: ERROR: unable to open /cmd_line: Read-only file system
```

you can fix this by adding an output folder:

```
genhtml lcov.info -o output
```
