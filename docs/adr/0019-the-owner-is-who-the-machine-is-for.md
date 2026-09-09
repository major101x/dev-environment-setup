# The Owner is who the machine is for, and root is only the privilege

The script requires root — `require_root` exits 1 without it — and until now root was the only
actor it had. Every `$HOME` and every `~` in `setup.sh` therefore resolved to `/root`, in twelve
Install Steps and in the script's own state. Nothing named the person the machine was actually
being set up for, so nothing could aim at them.

What that produced, reported from a real run: the install screen said `✔ base dependencies · go,
golangci-lint, air · go go1.23.5 · air v1.67.4`, and `go` was not found in the shell of the person
who ran it. Both statements were true. `/usr/local/go/bin/go` existed; the `PATH` line went to
`/root/.bashrc`; `air` went to `/root/go/bin`, which is exactly where its Version probe
(`air -v || "$HOME/go/bin/air" -v`) found it and read the version off. The run was describing
root's machine to a person who did not have one.

Someone had already met this once and worked around it for a single Tool: `install_opencode`
carries the comment *"installer puts binary in ~/.opencode/bin or /root/.opencode/bin"* and
symlinks into `/usr/local/bin` to dodge it. The workaround is the tell — there was no concept to
fix, only a symptom to patch.

## Decision

**The Owner is a first-class concept.** The person the machine is for, read from `SUDO_USER`. Root
is the privilege the script runs *with*, not the actor it runs *for*. Every home-relative write,
every Presence probe and every Version probe answers for the Owner.

**Where there is no Owner, root is the Owner — and the run says so.** `SUDO_USER` is empty for a
root container, a cloud image whose first login is root, `su -`, and CI. Those are legitimate uses
of a machine provisioner, so they are not refused. But the fallback is announced, because the
silent version of exactly this is the bug being fixed: nothing ever said whose machine was being
set up. Anthropic's own `claude.ai/install.sh` draws the same three-way line for the same reason —
`id -u` is 0 **and** `SUDO_USER` is set **and** it is not `root` — and its comment says plainly
that plain root with no sudo is unaffected.

**Privileges are dropped per command, not per Step.** Anything that does not need root runs as the
Owner via `runuser`. The alternative — staying root with `HOME` redirected — creates root-owned
files inside the Owner's home, which breaks `bun upgrade`, `npm install -g`, `rustup update` and
`cargo install` for them forever after. Ownership is the one thing that cannot be reliably repaired
afterwards, so it is established at write time.

