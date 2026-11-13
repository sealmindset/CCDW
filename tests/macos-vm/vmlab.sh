#!/bin/bash
#
# vmlab.sh — build the macOS test VM for claude_corp_bootstrap.sh from scratch.
#
# Nothing is restored from a saved VM image: every `up` installs macOS from
# Apple's restore image (cached; it is the macOS download, not our VM) and
# configures the guest by script. Human steps are batched into ONE sitting at
# the start; everything after that is automatic.
#
#   vmlab.sh up [--zscaler]   create + boot, one guided human sitting, then
#                             configure everything (and the Zscaler stand-in)
#   vmlab.sh configure        re-apply the automated guest configuration
#   vmlab.sh test [--real]    copy the installer in and run it (test mode by
#                             default; --real = VPN, sign-in, gateway checks)
#   vmlab.sh zscaler on|off|status   Zscaler stand-in (TLS inspection)
#   vmlab.sh cisco PKG        install a Cisco Secure Client .pkg you downloaded
#   vmlab.sh relay [PORT]     remote desktop to the VM over Tailscale (VNC)
#   vmlab.sh ssh [CMD]        shell / command in the guest
#   vmlab.sh status
#   vmlab.sh destroy          delete the VM (asks first)
#
# Settings (environment): VMLAB_VM (default work), VMLAB_USER (default tester),
# TERMINAL_MAC_HOME (default /Volumes/PRO-BLADE/terminal-mac).
# The VM password is asked once and kept in your login keychain
# (service "ccdw-vmlab"), never in a file.
#
# LESSONS LEARNED (each one cost time on 2026-11-12; the code below handles it)
#  - Every terminal-mac command must use the same TERMINAL_MAC_HOME, or the
#    VM "does not exist". This script always sets it.
#  - The macOS download can drop mid-way; re-running resumes it.
#  - The first boot right after install can fail with "Failed to lock auxiliary
#    storage" (installer still releasing files). Starting again works.
#  - macOS Setup Assistant cannot be scripted: it is the one unavoidable human
#    step. Do NOT turn on FileVault there — it disables automatic login.
#  - The guest helper only runs after login, so automatic login is essential.
#    `sysadminctl -autologin set` fails (error 22) on macOS 26; writing
#    /etc/kcpassword ourselves works (format checked against macOS's own).
#  - The guest display sleeps after 10 min; macOS then reports the session
#    locked and screenshots fail ("No guest display"). Display sleep, sleep,
#    screen saver and screen lock are turned off.
#  - The guest's IP changes on every boot: it is looked up each time.
#  - Typing whole strings into the guest (terminal-mac `type`) is unreliable;
#    single key presses are reliable. So everything goes over SSH, and keys
#    are used only to fill password dialogs.
#  - Trusting a root certificate needs an on-screen authorization even as
#    root. The dialog is raised in the GUI session (launchctl asuser) and
#    filled with key presses.
#  - RealVNC (iPad) cannot do Apple's account sign-in: it needs the VNC
#    password ("VNC viewers may control screen with password"). In RealVNC a
#    port needs TWO colons: 100.x.y.z::5901.
#  - Zscaler stand-in: mitmproxy local mode, its root trusted in the System
#    keychain like an MDM-installed Zscaler root, Claude/Anthropic/OpenAI not
#    inspected. Installed from mitmproxy's own tarball, NOT Homebrew — Homebrew
#    in the guest would hide the installer's own Homebrew install. It breaks
#    plain-HTTP downloads from the host, so files are copied with scp.
#  - macOS has no `timeout`: perl alarm is used.
#  - On a fresh Mac /usr/bin/python3 is only a stub that pops up "install
#    Command Line Tools?". Never use it in the guest (perl is built in).
#    Learnt the hard way: it passed on a VM that already had the tools.
#  - The guest helper reads its Accessibility permission only at launch;
#    switched on later it still reports false until restarted (done here).
#  - Running the installer over SSH skips two GUI-only behaviours: the
#    "Terminal wants Downloads" privacy prompt, and the browser sign-in
#    (claude-login uses a device code over SSH — enter it on any device).
# ============================================================================
set -euo pipefail

