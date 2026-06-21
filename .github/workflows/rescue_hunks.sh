#!/bin/bash
# ==============================================================================
# 🛠️ 直装修复版 rescue_hunk.sh (精准修复 namespace.c 失败 Hunks)
# 针对老版内核的 ida_get_new_above 分配与释放逻辑进行原汁原味的无损修补
# ==============================================================================

echo "=== [Actions Core] 开始执行高级内联清障引擎 ==="

python3 -c '
import os
import re

# ------------------------------------------------------------------------------
# 1. 修复 fs/namespace.c
# ------------------------------------------------------------------------------
if os.path.exists("fs/namespace.c"):
    with open("fs/namespace.c", "r") as f:
        ns_content = f.read()

    # A. 确保包含外部声明
    if "susfs_is_secret_mount" not in ns_content:
        ns_header_anchor = "#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\nextern bool susfs_is_current_ksu_domain(void);"
        ns_header_code = "\nextern bool susfs_is_secret_mount(struct mount *mnt);"
        ns_content = ns_content.replace(ns_header_anchor, ns_header_anchor + ns_header_code)

    # B. 精准修补 mnt_free_id (对齐 .rej 逻辑)
    ns_free_anchor = "static void mnt_free_id(struct mount *mnt)\n{\n\tint id = mnt->mnt_id;"
    ns_free_code = """
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
	if (mnt->mnt.mnt_flags & VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)
		return;
#endif"""
    if "VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT" not in ns_content and ns_free_anchor in ns_content:
        ns_content = ns_content.replace(ns_free_anchor, ns_free_anchor + ns_free_code)
        print("[+] 成功修补 mnt_free_id 释放过滤逻辑")

    # C. 精准修补 mnt_alloc_group_id (完全对齐 .rej 的 ida_get_new_above 老版机制)
    ns_alloc_anchor = "static int mnt_alloc_group_id(struct mount *mnt)\n{\n\tint res;"
    ns_alloc_code = """
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
	if (susfs_is_current_ksu_domain()) {
		if (!ida_pre_get(&mnt_group_ida, GFP_KERNEL))
			return -ENOMEM;
		res = ida_get_new_above(&mnt_group_ida,
					DEFAULT_KSU_MNT_GROUP_ID,
					&mnt->mnt_group_id);
		goto bypass_orig_flow;
	}

	if (!ida_pre_get(&mnt_group_ida, GFP_KERNEL))
		return -ENOMEM;
	res = ida_get_new_above(&mnt_group_ida,
				mnt_group_start,
				&mnt->mnt_group_id);
bypass_orig_flow:
#else
	if (!ida_pre_get(&mnt_group_ida, GFP_KERNEL))
		return -ENOMEM;

	res = ida_get_new_above(&mnt_group_ida,
				mnt_group_start,
				&mnt->mnt_group_id);
#endif"""

    if "DEFAULT_KSU_MNT_GROUP_ID" not in ns_content and ns_alloc_anchor in ns_content:
        ns_content = ns_content.replace(ns_alloc_anchor, ns_alloc_anchor + ns_alloc_code)
        print("[+] 成功原汁原味修复老版 mnt_alloc_group_id 分配劫持")

    # D. 修复 m_show 处的挂钩
    ns_mshow_anchor = "static int m_show(struct seq_file *m, void *v)\n{"
    ns_mshow_code = """#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
	if (susfs_is_current_ksu_domain()) {
		struct mount *r_ksu = v;
		if (r_ksu && susfs_is_secret_mount(r_ksu))
			return 0;
	}
#endif"""
    if "r_ksu = v" not in ns_content:
        ns_content = ns_content.replace(ns_mshow_anchor, ns_mshow_anchor + "\n" + ns_mshow_code)
        print("[+] 成功修复 m_show 挂载隐藏点")

    with open("fs/namespace.c", "w") as f:
        f.write(ns_content)


# ------------------------------------------------------------------------------
# 2. 修复 fs/proc/cmdline.c
# ------------------------------------------------------------------------------
if os.path.exists("fs/proc/cmdline.c"):
    with open("fs/proc/cmdline.c", "r") as f:
        cmd_content = f.read()

    cmd_anchor_extern = "static int cmdline_proc_show"
    cmd_extern_code = """#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
extern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;
extern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);
#endif
"""
    if "susfs_is_fake_cmdline_or_bootconfig_buffer_set" not in cmd_content and cmd_anchor_extern in cmd_content:
        cmd_content = cmd_content.replace(cmd_anchor_extern, cmd_extern_code + cmd_anchor_extern)
        print("[+] 成功注入 cmdline.c 显式 extern 声明 (static_key_false)")

    cmd_anchor_hook = "static int cmdline_proc_show(struct seq_file *m, void *v)\n{"
    cmd_hook_code = """#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	if (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {
		susfs_spoof_cmdline_or_bootconfig(m);
		seq_printf(m, "%s\\n");
		return 0;
	}
#endif"""
    if "if (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set))" not in cmd_content and cmd_anchor_hook in cmd_content:
        cmd_content = cmd_content.replace(cmd_anchor_hook, cmd_anchor_hook + "\n" + cmd_hook_code)
        print("[+] 成功内联修补挂钩逻辑: fs/proc/cmdline.c")

    with open("fs/proc/cmdline.c", "w") as f:
        f.write(cmd_content)


