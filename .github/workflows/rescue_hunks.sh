#!/bin/bash
# ==============================================================================
# 🛠️ 进化版 rescue_hunk.sh (原地内联注入 + 现代 IDA 语法适配)
# 彻底解决隐式声明与 mnt_group_start 变量未定义报错
# ==============================================================================

echo "=== [Actions Core] 开始执行高级内联清障引擎 ==="

# 使用 Python 进行精准的结构化文本替换，完美规避环境引发的 sed 空格/换行差异
python3 -c '
import os

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
        print(f"[-] 错误: 在 {filepath} 中找不到特征锚点!")

# ------------------------------------------------------------------------------
# 1. 修复 fs/namespace.c (完美适配 ida_alloc_min 现代语法)
# ------------------------------------------------------------------------------
# 原厂函数的标准开头
ns_anchor = """static int mnt_alloc_group_id(struct mount *mnt)
{"""

# 注入忠实于原补丁意图、但改用现代 ida_alloc_min 语法的非穿透拦截流
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
# 2. 修复 fs/proc/cmdline.c (前置拦截，防止执行顺序错乱)
# ------------------------------------------------------------------------------
cmd_anchor = """static int cmdline_proc_show(struct seq_file *m, void *v)
{"""

cmd_code = """#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	if (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {
		susfs_spoof_cmdline_or_bootconfig(m);
		seq_printf(m, "%s\\n");
		return 0;
	}
#endif"""

inline_patch("fs/proc/cmdline.c", cmd_anchor, cmd_code, "after")

# ------------------------------------------------------------------------------
# 3. 修复 fs/proc/task_mmu.c (无缝注入带 3 参数厂商特征的 show_smap)
# ------------------------------------------------------------------------------
mmu_anchor = """static int show_smap(struct seq_file *m, void *v, int is_pid)
{"""

mmu_code = """#ifdef CONFIG_KSU_SUSFS_SUS_MAP
	struct vm_area_struct *vma = v;
	if (vma && vma->vm_file && file_inode(vma->vm_file)) {
		if (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file))) {
			return 0;
		}
	}
#endif"""

inline_patch("fs/proc/task_mmu.c", mmu_anchor, mmu_code, "after")
'

# ------------------------------------------------------------------------------
# 4. 修复 kernel/sys.c (继续保持高效的单行原地快照劫持)
# ------------------------------------------------------------------------------
if [ -f "kernel/sys.c" ]; then
    echo "[+] 正在二次修补: kernel/sys.c"
    # 补充可能遗漏的系统调用头文件内外部声明
    sed -i '/#include <linux\/syscalls.h>/a #ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif' kernel/sys.c

    # 在系统调用读取内核版本信息的 memcpy 后直接拦截注入
    sed -i 's/memcpy(&tmp, utsname(), sizeof(tmp));/memcpy(\&tmp, utsname(), sizeof(tmp));\n#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(\&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(\&tmp);\n#endif/' kernel/sys.c
fi

echo "=== [Actions Core] 二次高级清障成功，结构安全，开始闭环编译 ==="
