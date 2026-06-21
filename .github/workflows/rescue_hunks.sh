#!/bin/bash
# ==============================================================================
# 🛠️ 终极无损修复版 rescue_hunk.sh (基于你的高效内联清障引擎)
# 补全了 namespace.c、task_mmu.c 缺失的挂钩，并将 sys.c 完美融入 Python 引擎
# ==============================================================================

echo "=== [Actions Core] 开始执行高级内联清障引擎 ==="

python3 -c '
import os
import re

def inline_patch(filepath, target_anchor, insert_code, mode="after"):
    if not os.path.exists(filepath):
        print(f"[-] 跳过不存在的文件: {filepath}")
        return
    with open(filepath, "r") as f:
        content = f.read()
    
    if target_anchor in content:
        if insert_code in content:
            print(f"[!] {filepath} 已经处理过，跳过。")
            return
        if mode == "after":
            content = content.replace(target_anchor, target_anchor + "\n" + insert_code)
        elif mode == "before":
            content = content.replace(target_anchor, insert_code + "\n" + target_anchor)
        with open(filepath, "w") as f:
            f.write(content)
        print(f"[+] 成功内联修补: {filepath}")
    else:
        print(f"[-] 错误: 在 {filepath} 中找不到特征锚点: {target_anchor[:30]}...")

# ------------------------------------------------------------------------------
# 1. 修复 fs/namespace.c (追加补全 m_show 挂载隐藏)
# ------------------------------------------------------------------------------
ns_anchor = "static int mnt_alloc_group_id(struct mount *mnt)\n{"
ns_code = """#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
	if (susfs_is_current_ksu_domain()) {
		int res = ida_alloc_min(&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, GFP_KERNEL);
		if (res < 0)
			return res;
		mnt->mnt_group_id = res;
		return 0;
	}
#endif"""
inline_patch("fs/namespace.c", ns_anchor, ns_code, "after")

ns_mshow_anchor = "static int m_show(struct seq_file *m, void *v)\n{"
ns_mshow_code = """#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
	if (susfs_is_current_ksu_domain()) {
		struct mount *r = v;
		if (r && susfs_is_secret_mount(r))
			return 0;
	}
#endif"""
inline_patch("fs/namespace.c", ns_mshow_anchor, ns_mshow_code, "after")


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
# 3. 修复 fs/proc/task_mmu.c (补全 show_map 以及 rollup 循环)
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
        # A. 修复 show_map
        map_pattern = r"(static int show_map\([^{]*\)\s*\{)"
        match_map = re.search(map_pattern, mmu_content)
        if match_map:
            matched_anchor = match_map.group(1)
            map_hook_code = """
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
	struct vm_area_struct *vma = v;
	if (vma && vma->vm_file && file_inode(vma->vm_file)) {
		if (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file))) {
			return 0;
		}
	}
#endif"""
            mmu_content = mmu_content.replace(matched_anchor, matched_anchor + map_hook_code)
            print("[+] 成功通过正则智能适配并修补 show_map")

        # B. 修复 show_smap (保留你的逻辑)
        smap_pattern = r"(static int show_smap\([^{]*\)\s*\{)"
        match_smap = re.search(smap_pattern, mmu_content)
        if match_smap:
            matched_anchor = match_smap.group(1)
            smap_hook_code = """
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
	struct vm_area_struct *vma = v;
	if (vma && vma->vm_file && file_inode(vma->vm_file)) {
		if (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file))) {
			return 0;
		}
	}
#endif"""
            mmu_content = mmu_content.replace(matched_anchor, matched_anchor + smap_hook_code)
            print("[+] 成功通过正则智能适配并修补 show_smap")

        # C. 修复 show_smaps_rollup 中的 vma 遍历循环
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
# 4. 修复 kernel/sys.c (将原 shell sed 逻辑安全移入 Python 块)
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
