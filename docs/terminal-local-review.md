# Phone-local terminal outcome checks

Notification macros now check each quiet tmux pane locally on the phone. The
existing SSH connection captures at most 40 recent history lines plus the pane
screen. The review excerpt is bounded to 40 lines and 6,000 characters, isolates
the latest bullet-style assistant reply when a turn boundary is clear, and
retains potentially shared caveats when that boundary is ambiguous.

The phone renders this excerpt as a monochrome terminal snapshot in memory.
This is a reconstruction of the selected pane's bottom section, not a capture
of whichever Android app happens to be foreground. Bundled ML Kit Latin OCR
runs on this image without a model download or remote OCR endpoint. The bitmap
is discarded after recognition. There is no screenshot/transcript upload, saved
review image, cloud completion request, or home-model request in this path.
SSH still needs connectivity to read fresh terminal output; stale and disconnected
panes retain their existing unknown state.

Analysis uses English keyword rules, not a generative language model. The
review starts at the latest reply bullet (Claude Code `●`, Codex `•`); earlier
progress messages in the same turn are superseded. The agent's own input box
(`› Ask Codex to do anything`, an empty `❯`) and status footer are not treated
as a new request, while an echoed submitted prompt still is.

1. **Result line.** Authoring macros can ask the agent to end
   with one plain line, e.g. `RESULT: DONE 20/20 approved, 0 failed, 0 skipped`.
   `DONE` with equal counts and no nonzero failure reads **✓ Done**. `CHECK`, a
   short count (18/20) or a nonzero failure reads **⚠ Check**. `EMPTY` (empty
   roster) reads **⚠ Check · Queue empty**. A template with placeholders, as
   echoed from a prompt, is ignored.
2. **Keywords** when no result line is present: "all 20 … approved",
   "20/20 approved/submitted", "N approved" with a zero-failure phrase or a
   leading "Done", and the earlier general completion phrases. Zero reports
   such as "0 failed", "Skipped: 0", "Zero failures" and "No topics were
   skipped or left unresolved" count as clean. Recovered failures ("a temporary
   connection failure was recovered") do not count against the report.
3. **Check** wins over Done: nonzero failed/skipped/unresolved counts, partial
   counts, "could not", "not approved", "please …", a closing question, or an
   empty roster/queue.
4. Plans ("I'll …", "I'm using …"), conditionals and `Working (… esc to
   interrupt)` stay **? Unknown**.

The source and OCR classifications must agree; disagreement remains unknown,
and evidence always comes from the original excerpt. OCR count confusions such
as `2O/2O` or `O failed` are normalized first. Rules were tuned against 295 real
end-of-batch Codex reports from these macros (2026-10). 244 read Done, every
empty-roster report read Check, and progress updates stayed Unknown. On an
Android 14 emulator, bundled ML Kit OCR of 32 rendered reports (including result
lines) agreed with the source verdict in all 32 cases. These rules cannot
verify the underlying work.

## Auto-run, timers and averages

**Allow auto-run** (Notification macros settings, on by default) only makes
automation available. Nothing runs by itself until you tap **Start auto-run**.
The main **DevOTA terminal** notification has one Start auto-run button, right
after Disconnect, that turns on every watched window; each window's own card in
the DevOTA window controls group also has one. A started window shows
`· auto on`.

A started window runs its macro 10 seconds after it stops changing (after the
quiet period, so about 20 seconds after the last output with the default
10-second quiet period), **whatever the OCR verdict says**. The ✓ Done / ⚠ Check
/ ? Unknown label is shown for information. The countdown leads the row:
`Auto-run in 8s · ✓ Done · 20/20 approved, 0 failed`. The one exception is an
empty queue (`RESULT: EMPTY` or "roster is empty"): automation stops with
`⚠ Auto-run stopped: queue empty` instead of rerunning empty batches.
**Stop auto-run** (the same main-notification button, or a window's card) turns
it off. The manual Run button always remains. Automation is not remembered
across app restarts or setting changes.

Starting automation, and every automatic run, first asks tmux for the window's
foreground program (`#{pane_current_command}`). If the agent has exited and the
window is a bare shell (bash, zsh, sh, fish, PowerShell, cmd and similar), or
the tmux window is gone, nothing is typed. Automation turns off with
`⚠ Auto-run stopped: no agent running in this window (bash)`. Codex reports
`node` (or `codex`) and Claude Code reports `claude`.

Each automatic run then uses the usual Run path with the same fresh-capture and
identity checks. New output cancels the countdown. One screen never auto-runs
twice, even if the run fails, and after a run nothing auto-runs again until the
window's output changes.

Each notification run starts a timer (`⏱ 12m (avg 18m)`). When the window goes
quiet after the run's output (whatever the verdict), the time from sending to
the last output is recorded
**per macro** (the last 10 runs, averaged), stored on the phone, and starts
from the first completed run. If a run passes 1.5× its macro's average (and
at least two minutes over), the card leads with
`⚠ 27m (avg 18m) · slower than usual, check it`. Runs typed in the
interactive terminal are not timed.

Enable or disable this in Terminal > SSH settings > Notification macros >
Check conclusions locally on this phone. The previous server/terminal_review.py
helper remains available for separate legacy clients, but the production SSH
watch transport no longer invokes it.

# ZeroTier recovery

Recovery runs on phone even with a disconnected relay. It requires the saved
whole-device permission and Android Accessibility service. Notification recovery
checks these before any macro action and preserves SSH when it cannot start.
In Agent, enable whole-device control and press Start Agent to apply that setting;
relay connectivity is not required for the local actions. If needed, enable
DevOTA in Android Accessibility settings.

The shipped recovery definition no longer syncs over the network before repairing
that network. It removes the eight-second foreground-package assertion after
turning ZeroTier on, reopens ZeroTier, and polls its online UI for up to 60 seconds.
OFFLINE is explicitly excluded so its substring "ONLINE" cannot satisfy the check.
Cached shipped steps are upgraded by the app; unrelated macros are preserved.
The separate computer relay must also listen on port 8083 for Agent connectivity.

Observed saved failures: September 30 and October 2 stopped after the on-toggle
because another app became foreground. Two October 3 runs stopped on the initial
Back action because whole-device control was disabled. On October 3 the Windows
ZeroTier service was running at the configured address while the relay port had
no listener. Starting the existing wrapper restored the listener and WebSocket
handshake response; that alone does not establish a phone reconnect.

Validation: 215 Flutter tests passed in an isolated checkout of these changes;
231 passed in the working tree including existing local changes. Flutter analysis
reported no issues in both. The native bundled OCR instrumentation test passed (1 test, Android 36
emulator), preserving negation and partial counts. Physical phone recovery
acceptance remains separate from the saved-run diagnosis and regression checks.
