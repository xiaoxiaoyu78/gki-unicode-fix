#!/usr/bin/env bash
# Applied from repository root (GITHUB_WORKSPACE).
set -u
ws="$(pwd)"
ksu="$ws/kernel/KernelSU"
p10="$ws/10_ksu_filtered.patch"
adapt="$ws/patches/susfs_port/nova_susfs_adapt.patch"

echo "p10 bytes: $(stat -c%s "$p10" 2>/dev/null || echo missing)"
echo "adapt bytes: $(stat -c%s "$adapt" 2>/dev/null || echo missing)"

cd "$ksu" || { echo "::error::cannot cd $ksu"; exit 1; }

patch -p1 --forward -F3 < "$p10" > /tmp/p10.log 2>&1
rc10=$?
patch -p1 --forward < "$adapt" > /tmp/adapt.log 2>&1
rcadapt=$?
rejs=$(find . -name "*.rej" | head -5 | tr '\n' '|')
echo "rc10=$rc10 rcadapt=$rcadapt rejs=$rejs"
echo "--- p10.log tail ---"; tail -5 /tmp/p10.log
echo "--- adapt.log tail ---"; tail -5 /tmp/adapt.log

if [ "$rc10" -ne 0 ] || [ "$rcadapt" -ne 0 ] || [ -n "$rejs" ]; then
  echo "::error::rc10=$rc10 rcadapt=$rcadapt rejs=$rejs p10tail=$(tail -2 /tmp/p10.log | tr '\n' '|') adapttail=$(tail -2 /tmp/adapt.log | tr '\n' '|')"
  exit 1
fi

python3 - <<'PYEOF'
import sys
p='kernel/hook/setuid_hook.c'
s=open(p).read()
if '#include <linux/susfs_def.h>' not in s:
    a='#include <linux/uidgid.h>\n'
    if a not in s:
        sys.exit('uidgid include anchor missing in setuid_hook.c')
    s=s.replace(a, a+'#ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs_def.h>\n#endif\n',1)
    open(p,'w').write(s)
    print('setuid_hook.c include patched')

p='kernel/supercall/susfs_reboot.c'
s=open(p).read()
if '#include <linux/cred.h>' not in s:
    s=s.replace('#include <linux/types.h>\n','#include <linux/types.h>\n#include <linux/cred.h>\n#include <linux/printk.h>\n',1)
    open(p,'w').write(s)
    print('susfs_reboot.c includes patched')

p='kernel/supercall/supercall.c'
s=open(p).read()
if 'ksu_susfs_reboot_cmd' in s and 'extern void ksu_susfs_reboot_cmd' not in s:
    s=s.replace('#include "klog.h" // IWYU pragma: keep','extern void ksu_susfs_reboot_cmd(unsigned int cmd, void __user *arg);\n\n#include "klog.h" // IWYU pragma: keep',1)
    open(p,'w').write(s)
    print('supercall.c prototype added')

p='kernel/core/init.c'
s=open(p).read()
if 'susfs_set_batch_sid' not in s:
    s=s.replace('#ifdef CONFIG_KSU_SUSFS\n    susfs_init();','extern void susfs_set_batch_sid(void);\n\n#ifdef CONFIG_KSU_SUSFS\n    susfs_init();\n    susfs_set_batch_sid();',1)
    open(p,'w').write(s)
    print('init.c batch sid call added')

p='kernel/feature/sucompat.c'
s=open(p).read()
if 'ret = escape_to_root_for_init();' in s:
    s=s.replace('ret = escape_to_root_for_init();','escape_to_root_for_init();\n        ret = 0;',1)
    open(p,'w').write(s)
    print('sucompat.c void-return fix applied')
PYEOF

grep -q "susfs_reboot.o" kernel/Kbuild || { echo "::error::kernel/Kbuild has no susfs_reboot.o"; exit 1; }
grep -q "linux/susfs_def.h" kernel/hook/setuid_hook.c || { echo "::error::setuid_hook.c has no susfs_def include"; exit 1; }
grep -q "susfs_set_batch_sid" kernel/core/init.c || { echo "::error::init.c has no batch sid call"; exit 1; }
grep -q "extern void ksu_susfs_reboot_cmd" kernel/supercall/supercall.c || { echo "::error::supercall.c has no prototype"; exit 1; }
echo APPLY_OK
