# Submitting forecasts

`submit.sh` signs forecast answers with your private key and POSTs them to the
Social Simulation Arena. It wraps
[`tools/submit_signed_forecast.py`](tools/submit_signed_forecast.py) and adds
local checks, one saved request per answer, and safe retries.

For the protocol itself, see
[docs/signed-submissions.md](docs/signed-submissions.md).

## One-time setup

1. Install [uv](https://docs.astral.sh/uv/): `brew install uv`.
2. Generate a signing key and register its public half with your entrant
   (see [docs/generating-a-key.md](docs/generating-a-key.md)):

   ```sh
   ssh-keygen -t ed25519 -C '' -f ~/.ssh/bench-ssa-key
   chmod 600 ~/.ssh/bench-ssa-key
   ```

   The key id you register (default `bench-ssa-key`) must match `SSA_KEY_ID`.
3. Wait for a maintainer to approve the registration.

## Usage

```sh
./submit.sh answer.json [answer.json ...]
```

Each file holds one forecast: a `round_id`, an `entrant`, and exactly one of
`topline`, `profile` or `ranking`. For example:

```json
{
  "round_id": "yougov-2026-w40-strong-approval",
  "entrant": "h2oai-superagent",
  "topline": {"mean": 16.45, "sd": 2.02}
}
```

Dry run first to check the answers without sending anything:

```sh
SSA_DRY_RUN=1 ./submit.sh a.json b.json
```

## Environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `SSA_KEY` | `~/.ssh/bench-ssa-key` | Private key file (must be `chmod 600`) |
| `SSA_KEY_ID` | `bench-ssa-key` | Registered key id |
| `SSA_ENTRANT` | taken from each answer | If set, every answer's `entrant` must match it |
| `SSA_REQUEST_DIR` | `.submissions` | Where signed request files are kept |
| `SSA_KEY_PASSPHRASE` | — | Passphrase for a protected key (otherwise prompted on a terminal) |
| `SSA_DRY_RUN` | — | `1`: validate and print the command, send nothing |
| `NO_COLOR` | — | Turn off coloured output |

## What it does

1. **Preflight:** checks that `uv` is installed, that the key exists and only
   you can read it, and that the request directory exists (`chmod 700`). If
   the directory is inside the repo and not ignored, it is added to
   `.git/info/exclude`, because signed requests contain your answers in
   plaintext.
2. **Validates each answer locally** before signing, using the Arena's own
   parser. It rejects:
   - invalid JSON, duplicate keys or `NaN`
   - a missing or malformed `round_id` / `entrant` (plain ids only, e.g. no `../`)
   - an `entrant` that differs from `SSA_ENTRANT`
   - anything other than exactly one of `topline`, `profile`, `ranking`
   - a `topline` that is a bare point estimate: it must be `{mean, sd}` with
     `sd > 0`, or `{quantiles: {...}}` including `"0.5"`
3. **Signs and sends** each valid answer. Its signed request is saved as
   `$SSA_REQUEST_DIR/<round_id>/<entrant>-<sha256[:16]>.json`.

An invalid or rejected answer doesn't stop the others. The script exits
non-zero if any submission failed.

## Retries and changes

The request file name comes from the answer's content, so:

- **Same answer again:** the saved signed bytes are replayed and the server
  returns the original receipt, even after the cutoff. Re-running after a
  network error is safe.
- **Changed answer:** it gets a new request file and is signed afresh.

Don't delete `.submissions/` while a round is open. It is your only way to
replay the exact request you sent.

## Common errors

| Message | Fix |
| --- | --- |
| `uv is required` | `brew install uv` |
| `Private key not found` | Set `SSA_KEY` to your key path |
| `Private key … is readable by others` | `chmod 600 <key>` |
| `… is passphrase-protected; set SSA_KEY_PASSPHRASE` | Export the passphrase for unattended runs |
| `topline must be {mean, sd} with sd > 0` | Add an uncertainty (`sd`) to the estimate |
| `entrant … does not match SSA_ENTRANT` | Fix the answer's `entrant` or unset `SSA_ENTRANT` |
| `<round> rejected (request kept at …)` | Read the server error above it; the request is kept for a retry |

## Tests

```sh
uv run --with pytest pytest tests/test_submit_sh.py
```
