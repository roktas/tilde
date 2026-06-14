# TODO

- [ ] Fix `bin/tilde smoke` in Lima so plan smoke resolves the sibling home repository through a mounted path or an
  explicit `REPO_ROOT`. In the current guest shape, `/here/../home` resolves to guest `/home` and can fail with
  `mkdir: Permission denied`.
- [ ] Decide how `repair` or retry apply caches should relate to full deployment caches. A retry that only contains
  failed modules is useful operationally, but `last-apply.json` should not become misleading for status or later audits.
- [ ] Clean up duplicate Google Chrome apt source declarations produced or tolerated by the Linux/Chrome modules.
  Spinoza reports duplicate targets in `chrome.list` and `google-chrome.list` during every apt update.
- [ ] Investigate repeated `LC_ALL=C.UTF-8` warnings on remote Linux shells. Bootstrap recorded locale state as ok, but
  remote apply output still includes locale warnings from Bash and the Tilde sudo wrapper.
- [ ] Decide the right home-module shape for macOS Screen Sharing enablement. `home/macos` currently defers the
  Postinstall command on non-interactive SSH because `launchctl load -w` needs sudo; this may belong in an explicit
  manual/repair path rather than routine update apply.
- [ ] Make macOS Dropbox File Provider warnings more actionable. `preflight` can detect checkouts that are not marked
  keep-downloaded, but remote update closeout should also explain the expected user action or policy.
- [ ] Clarify `status` timestamps by separating deployment apply, refresh apply, and upgrade apply dates. The kant
  update showed "Last apply date" coming from a refresh cache, while the deployment apply cache still contained a
  deferred module.
