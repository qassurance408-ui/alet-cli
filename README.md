# acc

A terminal app for managing AletCloud. You arrow through menus instead of
remembering commands or reading JSON.

```
  alet — Virtual Machines
  Choose a machine
  ──────────────────────────────────────────────────────────────

  ▶  alet-website-admin     ● RUNNING      Pro      41.x.x.x
      nested-virtualization  ● STOPPED      Ras      41.x.x.x
      gonder                 ● STOPPED      Ultra    —
      lalibela               ● STOPPED      Max      —
      ＋  New virtual machine
      ← Back

  ↑/↓  navigate   enter  select   q  back
```

(Status colours and the dot are green for running and amber for stopped. IPs
are masked here.)

Python 3.10 or newer, standard library only. No pip install, no dependencies,
one file.

## What it does

AletCloud exposes its control plane through an MCP endpoint at
`mcp.aletcloud.com/mcp`. That endpoint speaks JSON-RPC over HTTPS and answers
with server-sent events. It is a good machine interface and a miserable human
one. `acc` sits on top of it and turns it into screens.

Nothing about the protocol reaches the surface. You never see a tool name, a
request id, or a JSON payload. You see a list of your machines, you pick one,
and you get the actions that make sense for it right now.

Nine sections:

| Section | What is in it |
|---|---|
| Virtual Machines | list, detail, start, stop, reboot, resize, rebuild, delete, add a public IP, console access |
| App Hosting | deployed apps, env vars, custom domains, deploy, restart, stop, delete |
| Managed Databases | instances, connection credentials, start, stop, restart, delete |
| Object Storage | buckets, per-bucket and account-wide access keys, resize, delete |
| Domains & DNS | your domains, nameservers, DNS records, availability search, pricing |
| Hosting Projects | projects that group apps, and the apps inside them |
| VPN Access | on/off, enrolled devices, add and remove a device |
| Billing & Usage | wallet balance, this month's usage by resource, transaction history |
| Platform Status | component health, incidents, scheduled maintenance, 90 day uptime |

## Install on Linux

```bash
curl -fsSL https://raw.githubusercontent.com/qassurance408-ui/alet-cli/main/install.sh | sh
```

It checks that you have Python 3.10 or newer, downloads `acc`, verifies its
SHA256 against the published checksum, and puts it in `~/.local/bin`. Run it
again any time to upgrade.

If `~/.local/bin` is not already on your PATH, it adds the line to your shell
rc (`~/.bashrc`, `~/.zshrc`, or `~/.profile` depending on your shell) so new
terminals find `acc` without you doing anything. It only ever appends once, and
`ACC_NO_MODIFY_PATH=1` turns that off. The shell you ran the installer from is
a parent process, so nothing can change its PATH from the inside; the installer
prints the one line to paste if you want `acc` in that shell right away.

You can change what it does with environment variables:

```bash
ACC_VERSION=v0.5 \
ACC_INSTALL_DIR=/usr/local/bin \
ACC_NO_MODIFY_PATH=1 \
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/qassurance408-ui/alet-cli/main/install.sh)"
```

| Variable | Default | What it does |
|---|---|---|
| `ACC_VERSION` | `main` | tag or branch to install |
| `ACC_INSTALL_DIR` | `~/.local/bin` | where the file goes |
| `ACC_NO_MODIFY_PATH` | unset | set to `1` to leave your shell rc alone |

If you would rather not pipe a script into a shell, read it first or just copy
the file yourself:

```bash
install -m 755 acc ~/.local/bin/acc
```

Either way, if your shell was already open before you installed, run `rehash`
(zsh) or `hash -r` (bash), otherwise it keeps using the old cached path.

To uninstall, `rm ~/.local/bin/acc`.

## Install on Windows

Windows has no execute bit, so you need a small `.cmd` launcher and a PATH
entry. Use PowerShell, not Command Prompt. cmd does not understand `$HOME` or
`-Force` and will make folders with those literal names.

```powershell
python --version                     # needs 3.10+
git clone https://github.com/qassurance408-ui/alet-cli.git $HOME\alet-cli
New-Item -ItemType Directory -Force $HOME\bin | Out-Null

@'
@py -3 "%USERPROFILE%\alet-cli\acc" %*
'@ | Set-Content -Encoding ascii $HOME\bin\acc.cmd

[Environment]::SetEnvironmentVariable(
  'Path', [Environment]::GetEnvironmentVariable('Path','User') + ";$HOME\bin", 'User')
```

The launcher points at the clone directly, so `git pull` is the whole update
and there is nothing to copy.

Open a new PowerShell window, since PATH changes only apply to new shells, and
run `acc version`. Use Windows Terminal if you have it. The old Command Prompt
window works but the box drawing characters look rough.

## Token

`acc` needs a personal access token. Generate one at
https://aletcloud.com/access-tokens. It looks in three places, in order:

1. the `ALET_PAT` environment variable
2. `~/.config/aletcloud/config`
3. `~/.aletcloudrc`

If none of those has one, it asks on first run and saves it for you. On Linux
the file is written with mode 0600. On Windows that step is skipped, because
there `chmod` only toggles the read only bit and would not actually restrict
anyone, so the file just inherits your profile folder's permissions.

To set it yourself:

```bash
export ALET_PAT=alet_pat_...                                              # Linux
```
```powershell
[Environment]::SetEnvironmentVariable('ALET_PAT','alet_pat_...','User')   # Windows
```

