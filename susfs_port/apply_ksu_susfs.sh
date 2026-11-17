#!/usr/bin/env bash
# Applied from repository root (GITHUB_WORKSPACE).
set -u
ws="$(pwd)"
ksu="$ws/kernel/KernelSU"
p10="$ws/10_ksu_filtered.patch"
adapt="$ws/patches/susfs_port/nova_susfs_adapt.patch"
sel="$ws/patches/susfs_port/nova_susfs_selinux.patch"
hide="$ws/patches/susfs_port/nova_susfs_hide_shim.patch"

echo "p10 bytes: $(stat -c%s "$p10" 2>/dev/null || echo missing)"
echo "adapt bytes: $(stat -c%s "$adapt" 2>/dev/null || echo missing)"
echo "selinux bytes: $(stat -c%s "$sel" 2>/dev/null || echo missing)"
echo "hide bytes: $(stat -c%s "$hide" 2>/dev/null || echo missing)"

cd "$ksu" || { echo "::error::cannot cd $ksu"; exit 1; }

patch -p1 --forward -F3 < "$p10" > /tmp/p10.log 2>&1
rc10=$?
patch -p1 --forward < "$adapt" > /tmp/adapt.log 2>&1
rcadapt=$?
patch -p1 --forward < "$sel" > /tmp/sel.log 2>&1
rcsel=$?
patch -p1 --forward < "$hide" > /tmp/hide.log 2>&1
rchide=$?
rejs=$(find . -name "*.rej" | head -5 | tr '\n' '|')
echo "rc10=$rc10 rcadapt=$rcadapt rcsel=$rcsel rchide=$rchide rejs=$rejs"
echo "--- p10.log tail ---"; tail -5 /tmp/p10.log
echo "--- adapt.log tail ---"; tail -5 /tmp/adapt.log
echo "--- selinux.log tail ---"; tail -5 /tmp/sel.log
echo "--- hide.log tail ---"; tail -5 /tmp/hide.log

if [ "$rc10" -ne 0 ] || [ "$rcadapt" -ne 0 ] || [ "$rcsel" -ne 0 ] || [ "$rchide" -ne 0 ] || [ -n "$rejs" ]; then
  echo "::error::rc10=$rc10 rcadapt=$rcadapt rcsel=$rcsel rchide=$rchide rejs=$rejs seltail=$(tail -2 /tmp/sel.log | tr '\n' '|') hidetail=$(tail -2 /tmp/hide.log | tr '\n' '|') adapttail=$(tail -2 /tmp/adapt.log | tr '\n' '|')"
  exit 1
fi

WS_ROOT="$ws" python3 - <<'PYEOF'
import os
import sys
ws = os.environ['WS_ROOT']

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

p = os.path.join(ws, 'kernel/security/selinux/selinuxfs.c')
s = open(p).read()
if '#include <linux/jump_label.h>' not in s:
    a = '#include <linux/security.h>\n'
    if a not in s:
        sys.exit('security.h include anchor missing in selinuxfs.c')
    s = s.replace(a, a + '#include <linux/jump_label.h>\n#include <linux/cred.h>\n', 1)
    open(p, 'w').write(s)
    print('selinuxfs.c includes added')
PYEOF

grep -q "susfs_reboot.o" kernel/Kbuild || { echo "::error::kernel/Kbuild has no susfs_reboot.o"; exit 1; }
grep -q "linux/susfs_def.h" kernel/hook/setuid_hook.c || { echo "::error::setuid_hook.c has no susfs_def include"; exit 1; }
grep -q "extern void ksu_susfs_reboot_cmd" kernel/supercall/supercall.c || { echo "::error::supercall.c has no reboot_cmd decl"; exit 1; }
grep -q "u32 susfs_ksu_sid" kernel/selinux/selinux.c || { echo "::error::selinux.c has no susfs sids"; exit 1; }
grep -q "susfs_is_current_ksu_domain" kernel/selinux/selinux.c || { echo "::error::selinux.c has no susfs domain fn"; exit 1; }
grep -q "^bool ksu_selinux_hide_enabled" kernel/feature/selinux_hide.c || { echo "::error::selinux_hide.c enabled not exported"; exit 1; }
grep -q "^bool ksu_selinux_hide_running" kernel/feature/selinux_hide.c || { echo "::error::selinux_hide.c running not exported"; exit 1; }
grep -q "struct page \*fake_status" kernel/feature/selinux_hide.c || { echo "::error::selinux_hide.c fake_status not exported"; exit 1; }
grep -q "^void initialize_fake_status" kernel/feature/selinux_hide.c || { echo "::error::selinux_hide.c initialize_fake_status not exported"; exit 1; }
ksec="$ws/kernel/security/selinux"
grep -q "susfs_selinux_inode_setxattr" "$ksec/hooks.c" || { echo "::error::hooks.c has no susfs setxattr handler"; exit 1; }
grep -q "handle_selinux_setprocattr" "$ksec/hooks.c" || { echo "::error::hooks.c has no susfs setprocattr handler"; exit 1; }
grep -q "fake_status" "$ksec/selinuxfs.c" || { echo "::error::selinuxfs.c has no fake_status usage"; exit 1; }
grep -q "linux/jump_label.h" "$ksec/selinuxfs.c" || { echo "::error::selinuxfs.c missing jump_label include"; exit 1; }
grep -q "susfs_is_current_ksu_domain" "$ksec/status.c" || { echo "::error::status.c has no susfs domain check"; exit 1; }
echo APPLY_OK
