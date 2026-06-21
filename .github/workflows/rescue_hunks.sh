#!/bin/bash
# ==============================================================================
# 🚀 [Actions Monolithic Engine] SusFS 4.14 内核全新干净源码全量重塑脚本
# ==============================================================================

echo "=== [Actions Core] 针对干净源码树启动全量清障与特性植入 ==="

python3 -c '
import os
import re

# ------------------------------------------------------------------------------
# 1. 适配新版 IDA 机制并重塑 fs/namespace.c
# ------------------------------------------------------------------------------
if os.path.exists("fs/namespace.c"):
    with open("fs/namespace.c", "r") as f:
        ns_content = f.read()

    # A. 注入外部符号声明
    if "extern bool susfs_is_secret_mount" not in ns_content:
        ns_content = ns_content.replace(
            "#include \"internal.h\"",
            "#include \"internal.h\"\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\nextern bool susfs_is_secret_mount(struct mount *mnt);\nextern bool susfs_is_current_ksu_domain(void);\n#endif"
        )
        print("[+] [namespace.c] 注入外部符号声明完毕")

    # B. 强补 mnt_free_id 过滤
    if "mnt->mnt.mnt_flags & VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT" not in ns_content:
        ns_content = ns_content.replace(
            "int id = mnt->mnt_id;",
            "int id = mnt->mnt_id;\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt.mnt_flags & VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)\n\t\treturn;\n#endif"
        )
        print("[+] [namespace.c] 强补 mnt_free_id 完毕")

    # C. 适配现代 ida_alloc_min 机制，彻底消灭 mnt_group_start 未定义错误
    alloc_pattern = r"static int mnt_alloc_group_id\(struct mount \*mnt\)\s*\{([\s\S]*?)\n\}"
    alloc_target_code = """static int mnt_alloc_group_id(struct mount *mnt)
{
	int res;
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
	if (susfs_is_current_ksu_domain()) {
		res = ida_alloc_min(&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, GFP_KERNEL);
		if (res < 0)
			return res;
		mnt->mnt_group_id = res;
		return 0;
	}
#endif
	res = ida_alloc_min(&mnt_group_ida, 1, GFP_KERNEL);
	if (res < 0)
		return res;
	mnt->mnt_group_id = res;
	return 0;
}"""
    ns_content = re.sub(alloc_pattern, alloc_target_code, ns_content)
    print("[+] [namespace.c] 重塑 mnt_alloc_group_id (适配新版 IDA 机制)")

    # D. 重写 m_show 函数，将 Hook 移至变量声明下方，彻底解决 C99 编译警告
    m_show_pattern = r"static int m_show\(struct seq_file \*m,\s*void \*v\)\s*\{([\s\S]*?)\n\}"
    m_show_target = """static int m_show(struct seq_file *m, void *v)
{
	struct proc_mounts *p = m->private;
	struct mount *r = list_entry(v, struct mount, mnt_list);
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
	if (susfs_is_current_ksu_domain()) {
		if (r && susfs_is_secret_mount(r))
			return 0;
	}
#endif
	return p->show(m, &r->mnt);
}"""
    ns_content = re.sub(m_show_pattern, m_show_target, ns_content)
    print("[+] [namespace.c] 重写 m_show (规范化 C99 变量声明顺序)")

    with open("fs/namespace.c", "w") as f:
        f.write(ns_content)


