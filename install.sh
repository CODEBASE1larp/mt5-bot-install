#!/bin/bash
# Keep all side effects behind the final invocation for curl | bash.
main() (
    set -euo pipefail
    umask 077
    fail() { echo "mt5-bot: $*" >&2; exit 1; }
    [[ $(uname -s) == Darwin ]] || fail "Installation requires macOS."
    destination=${MT5BOT_HOME_DIR:-"$HOME/mt5-bot"}
    repo=${MT5BOT_REPO:-CODEBASE1larp/mt5-bot}
    [[ "$destination" == /* && "$destination" != */ && "$destination" != */. && "$destination" != */.. ]] ||
        fail "MT5BOT_HOME_DIR must be an absolute installation path."
    parent=$(dirname "$destination")
    bin="$HOME/.mt5-bot/bin"
    export GH_CONFIG_DIR="$HOME/.mt5-bot/gh" GH_HOST=github.com GH_PROMPT_DISABLED=1
    mkdir -p "$bin" "$GH_CONFIG_DIR" "$parent"
    lock="$HOME/.mt5-bot/bootstrap.lock"
    mkdir "$lock" 2>/dev/null || fail "Another installation holds $lock. If it was interrupted, inspect it before retrying."
    tmp=''
    release=''
    previous=''
    swapped=0
    backup=0
    committed=0
    # rename(2) replaces the link itself, including when it points at a directory.
    rename_link() { /usr/bin/perl -e 'rename($ARGV[0], $ARGV[1]) or die "rename: $!"' "$1" "$2"; }
    cleanup() {
        rc=$?
        trap - EXIT
        if (( swapped && ! committed )); then
            if (( backup )); then
                rename_link "$destination.prev" "$destination" || exit 1
            else
                rm -f "$destination"
            fi
        elif (( backup && ! swapped )); then
            rm -f "$destination.prev"
        fi
        if [[ -n "$release" ]] && (( ! committed )); then rm -R "$release"; fi
        if [[ -n "$tmp" ]]; then rm -R "$tmp"; fi
        rm -f "$lock/gh" "$lock/bootstrap"
        rmdir "$lock"
        exit "$rc"
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    tmp=$(mktemp -d "$parent/.mt5bot-download.XXXXXX")
    if [[ -L "$destination" ]]; then
        previous=$(readlink "$destination")
        [[ "$previous" == "$parent"/.mt5bot-release.* && "${previous##*/}" == "${previous#"$parent"/}" &&
           ! -L "$previous" && -f "$previous/.mt5bot-install-path" &&
           $(cat "$previous/.mt5bot-install-path") == "$destination" ]] || fail "Unmanaged installation at $destination."
    elif [[ -e "$destination" ]]; then
        fail "Move the existing directory $destination aside before installing a release."
    fi
    [[ ! -e "$destination.prev" && ! -L "$destination.prev" ]] || fail "Inspect existing backup $destination.prev before installing."

    gh="$bin/gh"
    if [[ ! -x "$gh" ]]; then
        base=https://github.com/cli/cli/releases
        latest=$(curl --proto '=https' -fsSLI -o /dev/null -w '%{url_effective}' "$base/latest")
        version=${latest##*/v}
        [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Unrecognized GitHub CLI release."
        case $(uname -m) in
            arm64) arch=arm64 ;;
            x86_64) arch=amd64 ;;
            *) fail "Unsupported macOS architecture." ;;
        esac
        name="gh_${version}_macOS_${arch}.zip"
        url="$base/download/v$version"
        curl --proto '=https' -fsSL "$url/gh_${version}_checksums.txt" -o "$tmp/checksums"
        universal="gh_${version}_macOS_universal.zip"
        if awk -v name="$universal" '$2 == name {found=1} END {exit !found}' "$tmp/checksums"; then
            name="$universal"
        fi
        curl --proto '=https' -fsSL "$url/$name" -o "$tmp/$name"
        expected=$(awk -v name="$name" '$2 == name {print $1}' "$tmp/checksums")
        [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || fail "Missing or ambiguous GitHub CLI checksum."
        (cd "$tmp" && printf '%s  %s\n' "$expected" "$name" | shasum -a 256 -c -)
        unzip -p "$tmp/$name" '*/bin/gh' > "$lock/gh"
        chmod 700 "$lock/gh"
        mv "$lock/gh" "$gh"
    fi
    # gh probes the shared macOS Keychain even with its own config directory.
    # Its optional git credential-helper probe can also trigger Apple's CLT prompt.
    github() {
        sandbox-exec -p '(version 1)(allow default)(deny process-exec (literal "/usr/bin/security") (literal "/usr/bin/git") (literal "/usr/bin/xcrun"))' "$gh" "$@"
    }
    if ! github auth status --hostname github.com >/dev/null 2>&1; then
        [[ -z ${GH_TOKEN:-} ]] || fail "GH_TOKEN could not authenticate to GitHub."
        echo "Open the GitHub link and enter the device code shown below. Sign in with the invited account."
        github auth login --hostname github.com --web --git-protocol https --insecure-storage </dev/null
    fi
    tag=${MT5BOT_VERSION:-}
    if [[ -z "$tag" ]]; then tag=$(github release view --repo "$repo" --json tagName --jq .tagName); fi
    [[ -n "$tag" && "$tag" != -* && "$tag" != *$'\n'* ]] || fail "Invalid release tag."
    github release download "$tag" --repo "$repo" --archive=tar.gz --output "$tmp/release.tar.gz"
    release=$(mktemp -d "$parent/.mt5bot-release.XXXXXX")
    tar -xzf "$tmp/release.tar.gz" -C "$release" --strip-components 1
    [[ -x "$release/install.sh" && -f "$release/bootstrap/install.sh" ]] || fail "Release lacks the installer."
    printf '%s\n' "$tag" > "$release/VERSION"
    printf '%s\n' "$destination" > "$release/.mt5bot-install-path"
    cp "$release/bootstrap/install.sh" "$lock/bootstrap"
    chmod 700 "$lock/bootstrap"
    if [[ -n "$previous" ]]; then
        ln -s "$previous" "$destination.prev"
        backup=1
    fi
    ln -s "$release" "$tmp/current"
    rename_link "$tmp/current" "$destination"
    swapped=1
    # launchd and the shim must use the stable path, including across releases.
    (unset GH_TOKEN GITHUB_TOKEN; MT5BOT_HOME_DIR="$destination" MT5BOT_REPO="$repo" "$destination/install.sh")
    mv "$lock/bootstrap" "$bin/mt5bot-bootstrap"
    committed=1
    if (( backup )); then
        if ! cmp -s "$previous/ea/MT5Bridge.mq5" "$release/ea/MT5Bridge.mq5"; then
            echo "MT5Bridge changed. Remove the EA from the chart and attach it again."
        fi
        rm -f "$destination.prev"
        rm -R "$previous"
    fi
    echo "Installed mt5-bot $tag at $destination."
)
main "$@"