VM="${VMLAB_VM:-work}"
VM_USER="${VMLAB_USER:-tester}"
export TERMINAL_MAC_HOME="${TERMINAL_MAC_HOME:-/Volumes/PRO-BLADE/terminal-mac}"
TM="$(command -v terminal-mac 2>/dev/null || echo "$HOME/.local/bin/terminal-mac")"
STATE="$TERMINAL_MAC_HOME/vmlab/$VM"
KEY="$STATE/id_ed25519"
ASKPASS="$STATE/askpass"
KC_SVC="ccdw-vmlab"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALLER="$REPO/claude_corp_bootstrap.sh"
MITM_VER="12.3.1"
MITM_URL="https://downloads.mitmproxy.org/${MITM_VER}/mitmproxy-${MITM_VER}-macos-arm64.tar.gz"
MITM_SHA="9b7f7a8e3fd1b1544089c937c579ef1f0f503f0ea598c25bda9eab077c735b93"
MITM_DIR="/Users/Shared/vmlab/mitmproxy"
# The corporate Zscaler whitelist: these are passed through, not inspected.
MITM_IGNORE='^(.+\.)?(claude\.ai|claude\.com|anthropic\.com|openai\.com|chatgpt\.com)(:443)?$'
# ServerAlive: a guest that restarts or sleeps must not leave ssh hanging forever.
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=3)

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31mERR\033[0m %s\n' "$*" >&2; exit 1; }

# --- password: asked once, kept in the login keychain ------------------------
PW=""
load_pw() {
  [[ -n "$PW" ]] && return 0
  PW="$(security find-generic-password -s "$KC_SVC" -a "$VM:$VM_USER" -w 2>/dev/null || true)"
  [[ -n "$PW" ]] && return 0
  local a b
  read -r -s -p "Choose the VM password for user '$VM_USER' (used in Setup Assistant): " a; echo
  read -r -s -p "Again: " b; echo
  [[ -n "$a" && "$a" == "$b" ]] || die "Passwords empty or different."
  PW="$a"
  security add-generic-password -U -s "$KC_SVC" -a "$VM:$VM_USER" -w "$PW"
  ok "Saved in your login keychain (service $KC_SVC, account $VM:$VM_USER)."
}

write_askpass() {
  mkdir -p "$STATE"
  printf '#!/bin/sh\nprintf "%%s\\n" "$VMLAB_PW"\n' > "$ASKPASS"; chmod 700 "$ASKPASS"
}

# --- guest access --------------------------------------------------------------
guest_ip() {   # the guest's current address (changes every boot), answering on port 22
  local ip
  for ip in $(arp -an | sed -nE 's/.*\((192\.168\.64\.[0-9]+)\) at ([0-9a-f]{1,2}:){5}.*/\1/p' | grep -v '\.1$' | sort -u -t. -k4,4nr); do
    nc -z -G 1 "$ip" 22 >/dev/null 2>&1 && { echo "$ip"; return 0; }
  done
  return 1
}

gssh() {   # gssh [ssh args…] CMD — key auth once configured, password before
  local ip; ip="$(guest_ip)" || die "The guest is not answering on SSH (Remote Login off, or VM not running)."
  # </dev/null: the probe must not swallow stdin meant for the real command (sudo's password).
  if [[ -f "$KEY" ]] && ssh -i "$KEY" -o BatchMode=yes "${SSH_OPTS[@]}" "$VM_USER@$ip" true </dev/null 2>/dev/null; then
    ssh -i "$KEY" "${SSH_OPTS[@]}" "$VM_USER@$ip" "$@"
  else
    load_pw; [[ -x "$ASKPASS" ]] || write_askpass
    VMLAB_PW="$PW" SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
      ssh -o PubkeyAuthentication=no "${SSH_OPTS[@]}" "$VM_USER@$ip" "$@"
  fi
}

groot() {   # groot 'shell command' — run as root in the guest; the password goes on stdin
  load_pw
  printf '%s\n' "$PW" | gssh "sudo -S -p '' /bin/sh -c $(printf '%q' "$1")"
}

gcopy() {   # gcopy LOCAL REMOTE
  local ip; ip="$(guest_ip)" || die "Guest not reachable."
  scp -q -i "$KEY" "${SSH_OPTS[@]}" "$1" "$VM_USER@$ip:$2"
}

BOOT_BEFORE=""
rebooted() { local b; b="$(gssh 'sysctl -n kern.boottime' </dev/null 2>/dev/null)" && [[ -n "$b" && "$b" != "$BOOT_BEFORE" ]]; }

helper_ready() {   # guest helper running with both permissions
  local s; s="$("$TM" action "$VM" status 2>/dev/null)" || return 1
  grep -q '"accessibility" : "true"' <<<"$s" && grep -q '"screenRecording" : "true"' <<<"$s"
}

# The helper reads its Accessibility permission only when it starts: switched on
# afterwards, it still reports false. Restart it (at most once a minute) when
# that is the only thing missing.
LAST_KICK=-999
helper_ready_or_kick() {
  helper_ready && return 0
  local s; s="$("$TM" action "$VM" status 2>/dev/null)" || return 1
  grep -q '"accessibility" : "false"' <<<"$s" && grep -q '"screenRecording" : "true"' <<<"$s" || return 1
  (( SECONDS - LAST_KICK >= 60 )) && guest_ip >/dev/null || return 1
  LAST_KICK=$SECONDS
  gssh 'pkill -f "TerminalMacGuest.app/Contents/MacOS/terminal-mac"; sleep 2; open ~/Applications/TerminalMacGuest.app' </dev/null >/dev/null 2>&1 || true
  sleep 5; helper_ready
}

logged_in() { gssh 'who | grep -q " console "' </dev/null; }

keyname() {   # one character -> a terminal-mac key name (US layout)
  case "$1" in
    [a-z0-9]) echo "$1" ;;  [A-Z]) echo "shift+$(printf '%s' "$1" | tr 'A-Z' 'a-z')" ;;
    '!') echo shift+1 ;; '@') echo shift+2 ;; '#') echo shift+3 ;; '$') echo shift+4 ;;
    '%') echo shift+5 ;; '^') echo shift+6 ;; '&') echo shift+7 ;; '*') echo shift+8 ;;
    '(') echo shift+9 ;; ')') echo shift+0 ;; '-') echo - ;; '_') echo shift+- ;;
    '=') echo '=' ;; '+') echo 'shift+=' ;; '.') echo . ;; ',') echo , ;; '/') echo / ;;
    ';') echo ';' ;; ':') echo 'shift+;' ;; ' ') echo space ;; *) return 1 ;;
  esac
}