# ------------------------------------------------------------------------------
# 2. 全量布防 fs/proc/task_mmu.c (4 处核心拦截点)
# ------------------------------------------------------------------------------
if os.path.exists("fs/proc/task_mmu.c"):
    with open("fs/proc/task_mmu.c", "r") as f:
        mmu_content = f.read()

    if "linux/susfs_def.h" not in mmu_content:
        mmu_content = mmu_content.replace(
            "#include <asm/elf.h>",
            "#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs_def.h>\n#endif\n#include <asm/elf.h>"
        )

    sus_map_hook = """
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
	struct vm_area_struct *ksu_vma = v;
	if (ksu_vma && ksu_vma->vm_file && file_inode(ksu_vma->vm_file)) {
		if (SUSFS_IS_INODE_SUS_MAP(file_inode(ksu_vma->vm_file))) {
			return 0;
		}
	}
#endif"""

    if "show_map" in mmu_content and "/* hook_show_map */" not in mmu_content:
        mmu_content = re.sub(r"(static int show_map\(struct seq_file \*m,\s*void \*v\)\s*\{)", r"\1\n\t/* hook_show_map */" + sus_map_hook, mmu_content)
    if "show_smap" in mmu_content and "/* hook_show_smap */" not in mmu_content:
        mmu_content = re.sub(r"(static int show_smap\(struct seq_file \*m,\s*void \*v.*?\)\s*\{)", r"\1\n\t/* hook_show_smap */" + sus_map_hook, mmu_content)
    if "show_numa_map" in mmu_content and "/* hook_show_numa */" not in mmu_content:
        mmu_content = re.sub(r"(static int show_numa_map\(struct seq_file \*m,\s*void \*v\)\s*\{)", r"\1\n\t/* hook_show_numa */" + sus_map_hook, mmu_content)
    if "show_smaps_rollup" in mmu_content and "/* hook_rollup */" not in mmu_content:
        mmu_content = re.sub(r"(static int show_smaps_rollup\(struct seq_file \*m,\s*void \*v\)\s*\{)", r"\1\n\t/* hook_rollup */" + sus_map_hook, mmu_content)

    print("[+] [task_mmu.c] 4 处内核映射拦截网全量部署完毕")
    with open("fs/proc/task_mmu.c", "w") as f:
        f.write(mmu_content)


# ------------------------------------------------------------------------------
# 3. 全量劫持 fs/proc/cmdline.c
# ------------------------------------------------------------------------------
if os.path.exists("fs/proc/cmdline.c"):
    with open("fs/proc/cmdline.c", "r") as f:
        cmd_content = f.read()

    if "susfs_spoof_cmdline_or_bootconfig" not in cmd_content:
        cmd_content = cmd_content.replace(
            "static int cmdline_proc_show(struct seq_file *m, void *v)\n{",
            """#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
extern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;
extern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);
#endif

static int cmdline_proc_show(struct seq_file *m, void *v)
{
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	if (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {
		susfs_spoof_cmdline_or_bootconfig(m);
		seq_printf(m, "%s\\n");
		return 0;
	}
#endif"""
        )
        print("[+] [cmdline.c] Cmdline 欺骗逻辑劫持完毕")
        with open("fs/proc/cmdline.c", "w") as f:
            f.write(cmd_content)


# ------------------------------------------------------------------------------
# 4. 精准重写 kernel/sys.c (锁定 newuname 作用域)
# ------------------------------------------------------------------------------
if os.path.exists("kernel/sys.c"):
    with open("kernel/sys.c", "r") as f:
        sys_content = f.read()

    if "extern void susfs_spoof_uname" not in sys_content:
        sys_content = sys_content.replace(
            "SYSCALL_DEFINE1(newuname",
            "#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif\nSYSCALL_DEFINE1(newuname"
        )

    if "susfs_spoof_uname(&tmp)" not in sys_content:
        sys_content = re.sub(
            r"(SYSCALL_DEFINE1\(newuname[\s\S]*?)(memcpy\(&tmp,\s*utsname\(\),\s*sizeof\(tmp\)\);)",
            r"\1\2\n#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(&tmp);\n#endif",
            sys_content
        )
        print("[+] [sys.c] Uname 欺骗逻辑劫持完毕")

    with open("kernel/sys.c", "w") as f:
        f.write(sys_content)

'
echo "=== [Actions Core] 针对干净源码树的Monolithic劫持引擎执行完毕 ==="
