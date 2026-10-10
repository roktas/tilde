# TODO

- [ ] Fix `bin/tilde smoke` in Lima so plan smoke resolves the sibling home repository through a mounted path or an
      explicit `REPO_ROOT`. In the current guest shape, `/here/../home` resolves to guest `/home` and can fail with
      `mkdir: Permission denied`.
- [x] Clean up duplicate Google Chrome apt source declarations produced or tolerated by the Linux/Chrome modules.
      Spinoza reports duplicate targets in `chrome.list` and `google-chrome.list` during every apt update.
- [ ] Verify that router/apply locale normalization removes repeated locale warnings on remote Linux shells. Bootstrap
      records locale state as ok, and Tilde now normalizes C/POSIX locales to `en_US.UTF-8`, but this still needs a remote
      Linux update run to confirm.
- [x] Make macOS Dropbox File Provider warnings more actionable. `preflight` can detect checkouts that are not marked
      keep-downloaded, but remote update closeout should also explain the expected user action or policy.
- [x] Print the current action ID on apply stderr so silent package commands and module blocks can be identified.
      The apply smoke test observes this output before exercising stale-lock recovery.

Apply caches and module `done` maps are absent from the current stateless model. They are not repair prerequisites.
