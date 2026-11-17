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

p = 'kernel/hook/setuid_hook.c'
s = open(p).read()
if '#include <linux/susfs_def.h>' not in s:
    a = '#include <linux/uidgid.h>\n'
    if a not in s:
        sys.exit('uidgid include anchor missing in setuid_hook.c')
    s = s.replace(a, a + '#ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs_def.h>\n#endif\n', 1)
    open(p, 'w').write(s)
    print('setuid_hook.c include patched')

p = 'kernel/supercall/susfs_reboot.c'
s = open(p).read()
if '#include <linux/cred.h>' not in s:
    s = s.replace('#include <linux/types.h>\n',
                  '#include <linux/types.h>\n#include <linux/cred.h>\n#include <linux/printk.h>\n', 1)
    open(p, 'w').write(s)
    print('susfs_reboot.c includes patched')

p = 'kernel/supercall/supercall.c'
s = open(p).read()
if 'extern void ksu_susfs_reboot_cmd' not in s:
    a = '#include <linux/susfs_def.h>\n'
    if a not in s:
        sys.exit('susfs_def include missing in supercall.c')
    s = s.replace(a, a + '\n#ifdef CONFIG_KSU_SUSFS\nextern void ksu_susfs_reboot_cmd(unsigned int cmd, void __user *arg);\n#endif\n', 1)
    open(p, 'w').write(s)
    print('supercall.c extern decl added')
PYEOF

grep -q "susfs_reboot.o" kernel/Kbuild || { echo "::error::kernel/Kbuild has no susfs_reboot.o"; exit 1; }
grep -q "linux/susfs_def.h" kernel/hook/setuid_hook.c || { echo "::error::setuid_hook.c has no susfs_def include"; exit 1; }
grep -q "extern void ksu_susfs_reboot_cmd" kernel/supercall/supercall.c || { echo "::error::supercall.c has no reboot_cmd decl"; exit 1; }
grep -q "u32 susfs_ksu_sid" kernel/selinux/selinux.c || { echo "::error::selinux.c has no susfs sids"; exit 1; }
grep -q "susfs_is_current_ksu_domain" kernel/selinux/selinux.c || { echo "::error::selinux.c has no susfs domain fn"; exit 1; }
echo APPLY_OK
