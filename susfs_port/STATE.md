SUSFS integration state (nova-susfs-689)

- 0..43ec83cf: 9 failed runs, upstream KSU patch file-by-file exclusion did not converge.
- 43ec83cf: pivot to "SUSFS Kconfig only + hand written integration", run 44070264111 failed at link with susfs_ksu_sid / susfs_priv_app_sid.
- 15227d7e: added sid globals in the apply script, but the workflow reads
  patches/susfs_port/apply_ksu_susfs.sh from the `patches` branch, so the change
  never reached CI.
- acf27844 (patches branch): apply script + filter script synced, sid globals included.
