#!/bin/bash
# .github/workflows/rescue_hunks.sh
set -e

echo "🚀 [Script Engine] Starting pure sed-driven structural rescue for crux kernel..."

# =====================================================================
# 1. 精准修复 fs/proc/cmdline.c (使用纯 sed 在原厂/厂商魔改逻辑间隙注入 SUSFS)
# =====================================================================
echo "🔧 [Fixing] fs/proc/cmdline.c..."
git checkout fs/proc/cmdline.c 2>/dev/null || true

# 1.1 注入外部全局变量声明（前置到静态展示函数之上，防止未声明先使用）
sed -i '/static int cmdline_proc_show/i #ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\nextern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;\nextern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);\n#endif\n' fs/proc/cmdline.c

# 1.2 在 cmdline_proc_show 函数体内开局处精准注入劫持拦截体
# 使用 !b;n;a 确保越过函数头声明，精准塞在入口花括号下方
sed -i '/static int cmdline_proc_show(struct seq_file \*m, void \*v)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\n\tif (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {\n\t\tsusfs_spoof_cmdline_or_bootconfig(m);\n\t\tseq_printf(m, "%s\\n");\n\t\treturn 0;\n\t}\n#endif' fs/proc/cmdline.c


# =====================================================================
# 2. 精准修复 fs/namespace.c (修正因函数头直接注入破坏的 C 语法闭合)
# =====================================================================
echo "🔧 [Fixing] fs/namespace.c..."
git checkout fs/namespace.c 2>/dev/null || true

# 2.1 修复 mnt_free_id 
sed -i '/int id = mnt->mnt_id;/a \\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt.mnt_flags & VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)\n\t\treturn;\n#endif' fs/namespace.c

# 2.2 优雅修复 mnt_alloc_group_id (确保注入在花括号内部，不截断原本的逻辑主体)
sed -i '/static int mnt_alloc_group_id(struct mount \*mnt)/!b;n;a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (susfs_is_current_ksu_domain()) {\n\t\tint res;\n\t\tif (!ida_pre_get(&mnt_group_ida, GFP_KERNEL))\n\t\t\treturn -ENOMEM;\n\t\tres = ida_get_new_above(&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, \&mnt->mnt_group_id);\n\t\tif (!res)\n\t\t\treturn 0;\n\t}\n#endif' fs/namespace.c


# =====================================================================
# 3. 稳健补全 fs/proc/task_mmu.c (补齐 Phase 1 中被 Rejected 的 smap 劫持逻辑)
# =====================================================================
echo "🔧 [Fixing] fs/proc/task_mmu.c..."
# 此时 task_mmu.c 已经带着 Phase 1 的部分安全修改，不清空它，直接追加补丁

# 3.1 注入顶部头文件支持
sed -i '/#include <linux\/ctype.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs.h>\n#endif' fs/proc/task_mmu.c

# 3.2 注入 show_smap 的底层安全防护（拦截非 rollup_mode）
sed -i '/if (!rollup_mode)/a #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tif (vma->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\treturn 0;\n\t}\n#endif' fs/proc/task_mmu.c


# =====================================================================
# 4. 精准修复 kernel/sys.c (新旧 uname 伪装代码回流与安全定位)
# =====================================================================
echo "🔧 [Fixing] kernel/sys.c..."
git checkout kernel/sys.c 2>/dev/null || true

# 4.1 为 SYSCALL_DEFINE1(newuname) 注入宏声明与劫持体
sed -i '/SYSCALL_DEFINE1(newuname/i #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c

sed -i '/memcpy(&tmp, utsname(), sizeof(tmp));/a #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(\&tmp);\n#endif' kernel/sys.c

# 4.2 为老版本的 SYSCALL_DEFINE1(uname) 同步注入声明
sed -i '/SYSCALL_DEFINE1(uname/i #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c


# =====================================================================
# 5. 收尾清理
# =====================================================================
find . -name "*.rej" -delete
find . -name "*.orig" -delete

echo "🎉 [Script Engine] Pure sed-driven adaptation completed successfully."
