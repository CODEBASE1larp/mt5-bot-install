# mt5-bot installer

Public installer for the private **mt5-bot** project (MetaTrader 5 execution bridge for macOS).
It contains no bot code. You need a GitHub account that has been invited to the private repo.

Paste in Terminal:

```
curl -fsSL https://raw.githubusercontent.com/CODEBASE1larp/mt5-bot-install/main/install.sh | bash
```

No Homebrew, git or admin password needed. The script downloads GitHub's official `gh` tool
(checksum-verified) into `~/.mt5-bot/bin`, asks you to log in to GitHub in your browser once,
downloads the newest mt5-bot release into `~/mt5-bot`, and installs it.
