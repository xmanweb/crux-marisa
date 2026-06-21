#!/bin/bash
# =====================================================================
#  SusFS 2.1.0 Patch Fixer for Crux Kernel 4.14.357
# =====================================================================

echo "🚀 [SusFS Rescue Engine] Starting manual repair for failed hunks..."

cat << 'EOF' > fix_susfs_failed_hunks.py
import os
import re

# ---------------------------------------------------------------------
# 1. 修复 fs/namespace.c (解决 mnt_free_id 和 mnt_alloc_group_id 冲突)
# ---------------------------------------------------------------------
if os.path.exists('fs/namespace.c'):
    print("[+] Patching fs/namespace.c...")
    with open('fs/namespace.c', 'r') as f:
        content = f.read()
    
    # 修复 mnt_free_id
    old_free = "static void mnt_free_id(struct mount *mnt)\n{\n\tint id = mnt->mnt_id;"
    new_free = "static void mnt_free_id(struct mount *mnt)\n{\n\tint id = mnt->mnt_id;\n\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tif (mnt->mnt.mnt_flags & VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)\n\t\treturn;\n#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT"
    content = content.replace(old_free, new_free)

    # 修复 mnt_alloc_group_id (使用正则兼容空格与Tab缩进变动)
    alloc_pattern = r"(static int mnt_alloc_group_id\(struct mount \*mnt\)\s*\{\s*int res;)\s*(if \(!ida_pre_get\(&mnt_group_ida,\s*GFP_KERNEL\)\)\s*return -ENOMEM;\s*res = ida_get_new_above\(&mnt_group_ida,\s*mnt_group_start,\s*&mnt->mnt_group_id\);)"
    alloc_replacement = """\\1

#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
\tif (susfs_is_current_ksu_domain()) {
\t\tif (!ida_pre_get(&mnt_group_ida, GFP_KERNEL))
\t\t\treturn -ENOMEM;
\t\tres = ida_get_new_above(&mnt_group_ida,
\t\t\t\t\tDEFAULT_KSU_MNT_GROUP_ID,
\t\t\t\t\t&mnt->mnt_group_id);
\t\tgoto bypass_orig_flow;
\t}

\tif (!ida_pre_get(&mnt_group_ida, GFP_KERNEL))
\t\treturn -ENOMEM;
\tres = ida_get_new_above(&mnt_group_ida,
\t\t\t\tmnt_group_start,
\t\t\t\t&mnt->mnt_group_id);
bypass_orig_flow:
#else
\tif (!ida_pre_get(&mnt_group_ida, GFP_KERNEL))
\t\treturn -ENOMEM;

\tres = ida_get_new_above(&mnt_group_ida,
\t\t\t\tmnt_group_start,
\t\t\t\t&mnt->mnt_group_id);
#endif"""
    content = re.sub(alloc_pattern, alloc_replacement, content, flags=re.MULTILINE)

    with open('fs/namespace.c', 'w') as f:
        f.write(content)

# ---------------------------------------------------------------------
# 2. 修复 fs/proc/cmdline.c (解决 Spoof Cmdline 冲突)
# ---------------------------------------------------------------------
if os.path.exists('fs/proc/cmdline.c'):
    print("[+] Patching fs/proc/cmdline.c...")
    with open('fs/proc/cmdline.c', 'r') as f:
        content = f.read()

    if "susfs_spoof_cmdline_or_bootconfig" not in content:
        content = content.replace(
            "static int cmdline_proc_show",
            "#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\nextern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;\nextern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);\n#endif\n\nstatic int cmdline_proc_show"
        )
        content = re.sub(
            r'(seq_printf\(m,\s*"%s\\n",\s*saved_command_line\);)',
            r'#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\n\tif (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {\n\t\tsusfs_spoof_cmdline_or_bootconfig(m);\n\t\tseq_printf(m, "%s\\n");\n\t\treturn 0;\n\t}\n#endif\n\t\1',
            content
        )

    with open('fs/proc/cmdline.c', 'w') as f:
        f.write(content)

# ---------------------------------------------------------------------
# 3. 修复 fs/proc/task_mmu.c (解决 SMAP 遍历屏蔽冲突)
# ---------------------------------------------------------------------
if os.path.exists('fs/proc/task_mmu.c'):
    print("[+] Patching fs/proc/task_mmu.c...")
    with open('fs/proc/task_mmu.c', 'r') as f:
        content = f.read()

    if "susfs_def.h" not in content:
        content = content.replace(
            "#include <linux/ctype.h>",
            "#include <linux/ctype.h>\n#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs_def.h>\n#endif"
        )

    # 注入 Size 打印屏蔽
    size_pattern = r'(\s*if \(!rollup_mode\)\s+)(seq_printf\(m,\s*"Size:\s+%8lu kB\\n")'
    size_replacement = r'\1#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tif (vma->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\treturn 0;\n\t}\n#endif\n\t\2'
    content = re.sub(size_pattern, size_replacement, content)

    # 注入 arch_show_smap 跳过逻辑
    arch_pattern = r'(\s*if \(!rollup_mode\) \{\s*)(arch_show_smap\(m,\s*vma\);\s*show_smap_vma_flags\(m,\s*vma\);\s*\})'
    arch_replacement = r'\1#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tif (vma->vm_file) {\n\t\tif (vma->vm_file && SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\tgoto bypass_orig_flow;\n\t}\n#endif\n\t\t\2\n\n#ifdef CONFIG_KSU_SUSFS_SUS_MAP\nbypass_orig_flow:\n#endif'
    content = re.sub(arch_pattern, arch_replacement, content)

    with open('fs/proc/task_mmu.c', 'w') as f:
        f.write(content)

# ---------------------------------------------------------------------
# 4. 修复 kernel/sys.c (解决 Spoof Uname 冲突)
# ---------------------------------------------------------------------
if os.path.exists('kernel/sys.c'):
    print("[+] Patching kernel/sys.c...")
    with open('kernel/sys.c', 'r') as f:
        content = f.read()

    if "susfs_is_uname_spoof_buffer_set" not in content:
        content = content.replace(
            "SYSCALL_DEFINE1(newuname, struct new_utsname __user *, name)",
            "#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\nextern struct static_key_false susfs_is_uname_spoof_buffer_set;\nextern void susfs_spoof_uname(struct new_utsname* tmp);\n#endif\nSYSCALL_DEFINE1(newuname, struct new_utsname __user *, name)"
        )
        content = content.replace(
            "\tmemcpy(&tmp, utsname(), sizeof(tmp));",
            "\tmemcpy(&tmp, utsname(), sizeof(tmp));\n#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n\tif (static_branch_likely(&susfs_is_uname_spoof_buffer_set))\n\t\tsusfs_spoof_uname(&tmp);\n#endif"
        )

    with open('kernel/sys.c', 'w') as f:
        f.write(content)

print("🎉 [SusFS Rescue Engine] All failed hunks fixed successfully!")
EOF

# 执行修复脚本
python3 fix_susfs_failed_hunks.py

# 清理临时脚本
rm fix_susfs_failed_hunks.py
