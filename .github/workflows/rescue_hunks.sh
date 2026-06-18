#!/bin/bash
# .github/workflows/rescue_hunks.sh
set -e

echo "🚀 [Script Engine] Executing strict incremental patch-level corrections (No checkout)..."

# =====================================================================
# 1. 严格修复 fs/proc/cmdline.c (增量注入)
# =====================================================================
echo "🔧 [Fixing] fs/proc/cmdline.c..."

# 1.1 检查并注入全局声明（若未包含则注入）
if ! grep -q "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG" fs/proc/cmdline.c; then
    sed -i '/static int cmdline_proc_show/i #ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\nextern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;\nextern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);\n#endif\n' fs/proc/cmdline.c

    sed -i '/static int cmdline_proc_show(struct seq_file \*m, void \*v)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\n\tif (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {\n\t\tsusfs_spoof_cmdline_or_bootconfig(m);\n\t\tseq_printf(m, "%s\\n");\n\t\treturn 0;\n\t}\n#endif' fs/proc/cmdline.c
fi


# =====================================================================
# 2. 严格修复 fs/namespace.c (增量补齐头部未合入的宏与逻辑体)
# =====================================================================
echo "🔧 [Fixing] fs/namespace.c..."

# 2.1 安全补齐未成功合入的全局宏（带条件防护，防止重定义错误）
sed -i '/#include "internal.h"/a \n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#ifndef VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT\n#define VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT BIT(24)\n#endif\n#ifndef DEFAULT_KSU_MNT_GROUP_ID\n#define DEFAULT_KSU_MNT_GROUP_ID (100000)\n#endif\n#endif\n' fs/namespace.c

# 2.2 修复 mnt_free_id 
sed -i '/static void mnt_free_id(struct mount \*mnt)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt.mnt_flags & VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)\n\t\treturn;\n#endif' fs/namespace.c

# 2.3 修复 mnt_alloc_group_id
sed -i '/static int mnt_alloc_group_id(struct mount \*mnt)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (susfs_is_current_ksu_domain()) {\n\t\tint res_ksu;\n\t\tif (!ida_pre_get(&mnt_group_ida, GFP_KERNEL))\n\t\t\treturn -ENOMEM;\n\t\tres_ksu = ida_get_new_above(&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, \&mnt->mnt_group_id);\n\t\tif (!res_ksu)\n\t\t\treturn 0;\n\t}\n#endif' fs/namespace.c

# 2.4 修复 mnt_release_group_id 
sed -i '/void mnt_release_group_id(struct mount \*mnt)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt_group_id == DEFAULT_KSU_MNT_GROUP_ID)\n\t\treturn;\n#endif' fs/namespace.c


# =====================================================================
# 3. 严格修复 fs/proc/task_mmu.c (针对残留状态精准补足)
# =====================================================================
echo "🔧 [Fixing] fs/proc/task_mmu.c..."

# 3.1 检查头文件支持
if ! grep -q "linux/susfs.h" fs/proc/task_mmu.c; then
    sed -i '/#include <linux\/ctype.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs.h>\n#endif' fs/proc/task_mmu.c
fi

# 3.2 针对 show_smap 开头的条件跳转进行安全过滤插入
sed -i '/show_smap_vma_flags(m, vma);/i #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tif (vma->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\tgoto bypass_orig_flow;\n\t}\n#endif' fs/proc/task_mmu.c

# 3.3 挂载带有分号保护的跳转标签
sed -i '/show_smap_vma_flags(m, vma);/a #ifdef CONFIG_KSU_SUSFS_SUS_MAP\nbypass_orig_flow: ;\n#endif' fs/proc/task_mmu.c


# =====================================================================
# 4. 精准修复 kernel/sys.c (追加逻辑体)
# =====================================================================
echo "🔧 [Fixing] kernel/sys.c..."

if ! grep -q "susfs_spoof_uname" kernel/sys.c; then
    # 4.1 newuname 声明与体插入
    sed -i '/SYSCALL_DEFINE1(newuname/i #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c

    sed -i '/SYSCALL_DEFINE1(newuname/,/memcpy(&tmp, utsname(), sizeof(tmp));/ { /memcpy(&tmp, utsname(), sizeof(tmp));/a #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(\&tmp);\n#endif\n }' kernel/sys.c

    # 4.2 老版本 uname 声明与体插入
    sed -i '/SYSCALL_DEFINE1(uname/i #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c

    sed -i '/SYSCALL_DEFINE1(uname/,/memcpy(&tmp, utsname(), sizeof(tmp));/ { /memcpy(&tmp, utsname(), sizeof(tmp));/a #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(\&tmp);\n#endif\n }' kernel/sys.c
fi


# =====================================================================
# 5. 收尾清理
# =====================================================================
find . -name "*.rej" -delete
find . -name "*.orig" -delete

echo "🎉 [Script Engine] Dynamic incremental patches successfully synced."
