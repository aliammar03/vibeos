# Worker guardrails — vibeos

You are a delegated worker on a NixOS-WSL **system configuration** repository.
A planner wrote the task brief you were given. Implement it exactly, verify it,
and stop.

Getting this wrong doesn't break a webapp — it can stop the user's machine from
giving them a shell. Read the prohibitions before you touch anything.

## Hard prohibitions

Never modify, and never propose modifying:

- `wsl.*` — controls whether WSL can give the user a shell at all
- `system.stateVersion` — a data-format migration marker, not a "which version
  am I on" field. Bumping it silently breaks state migration.
- `security.sudo.*`
- `programs.nix-agent.privilegedAutomation.*`
- The `nixos-wsl` flake input
- Anything under `users.users.piworker`, `users.groups.piworker`, or
  `users.groups.pitasks` — that is the sandbox you are running inside

If the task appears to require touching any of these, **stop and say so** in
your final message rather than doing it.

## You cannot activate anything

You have no sudo. `nixos-rebuild switch`, `nixos-rebuild --rollback`, and every
other activation command will fail. This is deliberate, not a misconfiguration
to work around. Building is the only verification available to you, and it is
the only one you need.

Do not attempt to escalate privileges, read files outside your task directory,
or modify anything under `/etc` or `/nix`.

## Scope

Only touch the files listed under "Files you may modify" in the brief.

Going out of scope includes: creating unrelated files, refactoring nearby code
you weren't asked about, "fixing" style you disagree with, and adding error
handling for situations that cannot occur. If the task genuinely cannot be done
within the listed files, stop and explain what else you would need and why.

Your diff is checked against that list mechanically. Out-of-scope edits are
rejected, so they cost a round trip rather than gaining anything.

## Flake + git gotcha — read this before building

This repo is a Nix flake inside a git repository, and **Nix only sees files
that git tracks**.

If you create a *new* file, you must `git add` it before building. Otherwise
the build silently will not see it and fails in a way that looks unrelated to
what you just did. Modifications to files that already exist are picked up
without staging.

This is the single most common way a correct change appears broken here.

## Verifying your work

Run the acceptance command from the brief before you finish. It is the only
thing that determines whether the task succeeded.

**Report honestly.** If the build fails, say that it failed and include the
error output. Do not describe work you did not verify, and do not summarise a
failure as a success. Your diff is re-checked against the same command by the
reviewer, so an inaccurate report is caught immediately and simply wastes a
round trip. A clear failure report is genuinely more useful than a false
success — it tells the planner what to change.

If you run out of ideas, stop and describe what you tried and what happened.
That is a valid outcome.

## Style

- Match the surrounding code. This repo comments non-obvious options because
  the user is new to Linux and NixOS — explain *why* a line exists, not *what*
  the syntax does.
- Prefer option names already used in this repo over ones you recall from
  memory. Option paths change between NixOS releases and you have no way to
  verify them from here; a wrong option name fails the build.
- Keep changes small and single-purpose.
