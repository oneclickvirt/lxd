---
name: oneclickvirt-lxd
description: "Operate and troubleshoot lxd instances deployed with the OneClickVirt scripts."
metadata:
  repository: oneclickvirt/lxd
  integration-version: "1.0.0"
---

# lxd

## Scope

Operate and troubleshoot lxd instances deployed with the OneClickVirt scripts.

- Read the platform precheck and installation pages before changing a host.
- Use the existing host runtime and its credentials. Instance IDs and names remain the native runtime identifiers.
- MCP starts read-only. Set ONECLICKVIRT_MCP_ALLOW_WRITE=1 on the intended host to expose start, graceful stop and restart; deletion, reinstall and arbitrary shell commands are not exposed.
- Use the lxc client for LXD. Do not substitute the incus daemon.

## Install and update

```bash
curl -fL --retry 3 https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/install_agent.py -o install_agent.py
python3 install_agent.py --client codex
```

The installer is also mirrored at `https://cnb.cool/oneclickvirt/lxd/-/git/raw/main/scripts/install_agent.py`; add `--source cnb` to install from an immutable CNB snapshot (requires Git).

Use `--client claude` or `--client openclaw` for another client. Download and run again to update; `--ref` pins a source tag/commit. The installer verifies all SHA-256 checksums before replacing its files, preserves extra local files/client settings, and records the source commit in `install.json`.

## MCP

Requires Python 3.9+. The adapter uses existing local commands and their existing permissions; it does not install a virtualization runtime. Merge the generated `mcp.codex.toml`, `mcp.claude.json`, or `mcp.openclaw.json` into that client's existing configuration. For a remote host, run its adapter over noninteractive SSH.

Call `integration_info` first for capabilities and prerequisites.

## Source and documentation

- [`panel_scripts/modify.sh`](https://github.com/oneclickvirt/lxd/blob/main/panel_scripts/modify.sh)
- [`panel_scripts/panel_init.sh`](https://github.com/oneclickvirt/lxd/blob/main/panel_scripts/panel_init.sh)
- [`scripts/add-ipv6.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/add-ipv6.sh)
- [`scripts/add_more.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/add_more.sh)
- [`scripts/backend.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/backend.sh)
- [`scripts/build_ipv6_network.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/build_ipv6_network.sh)
- [`scripts/build_monitor.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/build_monitor.sh)
- [`scripts/buildct.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/buildct.sh)
- [`scripts/buildvm.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/buildvm.sh)
- [`scripts/check-dns.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/check-dns.sh)
- [`scripts/config.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/config.sh)
- [`scripts/init.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/init.sh)
- [`scripts/instance_ownership.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/instance_ownership.sh)
- [`scripts/least.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/least.sh)
- [`scripts/lxdinstall.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/lxdinstall.sh)
- [`scripts/lxduninstall.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/lxduninstall.sh)
- [`scripts/monitor.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/monitor.sh)
- [`scripts/pre_check.sh`](https://github.com/oneclickvirt/lxd/blob/main/scripts/pre_check.sh)

- [集成安装说明 / Integration guide](https://www.spiritlhl.net/guide/agent_integrations.html)
- [平台准备与安装 / Platform prerequisites](https://www.spiritlhl.net/guide/lxd/lxd_precheck.html)

Check the relevant source and current documentation before giving commands. Preserve requested version pins, data paths and native host identifiers. Distinguish actual program execution, isolated tests and unverified environments.
