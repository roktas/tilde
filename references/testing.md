# Testing

Use Lima with the external `"there"` helper for end-to-end provisioning tests.

## Lima

The Tilde smoke wrapper expects `"there"` to be available in `PATH`. Install the `there` package, or activate an
environment that provides a compatible `"there"` command.

This skill intentionally does not encode how `"there"` is installed. See the `there` documentation for command behavior
and detailed usage.

Run the normal Tilde smoke script inside the Lima instance:

```bash
bin/smoke
```

Run the bootstrap helper inside the Lima instance:

```bash
bin/smoke boot
```

For fast repeated tests, stop the instance instead of destroying it:

```bash
bin/smoke stop
```

For a fresh-host test, destroy the instance explicitly:

```bash
bin/smoke destroy
```

Clean Lima's image cache only when explicitly requested:

```bash
bin/smoke prune
```

## Direct Command

Use `"there"` directly when a test needs a custom command:

```bash
there run bash -lc 'cd /here && .agents/tests/provision/smoke.sh'
```
