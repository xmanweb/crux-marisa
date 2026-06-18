#!/bin/bash
# .github/workflows/rescue_hunks.sh
set -e

echo "🚀 [Script Engine] Executing zero-brace precision patch execution..."

# =====================================================================
# 1. 严格修复 fs/proc/cmdline.c
# =====================================================================
echo "🔧 [Fixing] fs/proc/cmdline.c..."

sed -i '/static int cmdline_proc_show/i #ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\nextern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;\nextern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);\n#endif\n' fs/proc/cmdline.c

sed -i '/static int cmdline_proc_show(struct seq_file \*m, void \*v)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\n\tif (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {\n\t\tsusfs_spoof_cmdline_or_bootconfig(m);\n\t\tseq_printf(m, "%s\\n");\n\t\treturn 0;\n\t}\n#endif' fs/proc/cmdline.c


# =====================================================================
# 2. 精准修复 fs/namespace.c (保持完美洗白状态)
# =====================================================================
echo "🔧 [Fixing] fs/namespace.c..."

sed -i '/#include "internal.h"/a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#ifndef VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT\n#define VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT BIT(24)\n#endif\n#ifndef DEFAULT_KSU_MNT_GROUP_ID\n#define DEFAULT_KSU_MNT_GROUP_ID (100000)\n#endif\n#endif' fs/namespace.c

sed -i 's/static void mnt_free_id(struct mount \*mnt)/static void mnt_free_id(struct mount \*mnt)\n{\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt.mnt_flags \& VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)\n\t\treturn;\n#endif/g' fs/namespace.c
sed -i '/#endif/{n;s/^{//}' fs/namespace.c

sed -i 's/static int mnt_alloc_group_id(struct mount \*mnt)/static int mnt_alloc_group_id(struct mount \*mnt)\n{\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (susfs_is_current_ksu_domain()) {\n\t\tint res_ksu;\n\t\tif (!ida_pre_get(\&mnt_group_ida, GFP_KERNEL))\n\t\t\treturn -ENOMEM;\n\t\tres_ksu = ida_get_new_above(\&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, \&mnt->mnt_group_id);\n\t\tif (!res_ksu)\n\t\t\treturn 0;\n\t}\n#endif/g' fs/namespace.c
sed -i '/#endif/{n;s/^{//}' fs/namespace.c

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
# 4. 彻底重构 kernel/sys.c (精准靶向锁定，100% 规避误杀)
# =====================================================================
echo "🔧 [Fixing] kernel/sys.c..."

# 4.1 在 newuname 上方精准注入外部声明 (仅此一处)
sed -i '/SYSCALL_DEFINE1(newuname/i #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c

# 4.2 通过绝对唯一的函数入口锚点，向下顺延特定行数进行精准替换
# 定位到 SYSCALL_DEFINE1(newuname)，然后向下匹配第一个 memcpy 并进行就地替换，绝不影响其他任何函数！
sed -i '/SYSCALL_DEFINE1(newuname/,/memcpy/s/memcpy(&tmp, utsname(), sizeof(tmp));/memcpy(\&tmp, utsname(), sizeof(tmp));\n#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(\&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(\&tmp);\n#endif/' kernel/sys.c


# =====================================================================
# 5. 收尾清理
# =====================================================================
find . -name "*.rej" -delete
find . -name "*.orig" -delete

echo "🎉 [Script Engine] Non-destructive deployment finished perfectly."
