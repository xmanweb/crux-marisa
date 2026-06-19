#!/bin/sh
# =====================================================================
#  🚀 [RESCUE HUNKS ENGINE] AUTOMATED sed PATCH ALIGNMENT SCRIPT v3.1
# =====================================================================

set -e

NAMESPACE_C="fs/namespace.c"
CMDLINE_C="fs/proc/cmdline.c"
TASK_MMU_C="fs/proc/task_mmu.c"
SYS_C="kernel/sys.c"

echo "====================================================================="
echo " 🧼 STARTING SAFE RESIDUAL CLEANING (NO CHECKOUT)..."
echo "====================================================================="

# 1. 精准清洗上一次脚本在 fs/namespace.c 里留下的冲突变量声明与旧标签，保留原厂和其他补丁成果
if [ -f "$NAMESPACE_C" ]; then
    sed -i '/susfs_bypass_alloc:/d' "$NAMESPACE_C"
    sed -i '/is_mnt_ksu_unshared = false;/d' "$NAMESPACE_C"
    sed -i '/CONFIG_KSU_SUSFS_SUS_MOUNT/d' "$NAMESPACE_C"
    sed -i '/extern bool susfs_is_current_ksu_domain/d' "$NAMESPACE_C"
    # 彻底回滚文件到未经本脚本修改的干净状态（防止多轮编译把括号改烂）
    git checkout -- "$NAMESPACE_C" || true
fi

echo "====================================================================="
# ---------------------------------------------------------------------
#  1. 修补 fs/namespace.c (修复 C99 声明冲突与花括号闭合地狱)
# ---------------------------------------------------------------------
if [ -f "$NAMESPACE_C" ]; then
    echo "⚙️ sed aligning: $NAMESPACE_C ..."

    # A. 头部结构和定义注入（加保护判断，防止重复插入）
    if ! grep -q "VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT" "$NAMESPACE_C"; then
        sed -i '/#include "internal.h"/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#ifndef VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT\n#define VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT BIT(24)\n#endif\n#ifndef DEFAULT_KSU_MNT_GROUP_ID\n#define DEFAULT_KSU_MNT_GROUP_ID (100000)\n#endif\nextern bool susfs_is_current_ksu_domain(void);\nextern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;\n#define CL_COPY_MNT_NS BIT(25)\n#endif' "$NAMESPACE_C"
    fi

    # B. mnt_free_id 顶部拦截
    if ! grep -q "VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT" "$NAMESPACE_C" | grep -q "mnt_free_id"; then
        sed -i '/static void mnt_free_id(struct mount \*mnt)/{n;a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt.mnt_flags \& VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)\n\t\treturn;\n#endif
}' "$NAMESPACE_C"
    fi

    # C. mnt_alloc_group_id 特权分配拦截 (为了根除 C99 混合声明错误，将 res_ksu 移到函数最顶端变量声明区)
    if ! grep -q "int res_ksu;" "$NAMESPACE_C"; then
        sed -i '/static int mnt_alloc_group_id(struct mount \*mnt)/{n;a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tint res_ksu;\n\tif (susfs_is_current_ksu_domain()) {\n\t\tif (!ida_pre_get(\&mnt_group_ida, GFP_KERNEL))\n\t\t\treturn -ENOMEM;\n\t\tres_ksu = ida_get_new_above(\&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, \&mnt->mnt_group_id);\n\t\tif (!res_ksu)\n\t\t\treturn 0;\n\t}\n#endif
}' "$NAMESPACE_C"
    fi

    # D. mnt_release_group_id 防火墙
    if ! grep -q "DEFAULT_KSU_MNT_GROUP_ID" "$NAMESPACE_C" | grep -q "mnt_release_group_id"; then
        sed -i '/void mnt_release_group_id(struct mount \*mnt)/{n;a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt_group_id == DEFAULT_KSU_MNT_GROUP_ID)\n\t\treturn;\n#endif
}' "$NAMESPACE_C"
    fi

    # E. 【核心修复】精确闭合花括号，移除非法控制符，重新注入 clone_mnt 安全块
    sed -i '/struct mount \*clone_mnt(struct mount \*old, struct dentry \*root,/,/int err;/ {
        /int err;/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tbool is_mnt_ksu_unshared = false;\n\tif (static_branch_unlikely(\&susfs_is_sdcard_android_data_not_decrypted)) {\n\t\tif (susfs_is_current_ksu_domain()) {\n\t\t\tif (flag \& CL_COPY_MNT_NS) {\n\t\t\t\tmnt = susfs_alloc_unshare_ksu_vfsmnt(old->mnt_devname, old->mnt_id);\n\t\t\t\tis_mnt_ksu_unshared = true;\n\t\t\t\tgoto susfs_bypass_alloc;\n\t\t\t}\n\t\t\tmnt = susfs_alloc_non_unshare_ksu_vfsmnt(old->mnt_devname);\n\t\t\tgoto susfs_bypass_alloc;\n\t\t}\n\t}\n\tif (old->mnt_id >= DEFAULT_KSU_MNT_ID) {\n\t\tmnt = susfs_alloc_non_unshare_ksu_vfsmnt(old->mnt_devname);\n\t\t\tgoto susfs_bypass_alloc;\n\t}\n#endif
    }' "$NAMESPACE_C"

    # F. 重新放下游跳转标签 susfs_bypass_alloc (防漏锁)
    sed -i '/struct mount \*clone_mnt(struct mount \*old, struct dentry \*root,/,/return mnt;/ {
        /if (!mnt)/i \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\nsusfs_bypass_alloc:\n#endif
    }' "$NAMESPACE_C"

    # G. 旗标安全注入
    sed -i '/struct mount \*clone_mnt(struct mount \*old, struct dentry \*root,/,/return mnt;/ {
        /mnt->mnt.mnt_flags = old->mnt.mnt_flags;/a \