type_password_into_dialog() {   # macOS password dialogs sit at the same spot on a 1280x800 guest
  load_pw
  "$TM" action "$VM" click 639 371 >/dev/null
  local i k
  for ((i = 0; i < ${#PW}; i++)); do
    k="$(keyname "${PW:$i:1}")" || die "Can't type the password's character #$((i+1)) as a key press; use letters, digits and !@#\$%^&*()-_=+.,/;: only."
    "$TM" action "$VM" key "$k" >/dev/null
  done
  "$TM" action "$VM" key return >/dev/null
}

wait_for() {   # wait_for SECONDS "what" CMD… — real seconds (a check itself can take seconds)
  local secs="$1" what="$2" start=$SECONDS next=60; shift 2
  until "$@" >/dev/null 2>&1; do
    (( SECONDS - start >= secs )) && return 1
    if (( SECONDS - start >= next )); then
      echo "    still waiting for ${what}… ($((SECONDS - start))s)"; next=$((next + 60))
    fi
    sleep 5
  done
}

# --- up --------------------------------------------------------------------------
cmd_up() {
  local zscaler="no"; [[ "${1:-}" == "--zscaler" ]] && zscaler="yes"
  [[ -x "$TM" ]] || die "terminal-mac not found. Install: curl -fsSL https://github.com/govijr/terminal-mac/releases/latest/download/get.sh | bash"
  [[ -f "$INSTALLER" ]] || die "Installer not found at $INSTALLER"
  write_askpass
  load_pw

  if ! "$TM" status "$VM" >/dev/null 2>&1; then
    local free_gb; free_gb=$(( $(df -Pk "$TERMINAL_MAC_HOME" | awk 'NR==2{print $4}') / 1048576 ))
    (( free_gb >= 90 )) || warn "Only ${free_gb} GB free on $TERMINAL_MAC_HOME (the image is ~19 GB, the VM disk grows to 64 GB)."
    say "Installing macOS into VM '$VM' (downloads ~19 GB the first time; resumes if it drops)…"
    local n
    for n in 1 2 3; do
      "$TM" up "$VM" --detach && break
      "$TM" status "$VM" >/dev/null 2>&1 && break   # installed; only the first boot failed
      warn "Attempt $n failed; retrying (the download resumes)."
    done
    "$TM" status "$VM" >/dev/null 2>&1 || die "macOS did not install."
  fi
  if ! "$TM" status "$VM" 2>/dev/null | grep -q running; then
    "$TM" start "$VM" --window >/dev/null 2>&1 || { sleep 10; "$TM" start "$VM" --window >/dev/null; }
  fi
  "$TM" show "$VM" >/dev/null 2>&1 || true
  ok "VM '$VM' is running; its window is open on this Mac."

  if guest_ip >/dev/null; then
    ok "SSH already on — skipping the human steps."
  else
    cat <<EOF

  ==============================================================================
   ONE-TIME HUMAN STEPS (about 5 minutes) — in the VM window on this Mac
  ==============================================================================
   1. Setup Assistant. Create the account exactly:
        Full name / account name:  $VM_USER
        Password:                  the one you just entered
      Skip the Apple Account, Siri, Screen Time and analytics.
      Do NOT turn on FileVault (it blocks automatic login).
   2. Finder > My Shared Files > tools > open TerminalMacGuest.
      Turn on Screen Recording and Accessibility for it (password when asked).
   3. System Settings > General > Sharing > turn on Remote Login.

   This script waits and continues by itself.
  ==============================================================================

EOF
    wait_for 3600 "Remote Login (step 3)" guest_ip || die "Gave up waiting for Remote Login."
    ok "SSH is on ($(guest_ip))."
  fi

  cmd_configure
  say "Restarting the guest to prove it comes back unattended…"
  BOOT_BEFORE="$(gssh 'sysctl -n kern.boottime' </dev/null)"
  groot '(sleep 2; shutdown -r now) >/dev/null 2>&1 &' >/dev/null 2>&1 || true   # detached: ssh returns first
  # Pass only on a NEW boot: a fast check could otherwise see the old session.
  wait_for 600 "the guest to restart" rebooted || die "The guest did not restart."
  wait_for 600 "automatic login after restart" logged_in || die "No automatic login after restart (FileVault on?)."
  ok "Restarted and logged in automatically."
  if ! wait_for 120 "the guest helper" helper_ready_or_kick; then
    warn "The guest helper is missing a permission. In the VM: System Settings > Privacy & Security >"
    warn "Screen Recording and Accessibility: turn on TerminalMacGuest (step 2). Waiting…"
    wait_for 3600 "the guest helper (step 2)" helper_ready_or_kick || die "Gave up waiting for the guest helper."
  fi
  ok "Guest helper ready (screenshots and input work)."

  if [[ "$zscaler" == "yes" ]]; then cmd_zscaler on; fi
  cat <<EOF

  Done. VM '$VM' is a fresh Mac (no Command Line Tools, Homebrew or Claude Code),
  ready for:   $0 test        (test mode)
               $0 test --real (needs the VPN in the guest; see 'cisco')
EOF
}

# --- configure (idempotent) ---------------------------------------------------------
cmd_configure() {
  write_askpass
  load_pw
  say "Configuring the guest (no further input needed)…"

  [[ -f "$KEY" ]] || ssh-keygen -q -t ed25519 -N "" -C "vmlab-$VM" -f "$KEY"
  gssh 'umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; k="$(cat)"; grep -qxF "$k" ~/.ssh/authorized_keys || printf "%s\n" "$k" >> ~/.ssh/authorized_keys' < "$KEY.pub"
  ok "SSH key installed (no more passwords for plain SSH)."

  # Automatic login: kcpassword = password + NUL, XOR'd with Apple's key, padded to 12.
  # perl, not python3: on a fresh Mac /usr/bin/python3 is a stub that only pops
  # up "install Command Line Tools?" (and would spoil the fresh-Mac test).
  printf '%s' "$PW" | gssh 'umask 077; cat > /tmp/.vmlab-pw'
  gssh 'umask 077; cat > /tmp/.vmlab-kc.pl' <<'PL'
my $p = do { local $/; open my $f, '<', '/tmp/.vmlab-pw' or die "pw: $!"; binmode $f; <$f> };
my @k = (0x7D, 0x89, 0x52, 0x23, 0xD2, 0xBC, 0xDD, 0xEA, 0xA3, 0xB9, 0x1F);
my $d = $p . "\0"; $d .= "\0" x ((12 - length($d) % 12) % 12);
my $o = join '', map { chr(ord(substr($d, $_, 1)) ^ $k[$_ % 11]) } 0 .. length($d) - 1;
open my $w, '>', '/etc/kcpassword' or die "kcpassword: $!"; binmode $w; print $w $o; close $w;
chmod 0600, '/etc/kcpassword' or die "chmod: $!";
PL
  groot "/usr/bin/perl /tmp/.vmlab-kc.pl; rc=\$?; rm -f /tmp/.vmlab-pw /tmp/.vmlab-kc.pl; [ \$rc -eq 0 ] && defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser $VM_USER" \
    || die "Could not set up automatic login."
  groot "test -s /etc/kcpassword && [ \"\$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser)\" = $VM_USER ]" \
    || die "Automatic login is not configured (kcpassword or autoLoginUser missing)."
  ok "Automatic login as $VM_USER (verified)."

  groot "pmset -a displaysleep 0 sleep 0 disksleep 0 >/dev/null; sysadminctl -screenLock off -password $(printf '%q' "$PW") >/dev/null 2>&1 || true"
  gssh 'defaults -currentHost write com.apple.screensaver idleTime -int 0'
  ok "Display sleep, sleep, screen saver and screen lock off."

  local vncpw
  vncpw="$(security find-generic-password -s "$KC_SVC" -a "$VM:vnc" -w 2>/dev/null || true)"
  if [[ -z "$vncpw" ]]; then
    vncpw="$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 8 || true)"
    security add-generic-password -U -s "$KC_SVC" -a "$VM:vnc" -w "$vncpw"
  fi
  groot "launchctl enable system/com.apple.screensharing; launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null; \
/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -configure -clientopts -setvnclegacy -vnclegacy yes -setvncpw -vncpw $vncpw >/dev/null"
  local ip; ip="$(guest_ip)"
  if nc -z -G 3 "$ip" 5900 >/dev/null 2>&1; then
    ok "Screen Sharing on. VNC password: $vncpw (also in your keychain: $KC_SVC / $VM:vnc)."
  else
    warn "Screen Sharing did not start; turn it on in the guest: System Settings > General > Sharing."
  fi
}

# --- Zscaler stand-in -----------------------------------------------------------------
zscaler_running() { gssh 'pgrep -f "mitmdump --mode local" >/dev/null'; }
# Trusted = the root is IN the System keychain AND verifies. verify-cert alone is
# not enough: macOS keeps the trust setting after the certificate is deleted.
root_trusted() { gssh 'security find-certificate -c mitmproxy /Library/Keychains/System.keychain >/dev/null 2>&1 && security verify-cert -c ~/.mitmproxy/mitmproxy-ca-cert.pem >/dev/null 2>&1'; }
zscaler_intercepting() { gssh '/usr/bin/curl -sv -o /dev/null --max-time 10 https://github.com 2>&1 | grep -q "issuer: CN=mitmproxy"'; }

cmd_zscaler() {
  case "${1:-status}" in
    on)
      say "Zscaler stand-in: TLS inspection on (Claude/Anthropic/OpenAI passed through)…"
      gssh "set -e; if [ ! -x '$MITM_DIR/mitmproxy.app/Contents/MacOS/mitmdump' ]; then
              mkdir -p '$MITM_DIR'; cd '$MITM_DIR'
              /usr/bin/curl -fsSL '$MITM_URL' -o m.tgz
              echo '$MITM_SHA  m.tgz' | shasum -a 256 -c - >/dev/null
              tar -xzf m.tgz && rm -f m.tgz
            fi
            [ -f ~/.mitmproxy/mitmproxy-ca-cert.pem ] || { ('$MITM_DIR/mitmproxy.app/Contents/MacOS/mitmdump' --listen-port 18999 >/dev/null 2>&1 &); sleep 6; pkill -f 'mitmdump --listen-port 18999' || true; }"
      if ! root_trusted; then
        # Trust needs an on-screen authorization: raise it in the GUI session, then fill it.
        load_pw
        printf '%s\n' "$PW" | gssh 'P="$(cat)"; (printf "%s\n" "$P" | sudo -S -p "" launchctl asuser $(id -u) security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/.mitmproxy/mitmproxy-ca-cert.pem >/tmp/.vmlab-trust 2>&1 &) ; sleep 4'
        type_password_into_dialog; sleep 3
        root_trusted || die "The stand-in's root is not trusted. In the guest run: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/.mitmproxy/mitmproxy-ca-cert.pem"
      fi
      ok "Stand-in root trusted in the System keychain (like an MDM-installed Zscaler root)."
      zscaler_running || gssh "PYTHONUNBUFFERED=1 nohup '$MITM_DIR/mitmproxy.app/Contents/MacOS/mitmdump' --mode local --flow-detail 1 --ignore-hosts '$MITM_IGNORE' >~/vmlab-mitm.log 2>&1 </dev/null & sleep 6"
      if ! wait_for 30 "interception" zscaler_intercepting; then
        cat <<EOF

  ONE-TIME APPROVAL in the VM (first run only):
    System Settings > General > Login Items & Extensions > Network Extensions (i):
    turn on "Mitmproxy Redirector" (password), then click Allow for its proxy
    configuration. This script waits.
EOF
        wait_for 900 "the network-extension approval" zscaler_intercepting || die "Interception did not start."
      fi
      ok "Intercepting: github.com is now signed by the stand-in. Log: ~/vmlab-mitm.log in the guest." ;;
    off)
      gssh 'pkill -f "mitmdump --mode local" || true'; ok "Zscaler stand-in off (root stays trusted, as on a real Mac)." ;;
    status)
      if zscaler_running && zscaler_intercepting; then echo "on (intercepting)"; else echo "off"; fi ;;
    *) die "zscaler on|off|status" ;;
  esac
}

