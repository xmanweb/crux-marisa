#!/bin/bash
# .github/workflows/rescue_hunks.sh
set -e

echo "🚀 [Script Engine] Starting structural rescue for crux custom kernel..."

# =====================================================================
# 1. 重构 fs/proc/cmdline.c (保留厂商预留的 INITRAMFS 修复逻辑 + 注入 SUSFS)
# =====================================================================
echo "🔧 [Fixing] fs/proc/cmdline.c..."
git checkout fs/proc/cmdline.c 2>/dev/null || true

cat << 'EOF' > fs/proc/cmdline.c
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#ifdef CONFIG_INITRAMFS_IGNORE_SKIP_FLAG
#include <asm/setup.h>
#endif

#ifdef CONFIG_INITRAMFS_IGNORE_SKIP_FLAG
#define INITRAMFS_STR_FIND "skip_initramfs"
#define INITRAMFS_STR_REPLACE "want_initramfs"
#define INITRAMFS_STR_LEN (sizeof(INITRAMFS_STR_FIND) - 1)

static char proc_command_line[COMMAND_LINE_SIZE];

static void proc_command_line_init(void) {
	char *offset_addr;

	strcpy(proc_command_line, saved_command_line);

	offset_addr = strstr(proc_command_line, INITRAMFS_STR_FIND);
	if (!offset_addr)
		return;

	memcpy(offset_addr, INITRAMFS_STR_REPLACE, INITRAMFS_STR_LEN);
}
#endif

#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
extern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;
extern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);
#endif

static int cmdline_proc_show(struct seq_file *m, void *v)
{
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	if (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {
		susfs_spoof_cmdline_or_bootconfig(m);
		seq_printf(m, "%s\n");
		return 0;
	}
#endif
#ifdef CONFIG_INITRAMFS_IGNORE_SKIP_FLAG
	seq_printf(m, "%s\n", proc_command_line);
#else
	seq_printf(m, "%s\n", saved_command_line);
#endif
	return 0;
}

static int cmdline_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, cmdline_proc_show, NULL);
}

static const struct file_operations cmdline_proc_fops = {
	.open		= cmdline_proc_open,
	.read		= seq_read,
	.llseek		= seq_lseek,
	.release	= single_release,
};

static int __init proc_cmdline_init(void)
{
#ifdef CONFIG_INITRAMFS_IGNORE_SKIP_FLAG
	proc_command_line_init();
#endif

	proc_create("cmdline", 0, NULL, &cmdline_proc_fops);
	return 0;
}
fs_initcall(proc_cmdline_init);
EOF

# =====================================================================
# 2. 精准修复 fs/namespace.c (修正 mnt_alloc_group_id 因魔改被截断的底层错位)
# =====================================================================
echo "🔧 [Fixing] fs/namespace.c..."
git checkout fs/namespace.c 2>/dev/null || true

# 2.1 修复 mnt_free_id
sed -i '/int id = mnt->mnt_id;/a \\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt.mnt_flags & VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)\n\t\treturn;\n#endif' fs/namespace.c

# 2.2 修复被插烂的 mnt_alloc_group_id 头结构
sed -i '/static int mnt_alloc_group_id(struct mount \*mnt)/a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (susfs_is_current_ksu_domain()) {\n\t\tint res;\n\t\tif (!ida_pre_get(&mnt_group_ida, GFP_KERNEL))\n\t\t\treturn -ENOMEM;\n\t\tres = ida_get_new_above(&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, \&mnt->mnt_group_id);\n\t\tif (!res)\n\t\t\treturn 0;\n\t}\n#endif' fs/namespace.c

# =====================================================================
# 3. 彻底修复 fs/proc/task_mmu.c (移除所有导致编译断流的非法 continue 逻辑)
# =====================================================================
echo "🔧 [Fixing] fs/proc/task_mmu.c..."
git checkout fs/proc/task_mmu.c 2>/dev/null || true

# 3.1 注入通用 susfs 头文件
sed -i '/#include <linux\/uaccess.h>/i #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs.h>\n#endif' fs/proc/task_mmu.c

# 3.2 规范 show_map_vma 条件返回体
sed -i '/struct inode \*inode = file_inode(vma->vm_file);/a #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\t\tif (SUSFS_IS_INODE_SUS_MAP(inode))\n\t\t\treturn;\n#endif' fs/proc/task_mmu.c

# 3.3 完全清空刚才被插坏的错误行为，使用极其安全的单行注入
sed -i '/static int show_smap(struct seq_file \*m, void \*v)/a #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tstruct vm_area_struct *vma = v;\n\tif (vma && vma->vm_file && SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\treturn 0;\n#endif' fs/proc/task_mmu.c

# 3.4 规范化 show_numa_map 拦截体
sed -i '/static int show_numa_map(struct seq_file \*m, void \*v)/a #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tstruct vm_area_struct *vma = v;\n\tif (vma && vma->vm_file && SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\treturn 0;\n#endif' fs/proc/task_mmu.c

# =====================================================================
# 4. 精准修复 kernel/sys.c (新旧 uname 劫持补强，适配底层业务流)
# =====================================================================
echo "🔧 [Fixing] kernel/sys.c..."
git checkout kernel/sys.c 2>/dev/null || true

sed -i '/SYSCALL_DEFINE1(newuname/i #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c

sed -i '/memcpy(&tmp, utsname(), sizeof(tmp));/a #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(\&tmp);\n#endif' kernel/sys.c

sed -i '/SYSCALL_DEFINE1(uname/i #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c

# 清理残渣
find . -name "*.rej" -delete
find . -name "*.orig" -delete

echo "✅ [Script Engine] All structural failed hunks rescued successfully!"
