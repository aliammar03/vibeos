# VibeOS — rules for Claude

This repo IS my NixOS system config (NixOS-WSL). You edit it, rebuild, and roll back.

## Every change, in order
1. Verify every package/option name via the `nixos` MCP server before writing it.
   Never guess an option path.
2. Explain what you're about to change and why, in plain language.
3. `git add -A && git commit -m "..."` BEFORE rebuilding.
4. Build first to catch errors without applying:
   `sudo nixos-rebuild build --flake ~/vibeos#vibeos`
5. Only if the build succeeds, apply:
   `sudo nixos-rebuild switch --flake ~/vibeos#vibeos`
6. Tell me how to verify it worked.

## If something breaks
- Roll back one generation: `sudo nixos-rebuild switch --rollback`
- Or revert the config: `git revert HEAD && sudo nixos-rebuild switch --flake ~/vibeos#vibeos`

## GitHub workflow
- Remote `origin` = github.com/aliammar03/vibeos, default branch `main`.
  (GitHub user is `aliammar03`; the Linux user is `aliammar` — don't conflate them.)
- For non-trivial changes: make a branch, commit, `git push -u origin <branch>`,
  then `gh pr create --fill`. Summarize the diff for me and let me merge.
- Small/obvious changes may go straight to `main` only if I say so.
- After a merge: `git checkout main && git pull` BEFORE rebuilding.
- Never commit secrets (tokens, passwords, private keys) into any .nix file.

## Do NOT touch without asking me explicitly first
- Anything under `wsl.*`
- `system.stateVersion`
- The `nixos-wsl` flake input / module
These control whether WSL can give me a shell. Breaking them is the one thing that hurts.

## Style
- Prefer small, single-purpose commits.
- Keep configuration.nix readable; split into modules/ only when it gets long.
- I'm new to Linux/NixOS — comment non-obvious options.
