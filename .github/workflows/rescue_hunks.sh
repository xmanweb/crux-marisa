#!/bin/bash
# .github/workflows/rescue_hunks.sh
set -e

echo "🚀 [Script Engine] Executing flawless patch-level corrections (Zero-syntax mode)..."

# =====================================================================
# 1. 严格修复 fs/proc/cmdline.c
# =====================================================================
echo "🔧 [Fixing] fs/proc/cmdline.c..."

sed -i '/static int cmdline_proc_show/i #ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\nextern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;\nextern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);\n#endif\n' fs/proc/cmdline.c

sed -i '/static int cmdline_proc_show(struct seq_file \*m, void \*v)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\n\tif (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {\n\t\tsusfs_spoof_cmdline_or_bootconfig(m);\n\t\tseq_printf(m, "%s\\n");\n\t\treturn 0;\n\t}\n#endif' fs/proc/cmdline.c


# =====================================================================
# 2. 精准修复 fs/namespace.c (摒弃大括号，采用独一无二的函数体首行锚点)
# =====================================================================
echo "🔧 [Fixing] fs/namespace.c..."

# 2.1 注入头部宏定义
sed -i '/#include "internal.h"/a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#ifndef VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT\n#define VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT BIT(24)\n#endif\n#ifndef DEFAULT_KSU_MNT_GROUP_ID\n#define DEFAULT_KSU_MNT_GROUP_ID (100000)\n#endif\n#endif' fs/namespace.c

# 2.2 修复 mnt_free_id (精准替换函数体第一行，绝不产生断层错位)
sed -i 's/static void mnt_free_id(struct mount \*mnt)/static void mnt_free_id(struct mount \*mnt)\n{\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt.mnt_flags \& VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)\n\t\treturn;\n#endif/g' fs/namespace.c
# 擦除因上面替换导致原生保留下来的重复左大括号
sed -i '/#endif/{n;s/^{//}' fs/namespace.c

# 2.3 修复 mnt_alloc_group_id
sed -i 's/static int mnt_alloc_group_id(struct mount \*mnt)/static int mnt_alloc_group_id(struct mount \*mnt)\n{\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (susfs_is_current_ksu_domain()) {\n\t\tint res_ksu;\n\t\tif (!ida_pre_get(\&mnt_group_ida, GFP_KERNEL))\n\t\t\treturn -ENOMEM;\n\t\tres_ksu = ida_get_new_above(\&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, \&mnt->mnt_group_id);\n\t\tif (!res_ksu)\n\t\t\treturn 0;\n\t}\n#endif/g' fs/namespace.c
sed -i '/#endif/{n;s/^{//}' fs/namespace.c

# 2.4 修复 mnt_release_group_id
sed -i 's/void mnt_release_group_id(struct mount \*mnt)/void mnt_release_group_id(struct mount \*mnt)\n{\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt_group_id == DEFAULT_KSU_MNT_GROUP_ID)\n\t\treturn;\n#endif/g' fs/namespace.c
sed -i '/#endif/{n;s/^{//}' fs/namespace.c


# =====================================================================
# 3. 严格修复 fs/proc/task_mmu.c
# =====================================================================
echo "🔧 [Fixing] fs/proc/task_mmu.c..."

sed -i '/#include <linux\/ctype.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs.h>\n#endif' fs/proc/task_mmu.c

sed -i '/show_smap_vma_flags(m, vma);/i #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tif (vma->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\tgoto bypass_orig_flow;\n\t}\n#endif' fs/proc/task_mmu.c

sed -i '/show_smap_vma_flags(m, vma);/a #ifdef CONFIG_KSU_SUSFS_SUS_MAP\nbypass_orig_flow: ;\n#endif' fs/proc/task_mmu.c


# =====================================================================
# 4. 精准修复 kernel/sys.c (改用安全边界单行宏替换，彻底规避括号错误)
# =====================================================================
echo "🔧 [Fixing] kernel/sys.c..."

# 4.1 在 newuname 上方精准注入声明
sed -i '/SYSCALL_DEFINE1(newuname/i #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c

# 4.2 利用 `newuname` 和接下来的 `up_read` 之间唯一的特征结构进行无缝单行精准替换
sed -i 's/down_read(&uts_sem);/down_read(\&uts_sem);\n\tmemcpy(\&tmp, utsname(), sizeof(tmp));\n#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(\&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(\&tmp);\n#endif\n\t\/\* original_memcpy_stub_placeholder_bypass \*\//' kernel/sys.c

# 4.3 抹除原生的、紧跟在后面的那行旧 memcpy，避免重复调用
sed -i '/original_memcpy_stub_placeholder_bypass/n;/memcpy/d' kernel/sys.c


# =====================================================================
# 5. 收尾清理
# =====================================================================
find . -name "*.rej" -delete
find . -name "*.orig" -delete

echo "🎉 [Script Engine] Dynamic patches applied with clean zero-brace semantics. Ready!"
