#!/bin/bash
# ==============================================================================
# 🛠️ 直装修复版 rescue_hunk.sh (去除了旧注入清洗逻辑)
# 仅执行精准的 static_key_false 声明与挂钩注入
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
# 1. 修复 fs/namespace.c
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

# ------------------------------------------------------------------------------
# 2. 修复 fs/proc/cmdline.c (直接注入声明与挂钩，不执行清洗)
# ------------------------------------------------------------------------------
if os.path.exists("fs/proc/cmdline.c"):
    with open("fs/proc/cmdline.c", "r") as f:
        cmd_content = f.read()

    # A. 精准注入：在目标函数上方注入原版 extern 声明 (使用 static_key_false)
    cmd_anchor_extern = "static int cmdline_proc_show"
    cmd_extern_code = """#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
extern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;
extern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);
#endif
"""
    if "susfs_is_fake_cmdline_or_bootconfig_buffer_set" not in cmd_content and cmd_anchor_extern in cmd_content:
        cmd_content = cmd_content.replace(cmd_anchor_extern, cmd_extern_code + cmd_anchor_extern)
        print("[+] 成功注入 cmdline.c 显式 extern 声明 (static_key_false)")

    # B. 精准注入：在大括号后注入劫持 Hook 逻辑
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
        smap_pattern = r"(static int show_smap\([^{]*\)\s*\{)"
        match = re.search(smap_pattern, mmu_content)
        if match:
            matched_anchor = match.group(1)
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
            
    with open("fs/proc/task_mmu.c", "w") as f:
        f.write(mmu_content)
'

# ------------------------------------------------------------------------------
# 4. 修复 kernel/sys.c
# ------------------------------------------------------------------------------
if [ -f "kernel/sys.c" ]; then
    echo "[+] 正在二次修补: kernel/sys.c"
    if ! grep -q "susfs_is_uname_spoof_buffer_set" kernel/sys.c; then
        sed -i '/#include <linux\/syscalls.h>/a #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c
        sed -i 's/memcpy(&tmp, utsname(), sizeof(tmp));/memcpy(\&tmp, utsname(), sizeof(tmp));\n#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(\&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(\&tmp);\n#endif/' kernel/sys.c
    fi
fi

echo "=== [Actions Core] 二次高级清障成功，结构安全，开始闭环编译 ==="
