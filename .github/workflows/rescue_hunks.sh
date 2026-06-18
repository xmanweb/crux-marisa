#!/bin/bash
# .github/workflows/rescue_hunks.sh
set -e

echo "🚀 [Script Engine] Executing strict incremental patch-level corrections (No checkout)..."

# =====================================================================
# 1. 严格修复 fs/proc/cmdline.c (增量注入)
# =====================================================================
echo "🔧 [Fixing] fs/proc/cmdline.c..."

if ! grep -q "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG" fs/proc/cmdline.c; then
    sed -i '/static int cmdline_proc_show/i #ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\nextern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;\nextern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);\n#endif\n' fs/proc/cmdline.c

    sed -i '/static int cmdline_proc_show(struct seq_file \*m, void \*v)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\n\tif (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {\n\t\tsusfs_spoof_cmdline_or_bootconfig(m);\n\t\tseq_printf(m, "%s\\n");\n\t\treturn 0;\n\t}\n#endif' fs/proc/cmdline.c
fi


# =====================================================================
# 2. 严格修复 fs/namespace.c (带有脏字符擦除与防重复机制)
# =====================================================================
echo "🔧 [Fixing] fs/namespace.c..."

# 2.1 核心修复：如果文件里已经留下了上一轮的 "n#ifdef" 脏数据，原位洗白擦除为 "\n#ifdef"
if grep -q "n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT" fs/namespace.c; then
    echo "🧹 [Sanitizing] Found typo cleaner target 'n#ifdef' in fs/namespace.c, fixing..."
    sed -i 's/n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT/#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT/g' fs/namespace.c
fi

# 2.2 如果压根没注入过宏，则安全追加（使用标准的配合处理，防止 \n 转移失败）
if ! grep -q "DEFAULT_KSU_MNT_GROUP_ID" fs/namespace.c; then
    sed -i '/#include "internal.h"/a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#ifndef VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT\n#define VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT BIT(24)\n#endif\n#ifndef DEFAULT_KSU_MNT_GROUP_ID\n#define DEFAULT_KSU_MNT_GROUP_ID (100000)\n#endif\n#endif' fs/namespace.c
fi

# 2.3 修复 mnt_free_id 
if ! grep -q "VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT" fs/namespace.c; then
    sed -i '/static void mnt_free_id(struct mount \*mnt)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt.mnt_flags & VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)\n\t\treturn;\n#endif' fs/namespace.c
fi

# 2.4 修复 mnt_alloc_group_id
if ! grep -q "res_ksu" fs/namespace.c; then
    sed -i '/static int mnt_alloc_group_id(struct mount \*mnt)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (susfs_is_current_ksu_domain()) {\n\t\tint res_ksu;\n\t\tif (!ida_pre_get(&mnt_group_ida, GFP_KERNEL))\n\t\t\treturn -ENOMEM;\n\t\tres_ksu = ida_get_new_above(&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, \&mnt->mnt_group_id);\n\t\tif (!res_ksu)\n\t\t\treturn 0;\n\t}\n#endif' fs/namespace.c
fi

# 2.5 修复 mnt_release_group_id 
if ! grep -q "mnt->mnt_group_id == DEFAULT_KSU_MNT_GROUP_ID" fs/namespace.c; then
    sed -i '/void mnt_release_group_id(struct mount \*mnt)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt_group_id == DEFAULT_KSU_MNT_GROUP_ID)\n\t\treturn;\n#endif' fs/namespace.c
fi


# =====================================================================
# 3. 严格修复 fs/proc/task_mmu.c (针对残留状态精准补足)
# =====================================================================
echo "🔧 [Fixing] fs/proc/task_mmu.c..."

if ! grep -q "linux/susfs.h" fs/proc/task_mmu.c; then
    sed -i '/#include <linux\/ctype.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs.h>\n#endif' fs/proc/task_mmu.c
fi

# 3.2 针对 show_smap 开头的条件跳转进行安全过滤插入（防重注入保护）
if ! grep -q "goto bypass_orig_flow;" fs/proc/task_mmu.c; then
    sed -i '/show_smap_vma_flags(m, vma);/i #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tif (vma->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\tgoto bypass_orig_flow;\n\t}\n#endif' fs/proc/task_mmu.c

    # 3.3 挂载带有分号保护的跳转标签
    sed -i '/show_smap_vma_flags(m, vma);/a #ifdef CONFIG_KSU_SUSFS_SUS_MAP\nbypass_orig_flow: ;\n#endif' fs/proc/task_mmu.c
fi


# =====================================================================
# 4. 精准修复 kernel/sys.c
# =====================================================================
echo "🔧 [Fixing] kernel/sys.c..."

if ! grep -q "susfs_spoof_uname" kernel/sys.c; then
    # 4.1 注入外部依赖声明
    sed -i '/SYSCALL_DEFINE1(newuname/i #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c
    sed -i '/SYSCALL_DEFINE1(uname/i #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c

    # 4.2 通过全局替换追加拦截
    sed -i 's/memcpy(&tmp, utsname(), sizeof(tmp));/memcpy(\&tmp, utsname(), sizeof(tmp));\n#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(\&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(\&tmp);\n#endif/g' kernel/sys.c
fi


# =====================================================================
# 5. 收尾清理
# =====================================================================
find . -name "*.rej" -delete
find . -name "*.orig" -delete

echo "🎉 [Script Engine] All syntax-level bottlenecks resolved perfectly."
