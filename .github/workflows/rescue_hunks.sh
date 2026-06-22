#!/bin/bash
# =====================================================================
# 🚀 SusFS 2.1.0 Total Patch Fixer (Dual State-Machine Ultimate Edition)
# 场景：GitHub Actions 自动化流水线 (全量、零污染、纯 BASH + AWK)
# 特性：cmdline.c 与 sys.c 双状态机护航，彻底解决多同名点误触问题
# =====================================================================

set -e

echo "🚀 [SusFS Rescue Engine] Starting total dual state-machine patch integration..."

# ---------------------------------------------------------------------
# 1. 修复 fs/namespace.c (解决 3 处 Hunk FAILED，适配新版 IDA API)
# ---------------------------------------------------------------------
NAMESPACE_FILE="fs/namespace.c"
if [ -f "$NAMESPACE_FILE" ]; then
    echo "[+] Patching $NAMESPACE_FILE (Reconciling ID management with standard IDA API)..."
    
    awk '
    BEGIN { patched_free = 0; patched_alloc = 0; }

    # 全量拦截并重写 mnt_free_id 块
    /static void mnt_free_id\(struct mount \*mnt\)/, /^}/ {
        if (!patched_free) {
            print "static void mnt_free_id(struct mount *mnt)"
            print "{"
            print "#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT"
            print "\tif (mnt->mnt.mnt_flags & VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)"
            print "\t\treturn;"
            print "#endif"
            print ""
            print "\tida_free(&mnt_id_ida, mnt->mnt_id);"
            print "}"
            patched_free = 1
        }
        next
    }

    # 全量拦截并重写 mnt_alloc_group_id 块
    /static int mnt_alloc_group_id\(struct mount \*mnt\)/, /^}/ {
        if (!patched_alloc) {
            print "static int mnt_alloc_group_id(struct mount *mnt)"
            print "{"
            print "\tint res;"
            print ""
            print "#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT"
            print "\tif (susfs_is_current_ksu_domain()) {"
            print "\t\tres = ida_alloc_min(&mnt_group_ida, DEFAULT_KSU_MNT_GROUP_ID, GFP_KERNEL);"
            print "\t\tif (res < 0)"
            print "\t\t\treturn res;"
            print "\t\tmnt->mnt_group_id = res;"
            print "\t\treturn 0;"
            print "\t}"
            print "#endif"
            print ""
            print "\tres = ida_alloc_min(&mnt_group_ida, 1, GFP_KERNEL);"
            print "\tif (res < 0)"
            print "\t\treturn res;"
            print "\tmnt->mnt_group_id = res;"
            print "\treturn 0;"
            print "}"
            patched_alloc = 1
        }
        next
    }

    { print }
    ' "$NAMESPACE_FILE" > "${NAMESPACE_FILE}.tmp" && mv "${NAMESPACE_FILE}.tmp" "$NAMESPACE_FILE"
fi

# ---------------------------------------------------------------------
# 2. 修复 fs/proc/cmdline.c (状态机精确卡位：只在 cmdline_proc_show 内注入)
# ---------------------------------------------------------------------
CMDLINE_FILE="fs/proc/cmdline.c"
if [ -f "$CMDLINE_FILE" ]; then
    echo "[+] Patching $CMDLINE_FILE (Applying isolated cmdline spoof hook)..."
    
    awk '
    BEGIN { 
        header_added = 0; 
        in_cmdline_show = 0;  # 状态机：是否正处于 cmdline_proc_show 内
    }

    # 1. 匹配到目标函数入口，激活状态机，并在上方声明外部函数
    /static int cmdline_proc_show/ {
        if (!header_added) {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG"
            print "extern int susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);"
            print "#endif"
            print ""
            header_added = 1
        }
        in_cmdline_show = 1  # 开启安全过滤防线
    }

    # 2. 只有当处于函数体内，且首次撞见目标宏时，进行精准插桩
    /#ifdef CONFIG_INITRAMFS_IGNORE_SKIP_FLAG/ {
        if (in_cmdline_show == 1) {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG"
            print "\tif (!susfs_spoof_cmdline_or_bootconfig(m)) {"
            print "\t\tseq_putc(m, '\''\\n'\'');"
            print "\t\treturn 0;"
            print "\t}"
            print "#endif"
            in_cmdline_show = 0  # 注入达成，立刻关闭状态机，防止波及后面的 init 等函数
        }
    }

    # 3. 兜底清除状态
    /^}/ {
        in_cmdline_show = 0
    }

    { print }
    ' "$CMDLINE_FILE" > "${CMDLINE_FILE}.tmp" && mv "${CMDLINE_FILE}.tmp" "$CMDLINE_FILE"