\tmnt->mnt.mnt_flags \&= ~(MNT_WRITE_HOLD|MNT_MARKED|MNT_INTERNAL);\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (unlikely(is_mnt_ksu_unshared))\n\t\tmnt->mnt.mnt_flags |= VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT;\n#endif
    }' "$NAMESPACE_C"

    echo "✅ $NAMESPACE_C sed patched flawlessly."
fi

# ---------------------------------------------------------------------
#  2. 修补 fs/proc/cmdline.c
# ---------------------------------------------------------------------
if [ -f "$CMDLINE_C" ] && ! grep -q "susfs_spoof_cmdline_or_bootconfig" "$CMDLINE_C"; then
    echo "⚙️ sed aligning: $CMDLINE_C ..."
    sed -i '/static int cmdline_proc_show/i \
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\nextern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;\nextern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);\n#endif\n' "$CMDLINE_C"
    sed -i '/static int cmdline_proc_show/{n; a \
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\n\tif (static_branch_likely(\&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {\n\t\tsusfs_spoof_cmdline_or_bootconfig(m);\n\t\tseq_printf(m, "%s\\n");\n\t\treturn 0;\n\t}\n#endif
}' "$CMDLINE_C"
    echo "✅ $CMDLINE_C sed patched flawlessly."
fi

# ---------------------------------------------------------------------
#  3. 修补 fs/proc/task_mmu.c (对齐评估：完美恢复原生 def.h 独立配置开关规范)
# ---------------------------------------------------------------------
if [ -f "$TASK_MMU_C" ]; then
    echo "⚙️ sed aligning: $TASK_MMU_C ..."
    
    sed -i '/linux\/susfs.h/d' "$TASK_MMU_C"
    sed -i '/linux\/susfs_def.h/d' "$TASK_MMU_C"
    sed -i '/CONFIG_KSU_SUSFS_/d' "$TASK_MMU_C"
    sed -i '/linux\/cred.h/d' "$TASK_MMU_C"

    # 第一行顶格注入依赖，确保单独功能裁剪时极度纯净
    sed -i '1i #include <linux/cred.h>\n#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs_def.h>\n#endif' "$TASK_MMU_C"

    if ! grep -q "struct vm_area_struct \*vma_ksu = v;" "$TASK_MMU_C"; then
        sed -i '/static int show_smap(struct seq_file \*m, void \*v)/{n;a \
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tstruct vm_area_struct *vma_ksu = v;\n\tif (vma_ksu \&\& vma_ksu->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma_ksu->vm_file)))\n\t\t\treturn 0;\n\t}\n#endif
}' "$TASK_MMU_C"
    fi
    echo "✅ $TASK_MMU_C 完美对齐，已安全注入纯净 susfs_def.h 头文件依赖链。"
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
echo " 🎉 CI/CD DEPLOYMENT PREP COMPLETE: ALL RESCUE HUNKS INJECTED CLEANLY!"
echo "====================================================================="