# --- Cisco Secure Client ----------------------------------------------------------------
cmd_cisco() {
  local pkg="${1:-}"; [[ -f "$pkg" ]] || die "Usage: $0 cisco /path/to/cisco-secure-client-macos-….pkg (download it from the VPN portal; installing it accepts Cisco's license)."
  gcopy "$pkg" /tmp/cisco.pkg
  groot 'installer -pkg /tmp/cisco.pkg -target / >/dev/null && rm -f /tmp/cisco.pkg'
  ok "Cisco Secure Client installed."
  cat <<EOF

  In the VM (needs you — your credentials and MFA):
    1. System Settings > General > Login Items & Extensions > Network Extensions (i):
       turn on "Cisco Secure Client - Socket Filter" (VM password), click Allow.
    2. Open Cisco Secure Client, connect to the VPN, sign in.
  Then: $0 test --real
EOF
}

# --- test -----------------------------------------------------------------------------------
cmd_test() {
  local real="no"; [[ "${1:-}" == "--real" ]] && real="yes"
  [[ -f "$KEY" ]] || die "Run '$0 up' first."
  load_pw
  gssh 'mkdir -p ~/Downloads'
  gcopy "$INSTALLER" "Downloads/claude_corp_bootstrap.sh"
  ok "Installer copied ($(shasum -a 256 "$INSTALLER" | cut -c1-12)…)."
  local envs=""; [[ "$real" == "yes" ]] || envs="SKIP_CORP_CHECKS=1"
  if [[ "$real" == "yes" ]]; then
    say "Running it in the guest (REAL: VPN, sign-in, gateway)…"
    echo "    The Microsoft sign-in shows a code (SSH has no browser): enter it at microsoft.com/devicelogin on any device."
  else
    say "Running it in the guest (test mode)…"
  fi
  local ip; ip="$(guest_ip)"
  # expect answers only the Mac-password prompt; everything else is passed through.
  VMLAB_PW="$PW" expect -f - "$KEY" "$VM_USER@$ip" "$envs" <<'EXP'
set timeout -1
lassign $argv key target envs
spawn ssh -tt -i $key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR $target "$envs bash ~/Downloads/claude_corp_bootstrap.sh; echo VMLAB-EXIT=\$?"
set rc 1
expect {
  "Mac password for" { send -- "$env(VMLAB_PW)\r"; exp_continue }
  -re {VMLAB-EXIT=([0-9]+)} { set rc $expect_out(1,string) }
  eof {}
}
exit $rc
EXP
}

