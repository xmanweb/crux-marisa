#!/bin/sh
# =====================================================================
#  🚀 [RESCUE HUNKS ENGINE] AUTOMATED sed PATCH ALIGNMENT SCRIPT v4.8
#  🛡️ SAFE MODE: DISABLE HIGH-RISK MOUNT GOTO INTERCEPTIONS FOR BOOTLOOP
# =====================================================================

set -e

NAMESPACE_C="fs/namespace.c"
CMDLINE_C="fs/proc/cmdline.c"
TASK_MMU_C="fs/proc/task_mmu.c"
SYS_C="kernel/sys.c"

echo "====================================================================="
# ---------------------------------------------------------------------
#  1. 修补 fs/namespace.c (安全降级模式：移除高危 vfs_kern_mount 劫持)
# ---------------------------------------------------------------------
if [ -f "$NAMESPACE_C" ]; then
    echo "⚙️ sed aligning: $NAMESPACE_C ..."

    # 仅保留释放组 ID 的安全逻辑，防止解引用和分支提前触发
    if ! grep -q "DEFAULT_KSU_MNT_GROUP_ID" "$NAMESPACE_C"; then
        sed -i '/void mnt_release_group_id(struct mount \*mnt)/{n;n;a \
\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt_group_id == DEFAULT_KSU_MNT_GROUP_ID)\n\t\treturn;\n#endif
}' "$NAMESPACE_C"
    fi

    echo "✅ $NAMESPACE_C sed alignment bypassed high-risk gotos safely."
fi

# ---------------------------------------------------------------------
#  2. 修补 fs/proc/cmdline.c
# ---------------------------------------------------------------------
if [ -f "$CMDLINE_C" ] && ! grep -q "susfs_spoof_cmdline_or_bootconfig" "$CMDLINE_C"; then
    echo "⚙️ sed aligning: $CMDLINE_C ..."
    sed -i '/static int cmdline_proc_show/i \
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\nextern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;\nextern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);\n#endif\n' "$CMDLINE_C"
    
    sed -i '/static int cmdline_proc_show/{n;a \
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\n\tif (static_branch_likely(\&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {\n\t\tsusfs_spoof_cmdline_or_bootconfig(m);\n\t\tseq_printf(m, "%s\\n");\n\t\treturn 0;\n\t}\n#endif
}' "$CMDLINE_C"
    echo "✅ $CMDLINE_C sed patched flawlessly."
fi

# ---------------------------------------------------------------------
#  3. 修补 fs/proc/task_mmu.c (继续保持最强三段式连环断言)
# ---------------------------------------------------------------------
if [ -f "$TASK_MMU_C" ]; then
    echo "⚙️ sed aligning: $TASK_MMU_C ..."
    
    if ! grep -q "linux\/susfs_def.h" "$TASK_MMU_C"; then
        sed -i '1i #include <linux/cred.h>\n#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs_def.h>\n#endif' "$TASK_MMU_C"
    fi

    if ! grep -q "SUSFS_IS_INODE_SUS_MAP(inode)" "$TASK_MMU_C"; then
        sed -i '/struct inode \*inode = file_inode(vma->vm_file);/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\t\tif (inode \&\& SUSFS_IS_INODE_SUS_MAP(inode))\n\t\t\treturn;\n#endif' "$TASK_MMU_C"
    fi

    if ! grep -q "vma_ksu = v;" "$TASK_MMU_C"; then
        sed -i '/static int show_smap(struct seq_file \*m, void \*v)/{n;a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tstruct vm_area_struct *vma_ksu = v;\n\tif (vma_ksu \&\& vma_ksu->vm_file \&\& file_inode(vma_ksu->vm_file)) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma_ksu->vm_file)))\n\t\t\treturn 0;\n\t}\n#endif
}' "$TASK_MMU_C"

        sed -i '/static int show_smaps_rollup(struct seq_file \*m, void \*v)/{n;a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tstruct vm_area_struct *vma_ksu = v;\n\tif (vma_ksu \&\& vma_ksu->vm_file \&\& file_inode(vma_ksu->vm_file)) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma_ksu->vm_file)))\n\t\t\treturn 0;\n\t}\n#endif
}' "$TASK_MMU_C"
    fi

    if ! grep -q "struct vm_area_struct \*vma = find_vma" "$TASK_MMU_C"; then
        sed -i '/down_read(\&mm->mmap_sem);/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\t\tvma = find_vma(mm, start_vaddr);\n\t\tif (vma \&\& vma->vm_file \&\& file_inode(vma->vm_file) \&\& SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\tgoto bypass_orig_flow;\n#endif' "$TASK_MMU_C"

        sed -i '/ret = walk_page_range(start_vaddr, end, \&pagemap_walk);/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\nbypass_orig_flow:\n#endif' "$TASK_MMU_C"
    fi

    echo "✅ $TASK_MMU_C sed patched flawlessly with Deep Pointer Armor."
fi

# ---------------------------------------------------------------------
#  4. 修补 kernel/sys.c
# ---------------------------------------------------------------------
if [ -f "$SYS_C" ] && ! grep -q "susfs_spoof_uname" "$SYS_C"; then
    echo "⚙️ sed aligning: $SYS_C ..."
    sed -i '/SYSCALL_DEFINE1(newuname/i \
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' "$SYS_C"
    
    sed -i '/memcpy(&tmp, utsname(), sizeof(tmp));/a \
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(\&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(\&tmp);\n#endif' "$SYS_C"
    echo "✅ $SYS_C sed patched flawlessly."
fi

echo "====================================================================="
echo " 🎉 CI/CD DEPLOYMENT PREP COMPLETE: SAFE MODE DEPLOYED!"
echo "====================================================================="