`HOME` is exported as the Owner's for the whole file, which is what lets a probe answer for them
without every probe naming them — and it cuts the other way too: a command *root* runs with it set
leaves a root-owned directory in their home, the very thing this decision exists to avoid. Three do
(Chrome's headless check, the Docker smoke test, the Qdrant container), and each needs root, so
there is an `as_root` counterpart that puts root's own `HOME` back for the duration.

The cost is admitted rather than hidden: an Install Step is now **mixed-privilege**. `install_opencode`
runs a vendor installer as the Owner and `ln -sf … /usr/local/bin` as root, in one body, and every
such body has to say which of its commands is which.

**Reachability is separate from installation, and is repaired on every run.** A Tool on disk that
the Owner's shell cannot find is installed but not Reachable. The two were tangled: `install_go`
opens with `if command -v go; then … return; fi`, and that early return jumps over the `PATH`
append twenty lines below it — so a machine that has Go can never acquire the line that makes Go
usable. The runner was already right about this (`run_install_step` deliberately calls an
`already installed` Step's body, *"skipping the call outright would drop the PATH and config lines
some installers keep doing after the binary exists"*); the Step bodies were wrong. A Step's early
return may not skip the Reachability write.

**`claude-code` is why the Reachability file is not optional.** Every other vendor that installs into
a home writes its own rc line — bun, uv, rustup, nvm. Anthropic's installer writes none at all and
never mentions `PATH` (read off the live file on 2026-09-09), so its binary in `$HOME/.local/bin`
would be installed and permanently unfindable with nothing of its own to fall back on. The file's
contents are declared in one function and derived by the test that checks them, so a line dropped
from it cannot pass unnoticed — and the one Tool with no fallback is named in an assertion of its
own, because deriving alone would not have caught its removal.

**The lines this repo authors live in `/etc/profile.d/dev-setup.sh`, rewritten whole.** Idempotent
by construction rather than by `grep -q` guard, and no home directory is needed to hold it. The
four vendors that insist on writing a shell rc keep doing so and land correctly, because under the
decision above they run as the Owner. One of them settles this: `bun`'s installer has no
`--no-modify-path`, no environment variable, no lever of any kind — it appends to the first
writable of `$HOME/.bash_profile`, `$HOME/.bashrc`. Nothing can steer it except `$HOME` itself, so
"suppress every vendor and own the write centrally" was never reachable.

**A Presence probe answers what is on disk for the Owner, not what is on their `PATH`.** The
tempting alternative — probe for reachability, so an unreachable Tool reports absent and reinstalls
— repairs a one-line text problem with a 70MB download, and would have re-extracted a Go tarball
that was already fine. Presence and Reachability are asked separately and repaired separately.

**Persistence follows the Owner, and is written as them.** The picks record what a person chose,
not what the machine has; the machine's state is what the Presence probes answer. So two people on
one box each keep their own `--replay`, and the file they own is one they can overwrite. The same
holds for the Log.

## Consequences

**A machine provisioned by the old script reinstalls.** The probes now look in the Owner's home,
find nothing, and every affected Step re-runs — nvm, Node, Rust, bun, uv, opencode, air and the
Puppeteer Chrome download, into the right home this time. Correct, and slow once. The `/root` copies
are left where they are: migrating them means rewriting ownership, the absolute paths baked into
nvm and cargo shims, and the rc lines, and a half-moved cargo is worse than a re-downloaded one.
What the run does do is *say* it — finding `/root/.nvm` or `/root/.cargo` is reported on the
Summary, so the reinstall is not another thing happening for an invisible reason.

**`claude-code` starts working.** Its installer refuses to run under sudo-from-a-user and
`install_claude_code` pipes it to `bash` with no `|| warn`, so that Step fails today and the Tool
`ai-agents` names cannot be installed at all. Running as the Owner means `id -u` is no longer 0 and
the guard never fires — no `CLAUDE_INSTALL_ALLOW_SUDO` escape hatch needed.

**Puppeteer's system libraries are installed by apt directly.** The Step used to try
`puppeteer browsers install chrome --install-deps` with an apt list as its fallback. `--install-deps`
is the half that needs root while `npx` is the half that needs the Owner's nvm, so the two cannot be
one command any more; the apt list was already written down, and it is what root runs.

**`gh auth login` authenticates the Owner.** It wrote `$HOME/.config/gh/hosts.yml`, so the
credential landed in `/root` and the person's own `gh` stayed logged out. It is also the one place
a run reads the terminal, so `runuser` passing the controlling tty through is worth one test rather
than one assumption.

**Three static guards hold the line, not one.** Twelve Install Steps carried this bug, which is
twelve chances at a thirteenth. `$HOME` could not itself be banned from a Step body — it is the
Owner's now, so it is the *correct* spelling — so the guards say the three things that are actually
checkable: no Step writes to a shell rc (Reachability is centralised), no Step reaches a home
through a bare `~` (one spelling, and the tilde is the pre-Owner one), and a Step that pipes a
downloaded installer into a shell runs something as the Owner. All three were proven by
reintroducing the bug each forbids.

The third needs an escape hatch, because one installer here genuinely is root's: `install_ollama`
puts a binary in `/usr/local/bin`, creates a system user and a systemd unit, and touches no home at
all. It says so in its own body — `# owner: none`, with the reason — which the guard honours. An
exception a Step has to write down is one somebody had to think about.

The behavioural seam is one resolution function, which tests override with the established
`script_copy` + `override` idiom, plus a stubbed `runuser` witnessed with `witness_tool`. That
proves the *call*, not the privilege drop: the suite is un-privileged and cannot execute `runuser`
at all. Only a real root run closes that gap.

**No test has ever observed any of this.** `sandbox()` points `HOME` at a temp directory and the
suite runs un-`sudo`ed, so all 240 tests pass on a script that installs into the wrong home. That is
the gap the seam above closes, and it is why the guard is not optional.

## Considered and rejected

**Avoid home directories entirely** — everything into `/usr/local/bin` and `/etc/profile.d`, no
identity needed, nothing to get wrong. Six Tools make it impossible: nvm wants `$HOME/.nvm`, rustup
`$HOME/.cargo`, bun `$HOME/.bun`, uv `$HOME/.local/bin`, opencode `$HOME/.opencode`, and `go install`
`$HOME/go/bin`. The concept is needed whatever the mechanism; what this idea did contribute is the
boundary rule — system-wide wherever the destination is ours to choose, which is already what makes
`golangci-lint` (`-b /usr/local/bin`) and `fzf` correct.

**Redirect `HOME` and `chown -R` back afterwards.** Requires enumerating every path each vendor
touched. `bun` writes to whichever rc file it finds writable, so that set is not knowable in
advance — the same fact that ruled out centralising the writes.

**Refuse to run when there is no `SUDO_USER`.** Honest, and it breaks the root-container and CI
cases, which are ordinary uses of a machine provisioner rather than mistakes.

**Fix it silently, with no announcement of the Owner or of the reinstall.** Cheapest, and it
reproduces the original sin in a new place: a person watching a screen that reports success while
something else is true.
