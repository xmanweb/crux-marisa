#!/bin/sh
# =====================================================================
#  🚀 [RESCUE HUNKS ENGINE] AUTOMATED sed PATCH ALIGNMENT SCRIPT v4.7
# =====================================================================

set -e

NAMESPACE_C="fs/namespace.c"
CMDLINE_C="fs/proc/cmdline.c"
TASK_MMU_C="fs/proc/task_mmu.c"
SYS_C="kernel/sys.c"

echo "====================================================================="
# ---------------------------------------------------------------------
#  1. 修补 fs/namespace.c (保持等价对齐)
# ---------------------------------------------------------------------
if [ -f "$NAMESPACE_C" ]; then
    echo "⚙️ sed aligning: $NAMESPACE_C ..."

    if ! grep -q "VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT" "$NAMESPACE_C"; then
        sed -i '/static void mnt_free_id(struct mount \*mnt)/{n;n;a \
\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt.mnt_flags \& VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)\n\t\treturn;\n#endif
}' "$NAMESPACE_C"
    fi

    if ! grep -q "bypass_orig_flow" "$NAMESPACE_C"; then
        sed -i '/static int mnt_alloc_group_id(struct mount \*mnt)/,/res = ida_get_new_above/ {
            /int res;/a \
\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (susfs_is_current_ksu_domain()) {\n\t\tif (!ida_pre_get(\&mnt_group_ida, GFP_KERNEL))\n\t\t\treturn -ENOMEM;\n\t\tres = ida_get_new_above(\&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, \&mnt->mnt_group_id);\n\t\tgoto bypass_orig_flow;\n\t}\n#endif
        }' "$NAMESPACE_C"

        sed -i '/static int mnt_alloc_group_id(struct mount \*mnt)/,/if (!res)/ {
            /res = ida_get_new_above(\&mnt_group_ida, mnt_group_start, \&mnt->mnt_group_id);/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\nbypass_orig_flow:\n#endif' "$NAMESPACE_C"
    fi

    if ! grep -q "DEFAULT_KSU_MNT_GROUP_ID" "$NAMESPACE_C"; then
        sed -i '/void mnt_release_group_id(struct mount \*mnt)/{n;n;a \
\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt_group_id == DEFAULT_KSU_MNT_GROUP_ID)\n\t\treturn;\n#endif
}' "$NAMESPACE_C"
    fi

    echo "✅ $NAMESPACE_C sed patched flawlessly."
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
#  3. 修补 fs/proc/task_mmu.c (深度加固空指针与未定义指针解引用保护)
# ---------------------------------------------------------------------
if [ -f "$TASK_MMU_C" ]; then
    echo "⚙️ sed aligning: $TASK_MMU_C ..."
    
    # 头部依赖丢失修复
    if ! grep -q "linux\/susfs_def.h" "$TASK_MMU_C"; then
        sed -i '1i #include <linux/cred.h>\n#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs_def.h>\n#endif' "$TASK_MMU_C"
    fi

    # show_map_vma 拦截
    if ! grep -q "SUSFS_IS_INODE_SUS_MAP(inode)" "$TASK_MMU_C"; then
        sed -i '/struct inode \*inode = file_inode(vma->vm_file);/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\t\tif (inode \&\& SUSFS_IS_INODE_SUS_MAP(inode))\n\t\t\treturn;\n#endif' "$TASK_MMU_C"
    fi

    # show_smap & show_smaps_rollup 拦截加固
    # 彻底杜绝对匿名或半初始化映射解引用导致早期开机 Panic 
    if ! grep -q "vma_ksu = v;" "$TASK_MMU_C"; then
        # 注入 show_smap 头部
        sed -i '/static int show_smap(struct seq_file \*m, void \*v)/{n;a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tstruct vm_area_struct *vma_ksu = v;\n\tif (vma_ksu \&\& vma_ksu->vm_file \&\& file_inode(vma_ksu->vm_file)) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma_ksu->vm_file)))\n\t\t\treturn 0;\n\t}\n#endif
}' "$TASK_MMU_C"

        # 注入 show_smaps_rollup 头部
        sed -i '/static int show_smaps_rollup(struct seq_file \*m, void \*v)/{n;a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tstruct vm_area_struct *vma_ksu = v;\n\tif (vma_ksu \&\& vma_ksu->vm_file \&\& file_inode(vma_ksu->vm_file)) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma_ksu->vm_file)))\n\t\t\treturn 0;\n\t}\n#endif
}' "$TASK_MMU_C"
    fi

    # pagemap_read 拦截（严格检查，去重）
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
echo " 🎉 CI/CD DEPLOYMENT PREP COMPLETE: DEFENSIVE HARDENING DEPLOYED!"
echo "====================================================================="