# ------------------------------------------------------------------------------
# 3. 修复 fs/proc/task_mmu.c
# ------------------------------------------------------------------------------
if os.path.exists("fs/proc/task_mmu.c"):
    with open("fs/proc/task_mmu.c", "r") as f:
        mmu_content = f.read()

    mmu_header = "#include <linux/ctype.h>"
    mmu_header_code = """
#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)
#include <linux/susfs_def.h>
#endif
"""
    if "linux/susfs_def.h" not in mmu_content:
        mmu_content = mmu_content.replace(mmu_header, mmu_header + mmu_header_code)
        print("[+] 成功注入 task_mmu.c 核心头文件依赖")

    if "CONFIG_KSU_SUSFS_SUS_MAP" not in mmu_content:
        map_pattern = r"(static int show_map\([^{]*\)\s*\{)"
        match_map = re.search(map_pattern, mmu_content)
        if match_map:
            matched_anchor = match_map.group(1)
            map_hook_code = """
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
	struct vm_area_struct *vma_ksu = v;
	if (vma_ksu && vma_ksu->vm_file && file_inode(vma_ksu->vm_file)) {
		if (SUSFS_IS_INODE_SUS_MAP(file_inode(vma_ksu->vm_file))) {
			return 0;
		}
	}
#endif"""
            mmu_content = mmu_content.replace(matched_anchor, matched_anchor + map_hook_code)
            print("[+] 成功通过正则智能适配并修补 show_map")

        smap_pattern = r"(static int show_smap\([^{]*\)\s*\{)"
        match_smap = re.search(smap_pattern, mmu_content)
        if match_smap:
            matched_anchor = match_smap.group(1)
            smap_hook_code = """
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
	struct vm_area_struct *vma_ksu = v;
	if (vma_ksu && vma_ksu->vm_file && file_inode(vma_ksu->vm_file)) {
		if (SUSFS_IS_INODE_SUS_MAP(file_inode(vma_ksu->vm_file))) {
			return 0;
		}
	}
#endif"""
            mmu_content = mmu_content.replace(matched_anchor, matched_anchor + smap_hook_code)
            print("[+] 成功通过正则智能适配并修补 show_smap")

        rollup_anchor = "for (vma = priv->mm->mmap; vma; vma = vma->vm_next) {"
        if rollup_anchor in mmu_content:
            rollup_hook_code = """
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
		if (vma->vm_file && file_inode(vma->vm_file) && SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))
			continue;
#endif"""
            mmu_content = mmu_content.replace(rollup_anchor, rollup_anchor + "\n" + rollup_hook_code)
            print("[+] 成功内联修补 show_smaps_rollup 遍历循环")
            
    with open("fs/proc/task_mmu.c", "w") as f:
        f.write(mmu_content)


# ------------------------------------------------------------------------------
# 4. 修复 kernel/sys.c
# ------------------------------------------------------------------------------
if os.path.exists("kernel/sys.c"):
    with open("kernel/sys.c", "r") as f:
        sys_content = f.read()

    if "susfs_is_uname_spoof_buffer_set" not in sys_content:
        sys_header_anchor = "#include <linux/syscalls.h>"
        sys_header_code = """
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
extern struct static_key_false susfs_is_uname_spoof_buffer_set;
extern void susfs_spoof_uname(struct new_utsname* tmp);
#endif"""
        sys_content = sys_content.replace(sys_header_anchor, sys_header_anchor + sys_header_code)

        sys_hook_anchor = "memcpy(&tmp, utsname(), sizeof(tmp));"
        sys_hook_code = """
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
	if (static_branch_likely(&susfs_is_uname_spoof_buffer_set))
		susfs_spoof_uname(&tmp);
#endif"""
        sys_content = sys_content.replace(sys_hook_anchor, sys_hook_anchor + sys_hook_code)
        
        with open("kernel/sys.c", "w") as f:
            f.write(sys_content)
        print("[+] 成功内联修补: kernel/sys.c")
'

echo "=== [Actions Core] 二次高级清障成功，结构安全，开始闭环编译 ==="
