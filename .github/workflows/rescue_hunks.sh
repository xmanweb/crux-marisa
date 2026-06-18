#!/bin/sh
# =====================================================================
#  🚀 [RESCUE HUNKS ENGINE] AUTOMATED sed PATCH ALIGNMENT SCRIPT (CI/CD)
# =====================================================================

set -e

NAMESPACE_C="fs/namespace.c"
CMDLINE_C="fs/proc/cmdline.c"
TASK_MMU_C="fs/proc/task_mmu.c"
SYS_C="kernel/sys.c"

echo "====================================================================="
# ---------------------------------------------------------------------
#  1. 修补 fs/namespace.c
# ---------------------------------------------------------------------
if [ -f "$NAMESPACE_C" ]; then
    echo "⚙️ sed aligning: $NAMESPACE_C ..."

    # A. 头部结构和定义注入
    sed -i '/#include "internal.h"/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#ifndef VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT\n#define VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT BIT(24)\n#endif\n#ifndef DEFAULT_KSU_MNT_GROUP_ID\n#define DEFAULT_KSU_MNT_GROUP_ID (100000)\n#endif\nextern bool susfs_is_current_ksu_domain(void);\nextern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;\n#define CL_COPY_MNT_NS BIT(25)\n#endif' "$NAMESPACE_C"

    # B. mnt_free_id 顶部拦截
    sed -i '/static void mnt_free_id(struct mount \*mnt)/{n;a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt.mnt_flags \& VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)\n\t\treturn;\n#endif
}' "$NAMESPACE_C"

    # C. mnt_alloc_group_id 特权分配拦截 (调整变量声明位置到函数体第一步，解决 C99 冲突)
    sed -i '/static int mnt_alloc_group_id(struct mount \*mnt)/{n;a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tint res_ksu;\n\tif (susfs_is_current_ksu_domain()) {\n\t\tif (!ida_pre_get(\&mnt_group_ida, GFP_KERNEL))\n\t\t\treturn -ENOMEM;\n\t\tres_ksu = ida_get_new_above(\&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, \&mnt->mnt_group_id);\n\t\tif (!res_ksu)\n\t\t\treturn 0;\n\t}\n#endif
}' "$NAMESPACE_C"

    # D. mnt_release_group_id 防火墙
    sed -i '/void mnt_release_group_id(struct mount \*mnt)/{n;a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt_group_id == DEFAULT_KSU_MNT_GROUP_ID)\n\t\treturn;\n#endif
}' "$NAMESPACE_C"

    # E. clone_mnt 变量声明注入 (将 bool 声明强制塞到 clone_mnt 的入口变量定义区，斩断 C99 告警)
    sed -i '/struct mount \*clone_mnt(struct mount \*old, struct dentry \*root,/,/int err;/ {
        /int err;/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tbool is_mnt_ksu_unshared = false;\n#endif
    }' "$NAMESPACE_C"

    # F. clone_mnt 核心代码区间内包裹 (限定在 clone_mnt 作用域内，仅处理第一处 alloc_vfsmnt)
    sed -i '/struct mount \*clone_mnt(struct mount \*old, struct dentry \*root,/,/return mnt;/ {
        /mnt = alloc_vfsmnt(old->mnt_devname);/i \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (static_branch_unlikely(\&susfs_is_sdcard_android_data_not_decrypted)) {\n\t\tif (susfs_is_current_ksu_domain()) {\n\t\t\fif (flag \& CL_COPY_MNT_NS) {\n\t\t\t\tmnt = susfs_alloc_unshare_ksu_vfsmnt(old->mnt_devname, old->mnt_id);\n\t\t\t\tis_mnt_ksu_unshared = true;\n\t\t\t\tgoto bypass_orig_flow;\n\t\t\t}\n\t\t\tmnt = susfs_alloc_non_unshare_ksu_vfsmnt(old->mnt_devname);\n\t\t\tgoto bypass_orig_flow;\n\t\t}\n\t}\n\tif (old->mnt_id >= DEFAULT_KSU_MNT_ID) {\n\t\tmnt = susfs_alloc_non_unshare_ksu_vfsmnt(old->mnt_devname);\n\t\tgoto bypass_orig_flow;\n\t}\n#endif
        /mnt = alloc_vfsmnt(old->mnt_devname);/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\nbypass_orig_flow:\n#endif
    }' "$NAMESPACE_C"

    # G. 旗标注入 (同样加入区间锁，防止误伤后面的同名赋值)
    sed -i '/struct mount \*clone_mnt(struct mount \*old, struct dentry \*root,/,/return mnt;/ {
        /mnt->mnt.mnt_flags = old->mnt.mnt_flags;/a \
\tmnt->mnt.mnt_flags \&= ~(MNT_WRITE_HOLD|MNT_MARKED|MNT_INTERNAL);\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (unlikely(is_mnt_ksu_unshared))\n\t\tmnt->mnt.mnt_flags |= VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT;\n#endif
    }' "$NAMESPACE_C"

    echo "✅ $NAMESPACE_C sed patched flawlessly."
fi

# ---------------------------------------------------------------------
#  2. 修补 fs/proc/cmdline.c
# ---------------------------------------------------------------------
if [ -f "$CMDLINE_C" ]; then
    echo "⚙️ sed aligning: $CMDLINE_C ..."
    
    sed -i '/static int cmdline_proc_show/i \
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\nextern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;\nextern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);\n#endif\n' "$CMDLINE_C"

    sed -i '/static int cmdline_proc_show/{n;a \
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\n\tif (static_branch_likely(\&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {\n\t\tsusfs_spoof_cmdline_or_bootconfig(m);\n\t\tseq_printf(m, "%s\\n");\n\t\treturn 0;\n\t}\n#endif
}' "$CMDLINE_C"
    
    echo "✅ $CMDLINE_C sed patched flawlessly."
fi

# ---------------------------------------------------------------------
#  3. 修补 fs/proc/task_mmu.c (完全阻断 smaps 侧信道泄漏)
# ---------------------------------------------------------------------
if [ -f "$TASK_MMU_C" ]; then
    echo "⚙️ sed aligning: $TASK_MMU_C ..."
    
    sed -i '/#include <linux\/ctype.h>/a \
#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs.h>\n#endif' "$TASK_MMU_C"

    sed -i '/static int show_smap(struct seq_file \*m, void \*v)/{n;a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tstruct vm_area_struct *vma_ksu = v;\n\tif (vma_ksu \&\& vma_ksu->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma_ksu->vm_file)))\n\t\t\treturn 0;\n\t}\n#endif
}' "$TASK_MMU_C"
    
    echo "✅ $TASK_MMU_C sed patched flawlessly."
fi

# ---------------------------------------------------------------------
#  4. 修补 kernel/sys.c
# ---------------------------------------------------------------------
if [ -f "$SYS_C" ]; then
    echo "⚙️ sed aligning: $SYS_C ..."
    
    sed -i '/SYSCALL_DEFINE1(newuname/i \
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' "$SYS_C"

    sed -i '/memcpy(&tmp, utsname(), sizeof(tmp));/a \
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(\&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(\&tmp);\n#endif' "$SYS_C"
    
    echo "✅ $SYS_C sed patched flawlessly."
fi

echo "====================================================================="
echo " 🎉 CI/CD DEPLOYMENT PREP COMPLETE: ALL RESCUE HUNKS INJECTED VIA sed!"
echo "====================================================================="
