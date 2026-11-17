#!/usr/bin/env bash
# Applied from repository root (GITHUB_WORKSPACE).
set -u
ws="$(pwd)"
ksu="$ws/kernel/KernelSU"
p10="$ws/10_ksu_filtered.patch"
adapt="$ws/patches/susfs_port/nova_susfs_adapt.patch"

echo "p10 bytes: $(stat -c%s "$p10" 2>/dev/null || echo missing)"
echo "adapt bytes: $(stat -c%s "$adapt" 2>/dev/null || echo missing)"
head -c 200 "$p10" | head -3

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

grep -q "susfs_reboot.o" kernel/Kbuild || { echo "::error::kernel/Kbuild has no susfs_reboot.o"; exit 1; }
echo APPLY_OK
