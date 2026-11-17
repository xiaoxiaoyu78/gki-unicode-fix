#!/usr/bin/env python3
import re

KERNEL_EXCLUDES = {
    'fs/exec.c', 'fs/open.c', 'fs/stat.c', 'fs/read_write.c',
    'kernel/sys.c', 'kernel/reboot.c',
    'security/selinux/status.c', 'drivers/input/input.c',
    'security/selinux/selinuxfs.c', 'security/selinux/hooks.c',
}

# Only the SUSFS Kconfig menu is taken from the upstream KSU patch; all other
# KSU-side integration is hand-written in nova_susfs_adapt.patch because the
# upstream file versions do not match SukiSU Nova v3.0.0.
KSU_INCLUDE = {'kernel/Kconfig'}

def filter_patch(src_path, out_path, excludes, include_only=None):
    src = open(src_path).read()
    kept = []
    for part in re.split(r'(?m)^diff --git ', src)[1:]:
        head = 'diff --git ' + part
        m = re.match(r'diff --git a/(.*?) b/(.*?)\n', head)
        if not m:
            continue
        name = m.group(2)
        if include_only is not None:
            if name not in include_only:
                continue
        elif name in excludes:
            continue
        kept.append(head)
    open(out_path, 'w').write(''.join(kept))
    print('%s -> %s (%d files kept)' % (src_path, out_path, len(kept)))

filter_patch('susfs4ksu/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch',
             '50_kernel_filtered.patch', KERNEL_EXCLUDES)
filter_patch('susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch',
             '10_ksu_filtered.patch', set(), KSU_INCLUDE)