The first run prompt checks the token by actually using it. It makes a real
authenticated call and reads the answer, so a token that is well formed but
wrong gets refused at the prompt and nothing is written to disk. It also tells
a rejected token apart from an unreachable server, so a network outage does not
get blamed on your token.

## Using it

Arrow keys or `j`/`k` to move, Enter to pick, `q` or Esc to go back. In long
lists, `n` and `p` page forward and back.

Every section is a list. Pick a row and you get a detail screen plus the
actions that apply to it in its current state. A stopped machine offers Start.
A running one offers Stop and Reboot. Actions that change something ask first,
and the destructive ones say what happens before the Yes option, like "Every
file on this machine is erased."

Secrets get their own screen and a warning, because database passwords, storage
access keys, and VPN private keys are shown once and cannot be fetched again.

You can skip the menu with a shortcut:

```
acc                 interactive menu
acc vms             virtual machines
acc apps            hosted apps
acc dbs             managed databases
acc storage         buckets and access keys
acc domains         domains and DNS
acc projects        hosting projects
acc vpn             VPN access and devices
acc billing         balance, usage and transactions
acc balance         wallet balance only
acc usage           this month's usage only
acc status          platform health
acc help            list all of the above
acc version         print the version
```

`help` and `version` work with no token and no network.

## How it works

### Transport

The MCP code lives at the top of the file and nothing below it knows MCP
exists. One `initialize` handshake runs per session and the returned
`mcp-session-id` is reused for every later call. If the server expires that
session, the next call reopens it once and retries, so a long sit in a menu
does not turn into an error.

Replies come back either as plain JSON or as an SSE stream, so `_rpc` scans for
`data:` lines and falls back to parsing the whole body.

The platform reports application errors as a normal payload rather than with
the protocol's error flag, so a 404 arrives looking like data:

```json
{"error": true, "status": 404, "message": {...}}
```

`_unwrap` catches that shape and raises, which is what keeps a "not found" from
being rendered as a resource. Field validation messages get pulled out of
`message` and shown as one sentence, so a rejected password reads
`password: Password must be at least 6 characters (error 400)`.

### Screens

Screens never call the transport directly. They go through three helpers:

`load()` fetches something for display and shows the problem instead of the
data if the call fails. `act()` runs a mutation with a spinner and a plain
language result. `refreshed()` re-reads one record before opening its detail
screen, because list payloads carry every field but they age while you sit in a
menu.

One `browse()` loop and one `actions()` menu back all nine sections, which is
why they behave the same way. Adding a section means writing a fetch function
and a label function, not a new screen.

A few readers exist because the API is not always tidy. `v()` reads a field
that may be JSON null, since `dict.get(key, default)` hands back `None` when
the key is present with a null value, which is how this API says "unset". So a
machine with no public IP reads "not assigned" on its detail screen rather than
"None". `num()` coerces numbers that arrive as strings, because
`uptime_percent_90d` comes back as `"99.891"` and an `isinstance(x, float)`
check would silently drop it. `status_cell()` pads inside the colour codes
rather than outside, so the invisible escape bytes do not count toward the
column width.

### Drawing

Screens are written with plain `print()` calls, but a `_Painter` class takes the place of
`sys.stdout` and buffers them. When something blocks on input, the whole
screen goes out as a single write that homes the cursor and overwrites the
previous frame in place. There is no erase step, so there is no blank moment.
The session runs on the alternate screen buffer so your scrollback survives.

The single write is what keeps it steady on Windows. Linux terminals batch a
run of small writes into one render pass, so painting a screen line by line
looks fine there, but Windows consoles repaint on every write. Erasing first
and then printing line by line would show a blank screen filling back in on
every keypress.

### Windows differences

Three things needed platform code. `tty` and `termios` do not exist on Windows,
so `getch()` uses `msvcrt` there. Arrow keys arrive as a two byte pair instead
of an ANSI escape and get translated back into the same vocabulary, so the rest
of the code does not care which platform it is on. Virtual terminal processing
has to be switched on at startup or the colour codes print as literal text.

### Long output

Everything long is paged against the real terminal height rather than a fixed
number. The usage screen rolls about 1,500 raw billing intervals into one row
per resource, sorted by cost, with a total that stays visible while you page.
Transaction history is far too large to hold, so it pages server side, twenty
at a time.

## Things worth knowing

Status screens repeat the platform's own caveats instead of smoothing them
over. When incident history is unavailable, the screen says so rather than
reporting no incidents. Components the platform does not monitor are listed as
unknown rather than healthy.

App deploys auto-detect the framework, build command, output directory, root
directory and port. That is the default and it is one keypress. There is also a
"Set them myself" branch, because a wrong guess is otherwise uncorrectable from
the CLI. No tool on the endpoint enumerates the valid framework values and the
schema's own example disagrees with what the platform stores, so the picker
offers the values seen in use (`STATIC`, `NODEJS`, `ANGULAR`, `VITE`) plus a
free text option. An unrecognised value gets refused by the server with a clear
message and nothing is created.

Every screen recovers on its own. A failed request shows the reason and drops
you back rather than ending the session.

## Development

The whole app is one file. `acc` is the program, `install.sh` is the installer,
and `SHA256SUMS` is what the installer checks against.

If you change `acc`, regenerate the checksum before pushing or every install
will fail verification:

```bash
sha256sum acc > SHA256SUMS
```

Bump `VERSION` near the top of `acc` for a release and tag the commit. The
installer defaults to `main`, so `ACC_VERSION` is only needed to pin an older
build.

## License

MIT. See [LICENSE](LICENSE).