# --- relay: VNC over Tailscale -------------------------------------------------------------
cmd_relay() {
  local port="${1:-5901}" tip
  tip="$(tailscale ip -4 2>/dev/null || /usr/local/bin/tailscale ip -4 2>/dev/null || true)"
  tip="${tip%%$'\n'*}"; [[ -n "$tip" ]] || die "Tailscale is not running on this Mac."
  local vncpw; vncpw="$(security find-generic-password -s "$KC_SVC" -a "$VM:vnc" -w 2>/dev/null || echo '(run configure)')"
  say "VNC to VM '$VM': ${tip}:${port}  (RealVNC: ${tip}::${port})  VNC password: $vncpw"
  say "Tailscale devices only. Ctrl-C to stop."
  exec /usr/bin/python3 - "$tip" "$port" <<'PY'
import re, socket, subprocess, sys, threading, time
listen_ip, listen_port = sys.argv[1], int(sys.argv[2])
def guest():   # the guest's address changes every boot: look it up per connection
    arp = subprocess.run(["arp", "-an"], capture_output=True, text=True).stdout
    for ip in sorted(set(re.findall(r"\((192\.168\.64\.\d+)\) at [0-9a-f:]{11,}", arp)), key=lambda s: -int(s.rsplit(".", 1)[1])):
        if ip.endswith(".1"): continue
        try: socket.create_connection((ip, 5900), timeout=1).close(); return ip
        except OSError: pass
def pump(a, b):
    try:
        while d := a.recv(65536): b.sendall(d)
    except OSError: pass
    finally:
        try: b.shutdown(socket.SHUT_WR)   # half-close: the other direction keeps flowing
        except OSError: pass
def handle(c):
    ip = guest()
    if not ip: c.close(); print("no guest on :5900", flush=True); return
    u = socket.create_connection((ip, 5900), timeout=5); u.settimeout(None)
    print(time.strftime("%H:%M:%S"), c.getpeername()[0], "->", ip, flush=True)
    threading.Thread(target=pump, args=(c, u), daemon=True).start(); pump(u, c)
s = socket.create_server((listen_ip, listen_port))
while True:
    c, _ = s.accept(); threading.Thread(target=handle, args=(c,), daemon=True).start()
PY
}

