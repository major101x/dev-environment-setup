# The scope is a dev machine — VPS or desktop — and a Tool installs unattended

The README opened with "a fresh VPS", and the registry has been filling with Tools that have
nothing to do with servers: a browser automation stack, Chrome, a set of agent CLIs. #57 then
proposed desktop editors, and the contradiction stopped being cosmetic — a desktop editor cannot
run on a VPS, so admitting one either widens the stated scope or breaks it.

Nothing anywhere said what may be a Tool, so the question could only be argued case by case, and
the answer would have been whatever the last argument decided.

Two decisions, taken together because neither is safe alone:

- The project is for **a fresh dev machine — VPS or desktop**.
- A Tool is admitted by one rule: **it installs unattended on Ubuntu 24.04** — no prompts, no
  terminal reads, no desktop session required *to install*. It need not be usable headlessly.

## Why the rule is about installing, not about running

The rule has to be one this script can be held to, and installing is the only thing this script
does. What a Tool needs in order to *run* is the user's business and the machine's: Chrome has
been in the registry since before any of this, and on a VPS it runs headless or not at all. Making
"usable on this machine" the bar would have thrown Chrome out to keep an editor out.

So the caveat moves to where the user reads it rather than to where the registry enforces it: a
Tool that needs a graphical session says so in its description, exactly as Chrome's already says
`(headless)`. There is deliberately **no** declared "needs a display" property. A second dimension
in the registry is a thing every future Tool has to answer for, and it should be bought by a real
complaint — a picker that groups by it, a run that refuses on it — rather than by the hypothesis
that one might one day be useful.

## The alternatives

**Keep the scope at VPS and refuse desktop Tools.** This is the honest reading of the README as it
stood, and it was rejected because the registry had already left it: Chrome, Puppeteer and its
bundled browser are not server software, and no one had objected. A stated scope that the code
has quietly outgrown does not constrain anything; it just makes the next contributor guess.

**Widen to "any machine" and admit anything installable.** Rejected as no rule at all. The point of
writing one down is that some proposals fail it, and `unattended on Ubuntu 24.04` fails real ones:
an installer that insists on a prompt, one that only ships a GUI installer, one that needs a
display *to install*.

**Require a Tool to be usable on the machine it is installed on.** Rejected for the reason above,
and because it cannot be checked. Whether a machine has a display is a runtime fact about a
machine this script may never see again — `--dry-run` on a laptop plans a run for a server.

**Split the registry, one for servers and one for desktops.** Rejected as two registries to keep in
step for one difference that a sentence of description already carries. The Category list is the
grouping the picker already has, and #57 proposes `Editors` as one more Category — not as a second
registry. No editor is in the registry yet; this ADR is what admits one.

## A browser-hosted editor will exist beside a desktop one, on purpose

No editor is in the registry as this is written — #57 proposes `vscode`, `cursor` and
`code-server`, and #62 and #63 are where they arrive. The desktop pair is what the scope was
argued over; this section is about the pair that arrives looking redundant. `vscode` and
`code-server` will read as the same Tool twice to a later reader, who is then likely to
"simplify" by deleting one.

They will not be the same Tool. Which one is useful is decided by the machine, not by taste:

- On a **desktop**, `vscode` is the editor. `code-server` there is a web server for an editor the
  machine can already display.
- On a **VPS**, `code-server` is the only one of the two usable at all: it serves the editor over
  HTTP to a browser somewhere else. `vscode` on the same machine will still install cleanly, and
  still cannot open a window.

Both pass the admission rule, because the rule is about installing. Admitting both is what makes
the widened scope mean something: the registry will serve both machines rather than serving one and
apologising to the other. Deleting `code-server` would leave a server with no editor; deleting
`vscode` would leave a desktop installing a web server to edit files locally.

VS Code's Remote-SSH is the third case and will need no Tool: it installs its own server component
on connect. That is worth saying out loud in the docs, because it is the reason a server does *not*
need `vscode` — not a reason `code-server` is redundant.

## Consequences

The README's opening line changes, and it is now the scope the registry is actually held to.

"Can we add X?" has an answer that is not an argument: install it unattended on a fresh Ubuntu
24.04, or it is not a Tool. The commonest way to fail the rule is an installer that reads the
terminal, which is its own recorded Decision (`CONTEXT.md`) and its own static assertion, because
under [ADR-0013](0013-the-install-screen-reads-the-stream.md) such an installer does not prompt —
it deadlocks behind the install screen.

Tools whose installers *can* be made to comply — with a flag, as every `apt-get install -y` here
already does, or with an environment variable — are admitted, and supplying it is the Install
Step's job. That is a real widening: the rule is "installs unattended", not "is unattended by
default".

## Guarded by

The admission rule is a rule for people, and most of it cannot be asserted — no test can prove a
Tool needs no display. The half that can be is: `test/cli.bats` fails if any Install Step body
reads the terminal, which is the rule's one mechanically checkable clause and the one that
otherwise fails silently, as a hang.