fi

# ---------------------------------------------------------------------
# 3. 修复 fs/proc/task_mmu.c (解决 SMAP 遍历屏蔽冲突及空指针 Bug)
# ---------------------------------------------------------------------
TASK_MMU_FILE="fs/proc/task_mmu.c"
if [ -f "$TASK_MMU_FILE" ]; then
    echo "[+] Patching $TASK_MMU_FILE..."
    
    awk '
    /#include <linux\/ctype\.h>/ {
        print $0
        print "#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)"
        print "#include <linux/susfs_def.h>"
        print "#endif"
        next
    }
    /seq_printf\(m,\s*"Size:/ {
        print "#ifdef CONFIG_KSU_SUSFS_SUS_MAP"
        print "\tif (vma->vm_file) {"
        print "\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))"
        print "\t\t\treturn 0;"
        print "\t}"
        print "#endif"
        print $0
        next
    }
    /arch_show_smap\(m, vma\);/ {
        print "#ifdef CONFIG_KSU_SUSFS_SUS_MAP"
        print "\tif (vma->vm_file) {"
        print "\t\tif (vma->vm_file && SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))"
        print "\t\t\tgoto bypass_orig_flow;"
        print "\t}"
        print "#endif"
        print $0
        next
    }
    /show_smap_vma_flags\(m, vma\);/ {
        print $0
        print ""
        print "#ifdef CONFIG_KSU_SUSFS_SUS_MAP"
        print "bypass_orig_flow:"
        print "#endif"
        next
    }
    /extern int susfs_open_redirect_spoof_show_map_vma/ {
        sub(/char \*spoofed_name/, "char **spoofed_name")
    }
    /susfs_open_redirect_spoof_show_map_vma\(inode, &ino, &dev, spoofed_redirected_name\)/ {
        sub(/spoofed_redirected_name/, "\\&spoofed_redirected_name")
    }
    { print }
    ' "$TASK_MMU_FILE" > "${TASK_MMU_FILE}.tmp" && mv "${TASK_MMU_FILE}.tmp" "$TASK_MMU_FILE"
fi

# ---------------------------------------------------------------------
# 4. 修复 kernel/sys.c (状态机护航：只在 newuname 内进行 SusFS 2.0.0 注入)
# ---------------------------------------------------------------------
SYS_FILE="kernel/sys.c"
if [ -f "$SYS_FILE" ]; then
    echo "[+] Patching $SYS_FILE (Applying isolated newuname hook)..."
    
    awk '
    BEGIN { 
        header_added = 0; 
        in_newuname = 0;
    }

    # 1. 拦截 newuname 系统调用入口点
    /SYSCALL_DEFINE1\(newuname, struct new_utsname __user \*, name\)/ {
        if (!header_added) {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME"
            print "extern void susfs_spoof_uname(struct new_utsname* tmp);"
            print "#endif"
            header_added = 1
        }
        in_newuname = 1
    }

    # 2. 如果状态机处于激活状态，且撞到了 up_read(&uts_sem);
    /up_read\(&uts_sem\);/ {
        if (in_newuname == 1) {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME"
            print "\tsusfs_spoof_uname(&tmp);"
            print "#endif"
            in_newuname = 0
        }
    }

    /^}/ {
        in_newuname = 0
    }

    { print }
    ' "$SYS_FILE" > "${SYS_FILE}.tmp" && mv "${SYS_FILE}.tmp" "$SYS_FILE"
fi

echo "🎉 [SusFS Rescue Engine] Double state-machine patching complete! Ready to compile safely!"
