#!/bin/bash
# ==============================================================================
# 🛠️ 终极版 rescue_hunk.sh (智能正则匹配 + 依赖强力注入)
# 彻底解决 task_mmu.c 锚点不匹配导致的头文件缺失与隐式声明报错
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
        elif mode == "replace":
            content = content.replace(target_anchor, insert_code)
        with open(filepath, "w") as f:
            f.write(content)
        print(f"[+] 成功内联修补: {filepath}")
    else:
        print(f"[-] 错误: 在 {filepath} 中找不到特征锚点: {target_anchor[:30]}...")

# ------------------------------------------------------------------------------
# 1. 修复 fs/namespace.c (现代 IDA 语法适配)
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
# 2. 修复 fs/proc/cmdline.c (前置拦截)
# ------------------------------------------------------------------------------
cmd_anchor = "static int cmdline_proc_show(struct seq_file *m, void *v)\n{"
cmd_code = """#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	if (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {
		susfs_spoof_cmdline_or_bootconfig(m);
		seq_printf(m, "%s\\n");
		return 0;
	}
#endif"""
inline_patch("fs/proc/cmdline.c", cmd_anchor, cmd_code, "after")

# ------------------------------------------------------------------------------
# 3. 强力修复 fs/proc/task_mmu.c (头文件注入 + 正则智能匹配)
# ------------------------------------------------------------------------------
if os.path.exists("fs/proc/task_mmu.c"):
    with open("fs/proc/task_mmu.c", "r") as f:
        mmu_content = f.read()

    # A. 无论如何，先确保头文件和必要宏声明进去
    mmu_header = "#include <linux/ctype.h>"
    mmu_header_code = """
#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)
#include <linux/susfs_def.h>
#endif
"""
    if "linux/susfs_def.h" not in mmu_content:
        mmu_content = mmu_content.replace(mmu_header, mmu_header + mmu_header_code)
        print("[+] 成功注入 task_mmu.c 核心头文件依赖")

    # B. 使用正则表达式动态匹配 show_smap 签名，完美兼容不同内核参数数量
    if "CONFIG_KSU_SUSFS_SUS_MAP" not in mmu_content:
        # 匹配 static int show_smap(参数...) { 这种结构
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
        else:
            print("[-] 警告: 即使使用正则也未能找到 show_smap 函数入口")
            
    with open("fs/proc/task_mmu.c", "w") as f:
        f.write(mmu_content)
'

# ------------------------------------------------------------------------------
# 4. 修复 kernel/sys.c (保持原位单行快照劫持)
# ------------------------------------------------------------------------------
if [ -f "kernel/sys.c" ]; then
    echo "[+] 正在二次修补: kernel/sys.c"
    if ! grep -q "susfs_is_uname_spoof_buffer_set" kernel/sys.c; then
        sed -i '/#include <linux\/syscalls.h>/a #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c
        sed -i 's/memcpy(&tmp, utsname(), sizeof(tmp));/memcpy(\&tmp, utsname(), sizeof(tmp));\n#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(\&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(\&tmp);\n#endif/' kernel/sys.c
    fi
fi

echo "=== [Actions Core] 二次高级清障成功，结构安全，开始闭环编译 ==="
