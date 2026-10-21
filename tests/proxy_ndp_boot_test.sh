#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$ROOT_DIR" <<'PYTEST'
import os
from pathlib import Path
import subprocess
import sys
import tempfile
source=Path(sys.argv[1])
runtime=source.name
assert runtime in ['incus','lxd']
script=(source/'scripts/build_ipv6_network.sh').read_text()
start=script.index('persist_proxy_ndp_sysctl() {')
function=script[start:script.index('\n}\n',start)+2]
assert 'systemctl restart' not in function,'Repeated creation must not restart the runtime daemon'
with tempfile.TemporaryDirectory() as temporary:
    root=Path(temporary)
    (root/'etc/systemd/system').mkdir(parents=True)
    (root/'bin').mkdir()
    stubs={
        'sysctl':'exit 0',
        'networkctl':'''case "$1" in
status) echo '    Network File: /run/systemd/network/10-cloud-init.network' ;;
reload) exit 0 ;;
*) exit 1 ;;
esac''',
        'systemctl':'''case "$1" in
is-active|daemon-reload|enable) exit 0 ;;
show) echo loaded ;;
start) [ "${OCV_FAIL_START:-0}" != 1 ] ;;
*) exit 1 ;;
esac''',
    }
    for name,body in stubs.items():
        path=root/'bin'/name
        path.write_text('#!/bin/sh\nset -eu\n'+body+'\n')
        path.chmod(0o755)
    function=function.replace('/etc/',str(root)+'/etc/')
    env=dict(os.environ,PATH=str(root/'bin')+':'+os.environ['PATH'])
    result=subprocess.run(['bash','-c',function+'\npersist_proxy_ndp_sysctl eth0\n'],env=env,capture_output=True,text=True)
    assert result.returncode==0,(result.stdout,result.stderr)
    unit='oneclickvirt-'+runtime+'-ipv6-proxy-ndp.service'
    content=(root/'etc/systemd/system'/unit).read_text()
    assert 'After=network-online.target' in content
    assert 'Before=incus.service incus-daemon.service lxd.service snap.lxd.daemon.service' in content
    assert 'net.ipv6.conf.default.proxy_ndp=1' in content
    for daemon in ['snap.lxd.daemon.service','incus.service']:
        dropin=(root/'etc/systemd/system'/(daemon+'.d')/'99-oneclickvirt-ipv6-script.conf').read_text()
        assert 'Requires='+unit in dropin and 'After='+unit in dropin
    assert (root/'etc/systemd/network/10-cloud-init.network.d/99-oneclickvirt-ipv6.conf').read_text()=='[Network]\nIPv6ProxyNDP=yes\n'
    env['OCV_FAIL_START']='1'
    result=subprocess.run(['bash','-c',function+'\npersist_proxy_ndp_sysctl eth0\n'],env=env,capture_output=True,text=True)
    assert result.returncode!=0,'Readiness failure was silently ignored'
print('IPv6 networkd persistence, daemon ordering and startup failure propagation passed')
PYTEST
