# acc

A terminal app for AletCloud. You arrow through menus instead of remembering
commands. It talks to the platform's MCP endpoint over HTTPS and never shows
you any of that: no tool names, no JSON, no protocol.

Python 3.10 or newer, standard library only. No pip install, no dependencies.

```
acc                 interactive menu
acc vms             jump straight to a section
acc help            list every shortcut
acc version         prints 0.5
```

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
entry. Use **PowerShell**, not Command Prompt. cmd does not understand `$HOME`
or `-Force` and will make folders with those literal names.

```powershell
python --version                     # needs 3.10+
New-Item -ItemType Directory -Force $HOME\bin | Out-Null

@'
@py -3 "%USERPROFILE%\acc\acc" %*
'@ | Set-Content -Encoding ascii $HOME\bin\acc.cmd

[Environment]::SetEnvironmentVariable(
  'Path', [Environment]::GetEnvironmentVariable('Path','User') + ";$HOME\bin", 'User')
```

That assumes the repo is cloned at `C:\Users\<you>\acc`. The launcher points at
the clone directly, so `git pull` is the whole update, no copying needed.

Open a **new** PowerShell window (PATH changes only apply to new shells) and run
`acc version`. Use Windows Terminal if you have it. The old Command Prompt
window works but the box drawing characters look rough.

## Token

`acc` needs a personal access token. It looks in three places, in order:

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

## Using it

Arrow keys or `j`/`k` to move, Enter to pick, `q` or Esc to go back. In long
lists, `n` and `p` page forward and back.

Nine sections: Virtual Machines, App Hosting, Managed Databases, Object
Storage, Domains & DNS, Hosting Projects, VPN Access, Billing & Usage, and
Platform Status. Each one is a list, and picking a row opens a detail screen
with the actions that make sense for that thing right now. A stopped VM offers
Start. A running one offers Stop and Reboot.

Every action that changes something asks first. Destructive ones spell out what
happens before the Yes option, like "Every file on this machine is erased".

## How it works

**Transport.** The MCP bits live at the top of the file and nothing below them
knows about MCP. There is one `initialize` handshake per run, the session id
gets reused, and if the server expires it the next call reopens it once and
retries. Responses come back as SSE, so `_rpc` pulls the payload out of the
`data:` lines.

**Screens.** Everything goes through three helpers: `load()` to fetch and show,
`act()` to change something, and `refreshed()` to re-read one record before its
detail screen so you are not looking at a stale snapshot. One `browse()` loop
and one `actions()` menu back all nine sections, which is why they all behave
the same way.

**Drawing.** Screens are written with plain `print()` calls, but a `_Painter`
class stands in for `sys.stdout` and buffers them. When something blocks on
input, the whole screen goes out as a single write that homes the cursor and
overwrites the previous frame in place. There is no erase step, so there is no
blank moment. The session runs on the alternate screen buffer so your scrollback
survives.

The single write is what keeps it steady on Windows. Linux terminals batch a
run of small writes into one render pass, so painting a screen line by line
looks fine there, but Windows consoles repaint on every write. Erasing first
and then printing line by line would show a blank screen filling back in on
every keypress.

**Windows differences.** Only three things needed platform code: `tty` and
`termios` do not exist on Windows so `getch()` uses `msvcrt` there, arrow keys
arrive as a two byte pair instead of an ANSI escape and get translated back so
the rest of the code does not care, and virtual terminal processing has to be
switched on at startup or the colour codes print as literal text.
