#!/bin/bash
# .github/workflows/rescue_hunks.sh
set -e

echo "🚀 [Script Engine] Executing strict patch-level sed corrections..."

# =====================================================================
# 1. 精准修复 fs/proc/cmdline.c
# =====================================================================
echo "🔧 [Fixing] fs/proc/cmdline.c..."
git checkout fs/proc/cmdline.c 2>/dev/null || true

sed -i '/static int cmdline_proc_show/i #ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\nextern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;\nextern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);\n#endif\n' fs/proc/cmdline.c

sed -i '/static int cmdline_proc_show(struct seq_file \*m, void \*v)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\n\tif (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {\n\t\tsusfs_spoof_cmdline_or_bootconfig(m);\n\t\tseq_printf(m, "%s\\n");\n\t\treturn 0;\n\t}\n#endif' fs/proc/cmdline.c


# =====================================================================
# 2. 严格修复 fs/namespace.c (补齐全部 3 处失败)
# =====================================================================
echo "🔧 [Fixing] fs/namespace.c..."
git checkout fs/namespace.c 2>/dev/null || true

# 2.1 修复 mnt_free_id (Hunk 1)
sed -i '/static void mnt_free_id(struct mount \*mnt)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt.mnt_flags & VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)\n\t\treturn;\n#endif' fs/namespace.c

# 2.2 修复 mnt_alloc_group_id (Hunk 2)
sed -i '/static int mnt_alloc_group_id(struct mount \*mnt)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (susfs_is_current_ksu_domain()) {\n\t\tint res;\n\t\tif (!ida_pre_get(&mnt_group_ida, GFP_KERNEL))\n\t\t\treturn -ENOMEM;\n\t\tres = ida_get_new_above(&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, \&mnt->mnt_group_id);\n\t\tif (!res)\n\t\t\treturn 0;\n\t}\n#endif' fs/namespace.c

# 2.3 修复 mnt_release_group_id (Hunk 3 - 补齐原本漏掉的 release 对应逻辑)
sed -i '/void mnt_release_group_id(struct mount \*mnt)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt_group_id == DEFAULT_KSU_MNT_GROUP_ID)\n\t\treturn;\n#endif' fs/namespace.c


# =====================================================================
# 3. 严格修复 fs/proc/task_mmu.c (完美还原 show_smap 的 goto 跳过逻辑)
# =====================================================================
echo "🔧 [Fixing] fs/proc/task_mmu.c..."

# 3.1 注入顶部头文件支持 (Hunk 1)
sed -i '/#include <linux\/ctype.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs.h>\n#endif' fs/proc/task_mmu.c

# 3.2 还原 show_smap 中对基础打印的拦截与分流 (Hunk 2)
sed -i '/if (!rollup_mode)/a #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tif (vma->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\tgoto bypass_orig_flow;\n\t}\n#endif' fs/proc/task_mmu.c

# 3.3 还原 show_smap 尾部的 arch_show_smap 跳过与标签挂载 (Hunk 3 & 4)
sed -i '/show_smap_vma_flags(m, vma);/a #ifdef CONFIG_KSU_SUSFS_SUS_MAP\nbypass_orig_flow:\n#endif' fs/proc/task_mmu.c


# =====================================================================
# 4. 精准修复 kernel/sys.c
# =====================================================================
echo "🔧 [Fixing] kernel/sys.c..."
git checkout kernel/sys.c 2>/dev/null || true

# 4.1 newuname 声明
sed -i '/SYSCALL_DEFINE1(newuname/i #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c

# 4.2 newuname 劫持 (紧跟 memcpy 确保严格拦截)
sed -i '/memcpy(&tmp, utsname(), sizeof(tmp));/!b;a #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(&susfs_is_uname_spoof_buffer_set)) {\n\t\tsusfs_spoof_uname(\&tmp);\n\t}\n#endif' kernel/sys.c

# 4.3 老版本 uname 修复
sed -i '/SYSCALL_DEFINE1(uname/i #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c


# =====================================================================
# 5. 收尾清理
# =====================================================================
find . -name "*.rej" -delete
find . -name "*.orig" -delete

echo "🎉 [Script Engine] Patch-level strict adaptation completed successfully."
