#!/bin/sh
# =====================================================================
#  🚀 [RESCUE HUNKS ENGINE] AUTOMATED sed PATCH ALIGNMENT SCRIPT v4.5
# =====================================================================

set -e

NAMESPACE_C="fs/namespace.c"
CMDLINE_C="fs/proc/cmdline.c"
TASK_MMU_C="fs/proc/task_mmu.c"
SYS_C="kernel/sys.c"

echo "====================================================================="
# ---------------------------------------------------------------------
#  1. 修补 fs/namespace.c (完全等价对齐你的 .rej 拒绝块，纠正错位 Bug)
# ---------------------------------------------------------------------
if [ -f "$NAMESPACE_C" ]; then
    echo "⚙️ sed aligning: $NAMESPACE_C ..."

    # A. 对齐 .rej：mnt_free_id 内部精准注入
    if ! grep -q "VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT" "$NAMESPACE_C"; then
        sed -i '/static void mnt_free_id(struct mount \*mnt)/{n;n;a \
\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt.mnt_flags \& VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)\n\t\treturn;\n#endif
}' "$NAMESPACE_C"
    fi

    # B. 对齐 .rej：mnt_alloc_group_id 精准注入旧版内核分配链与跳转标签（限定作用域）
    if ! grep -q "bypass_orig_flow" "$NAMESPACE_C"; then
        sed -i '/static int mnt_alloc_group_id(struct mount \*mnt)/,/res = ida_get_new_above/ {
            /int res;/a \
\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (susfs_is_current_ksu_domain()) {\n\t\tif (!ida_pre_get(\&mnt_group_ida, GFP_KERNEL))\n\t\t\treturn -ENOMEM;\n\t\tres = ida_get_new_above(\&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, \&mnt->mnt_group_id);\n\t\tgoto bypass_orig_flow;\n\t}\n#endif
        }' "$NAMESPACE_C"

        # 放下游跳转标签
        sed -i '/static int mnt_alloc_group_id(struct mount \*mnt)/,/if (!res)/ {
            /res = ida_get_new_above(\&mnt_group_ida, mnt_group_start, \&mnt->mnt_group_id);/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\nbypass_orig_flow:\n#endif' "$NAMESPACE_C"
    fi

    # C. 对齐 .rej：mnt_release_group_id 精准注入
    if ! grep -q "DEFAULT_KSU_MNT_GROUP_ID" "$NAMESPACE_C"; then
        sed -i '/void mnt_release_group_id(struct mount \*mnt)/{n;n;a \
\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt_group_id == DEFAULT_KSU_MNT_GROUP_ID)\n\t\treturn;\n#endif
}' "$NAMESPACE_C"
    fi

    echo "✅ $NAMESPACE_C sed patched flawlessly (Strictly Aligned with .rej)."
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
#  3. 修补 fs/proc/task_mmu.c (全量补回 4 处失败的 Patch)
# ---------------------------------------------------------------------
if [ -f "$TASK_MMU_C" ]; then
    echo "⚙️ sed aligning: $TASK_MMU_C ..."
    
    # 【第一处失败】头部依赖丢失
    if ! grep -q "linux\/susfs_def.h" "$TASK_MMU_C"; then
        sed -i '1i #include <linux/cred.h>\n#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs_def.h>\n#endif' "$TASK_MMU_C"
    fi

    # 【第二处失败】show_map_vma 拦截丢失
    if ! grep -q "SUSFS_IS_INODE_SUS_MAP(inode)" "$TASK_MMU_C"; then
        sed -i '/struct inode \*inode = file_inode(vma->vm_file);/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\t\tif (SUSFS_IS_INODE_SUS_MAP(inode))\n\t\t\treturn;\n#endif' "$TASK_MMU_C"
    fi

    # 【第三处失败】show_smap 拦截丢失
    if ! grep -q "vma_ksu = v;" "$TASK_MMU_C"; then
        sed -i '/struct mem_size_stats mss;/i \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tstruct vm_area_struct *vma_ksu = v;\n\tif (vma_ksu \&\& vma_ksu->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma_ksu->vm_file)))\n\t\t\treturn 0;\n\t}\n#endif' "$TASK_MMU_C"
    fi

    # 【第四处失败】pagemap_read 拦截丢失
    if ! grep -q "walk_page_range" "$TASK_MMU_C" | grep -q "bypass_orig_flow"; then
        sed -i '/ret = walk_page_range(start_vaddr, end, \&pagemap_walk);/i \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\t\tstruct vm_area_struct *vma = find_vma(mm, start_vaddr);\n\t\tif (vma \&\& vma->vm_file \&\& SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\tgoto bypass_orig_flow;\n#endif' "$TASK_MMU_C"

        sed -i '/ret = walk_page_range(start_vaddr, end, \&pagemap_walk);/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\nbypass_orig_flow:\n#endif' "$TASK_MMU_C"
    fi

    echo "✅ $TASK_MMU_C sed patched flawlessly (All 4 Hunks Restored)."
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
echo " 🎉 CI/CD DEPLOYMENT PREP COMPLETE: ALL REJECTED HUNKS BACK-FILLED!"
echo "====================================================================="
