#!/usr/bin/env python3
import re

KERNEL_EXCLUDES = {
    'fs/exec.c', 'fs/open.c', 'fs/stat.c', 'fs/read_write.c',
    'kernel/sys.c', 'kernel/reboot.c',
    'security/selinux/status.c', 'drivers/input/input.c',
    'security/selinux/selinuxfs.c', 'security/selinux/hooks.c',
}

KSU_EXCLUDES = {
    'kernel/Kbuild', 'kernel/Makefile', 'kernel/core/init.c',
    'kernel/hook/setuid_hook.c', 'kernel/policy/allowlist.c',
    'kernel/runtime/ksud_integration.c',
    'kernel/supercall/supercall.c', 'kernel/supercall/dispatch.c',
    'kernel/policy/app_profile.c', 'kernel/policy/app_profile.h',
}

def filter_patch(src_path, out_path, excludes):
    src = open(src_path).read()
    kept = []
    for part in re.split(r'(?m)^diff --git ', src)[1:]:
        head = 'diff --git ' + part
        m = re.match(r'diff --git a/(.*?) b/(.*?)\n', head)
        if not m:
            continue
        if m.group(2) in excludes:
            continue
        kept.append(head)
    open(out_path, 'w').write(''.join(kept))
    print('%s -> %s (%d files kept)' % (src_path, out_path, len(kept)))

filter_patch('susfs4ksu/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch',
             '50_kernel_filtered.patch', KERNEL_EXCLUDES)
filter_patch('susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch',
             '10_ksu_filtered.patch', KSU_EXCLUDES)