cmd_status() {
  "$TM" status "$VM" 2>/dev/null | tr -d '\n ' ; echo
  local ip; ip="$(guest_ip || true)"
  echo "guest IP: ${ip:-not reachable}"
  if helper_ready; then echo "helper: ready"; else echo "helper: not ready (logged out or permissions missing)"; fi
  if [[ -n "$ip" ]]; then echo "zscaler stand-in: $(cmd_zscaler status 2>/dev/null || echo unknown)"; fi
}

cmd_destroy() {
  "$TM" status "$VM" >/dev/null 2>&1 || die "No VM '$VM'."
  local a; read -r -p "Delete VM '$VM' and its disk for good? Type its name to confirm: " a
  [[ "$a" == "$VM" ]] || die "Not confirmed; nothing deleted."
  "$TM" stop "$VM" --force >/dev/null 2>&1 || true
  sleep 3
  rm -rf "${TERMINAL_MAC_HOME:?}/machines/${VM:?}" "${STATE:?}"
  security delete-generic-password -s "$KC_SVC" -a "$VM:$VM_USER" >/dev/null 2>&1 || true
  security delete-generic-password -s "$KC_SVC" -a "$VM:vnc" >/dev/null 2>&1 || true
  ok "VM '$VM' deleted (the cached macOS download is kept in $TERMINAL_MAC_HOME/cache)."
}

case "${1:-}" in
  up)        shift; cmd_up "$@" ;;
  configure) cmd_configure ;;
  test)      shift; cmd_test "$@" ;;
  zscaler)   shift; cmd_zscaler "$@" ;;
  cisco)     shift; cmd_cisco "$@" ;;
  relay)     shift; cmd_relay "$@" ;;
  ssh)       shift; if (( $# )); then gssh "$@"; else gssh -t; fi ;;
  status)    cmd_status ;;
  destroy)   cmd_destroy ;;
  *) sed -n '3,22p' "$0"; exit 1 ;;
esac
