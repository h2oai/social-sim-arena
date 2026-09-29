# Updating from upstream

`update-from-upstream.sh` brings this fork's local `main` up to date with
`main` in the upstream repository
([Social-Atoms/social-sim-arena](https://github.com/Social-Atoms/social-sim-arena)).

It updates **only `main`**, and only by fast-forward. It never creates merge
commits, rebases, or touches any other branch.

## One-time setup

Add the upstream repository as a remote named `upstream`:

```sh
git remote add upstream git@github.com:Social-Atoms/social-sim-arena.git
git remote -v   # should list both origin and upstream
```

## Usage

```sh
git switch main
./update-from-upstream.sh
git push origin main   # optional: publish the update to the fork
```

The script takes no arguments.

## What it does

1. Checks that you are inside a git repository, that the `upstream` remote
   exists, and that `main` is checked out.
2. Runs `git fetch --prune upstream`.
3. Compares `main` with `upstream/main`:
   - **Nothing new upstream:** prints `Already up to date` and exits.
   - **Upstream has new commits:** lists them, then runs
     `git merge --ff-only upstream/main`.
   - **Local `main` has commits that upstream doesn't:** stops without
     changing anything (see below).

## When it refuses

| Message | Cause | Fix |
| --- | --- | --- |
| `Usage: … takes no arguments` | An argument was passed | Run it with no arguments |
| `Remote 'upstream' is not configured` | Setup not done | See [One-time setup](#one-time-setup) |
| `Detached HEAD` | No branch checked out | `git switch main` |
| `On branch '<x>'; only 'main' can be updated` | Another branch is checked out | `git switch main` |
| `'main' has N local commit(s) not in upstream/main` | Local `main` has diverged | See below |

If local `main` has diverged, move your commits to a feature branch, then
reset `main` to upstream:

```sh
git branch my-work                 # keep your commits on a branch
git reset --hard upstream/main     # discards local main commits; my-work still has them
```

Then rebase or merge `my-work` onto the updated `main` yourself.

## Output

Colours are shown only when output goes to a terminal. Set `NO_COLOR=1` to
turn them off.

## Tests

```sh
uv run --with pytest pytest tests/test_update_from_upstream_sh.py
```
