#!/bin/bash
# =====================================================================
# 🚀 SusFS Rescue Engine (Precise AST-Style Alignment)
# 场景：GitHub Actions 自动化流水线
# 修复：自动清除 task_mmu.c 中被模糊匹配打错位置的补丁并重新精准注入
# =====================================================================

set -e

echo "🚀 [SusFS Rescue Engine] Running AST-Style patch alignment..."

# ---------------------------------------------------------------------
# 1. 修复 fs/namespace.c (功能对齐 ida_alloc_min API)
# ---------------------------------------------------------------------
NAMESPACE_FILE="fs/namespace.c"
if [ -f "$NAMESPACE_FILE" ]; then
    echo "[+] Patching $NAMESPACE_FILE..."
    
    awk '
    BEGIN { patched_free = 0; patched_alloc = 0; }

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
# 2. 修复 fs/proc/cmdline.c
# ---------------------------------------------------------------------
CMDLINE_FILE="fs/proc/cmdline.c"
if [ -f "$CMDLINE_FILE" ]; then
    echo "[+] Patching $CMDLINE_FILE..."
    
    awk '
    BEGIN { header_added = 0; in_cmdline_show = 0; }

    /static int cmdline_proc_show/ {
        if (!header_added) {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG"
            print "extern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;"
            print "extern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);"
            print "#endif"
            print ""
            header_added = 1
        }
        in_cmdline_show = 1
    }

    /seq_printf\(m, "%s\\n", saved_command_line\);/ {
        if (in_cmdline_show) {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG"
            print "\tif (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {"
            print "\t\tsusfs_spoof_cmdline_or_bootconfig(m);"
            print "\t\tseq_putc(m, \047\\n\047);"
            print "\t\treturn 0;"
            print "\t}"
            print "#endif"
            in_cmdline_show = 0
        }
    }

    /^}/ { in_cmdline_show = 0 }

    { print }
    ' "$CMDLINE_FILE" > "${CMDLINE_FILE}.tmp" && mv "${CMDLINE_FILE}.tmp" "$CMDLINE_FILE"
fi

# ---------------------------------------------------------------------
# 修复 fs/proc/task_mmu.c (使用标准 AWK 语法修复注释报错)
# ---------------------------------------------------------------------
TASK_MMU_FILE="fs/proc/task_mmu.c"
if [ -f "$TASK_MMU_FILE" ]; then
    echo "[+] Repatching $TASK_MMU_FILE safely..."
    awk '
    BEGIN { 
        header_added = 0; 
        in_smap_gather_stats = 0;
        in_show_smap = 0; 
        smap_patched = 0;
        skip_bad_block = 0;
        skip_next_blank = 0;
    }

    # 0. 吞掉清除脏块后紧跟的多余空行
    skip_next_blank && NF == 0 { skip_next_blank = 0; next }
    skip_next_blank { skip_next_blank = 0 }

    # 1. 在第一个 #include 下方注入 SusFS 头文件
    /^#include / && !header_added {
        print $0
        print "#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)"
        print "#include <linux/susfs_def.h>"
        print "#endif"
        header_added = 1
        next
    }

    # 2. 严格锁定 smap_gather_stats 内部清理脏块
    /smap_gather_stats\(/ {
        in_smap_gather_stats = 1
        print $0
        next
    }

    in_smap_gather_stats && /#ifdef CONFIG_KSU_SUSFS_SUS_MAP/ {
        skip_bad_block = 1
        next
    }
    skip_bad_block && /#endif/ {
        skip_bad_block = 0
        skip_next_blank = 1 # 吃掉残余空行
        next
    }
    skip_bad_block { next }

    in_smap_gather_stats && /^}/ {
        in_smap_gather_stats = 0
        print $0
        next
    }

    # 3. show_smap 补全逻辑
    /static int show_smap\(struct seq_file \*m, void \*v/ {
        in_show_smap = 1
        print $0
        next
    }

    in_show_smap && /memset\(&mss, 0, sizeof\(mss\)\);/ && !smap_patched {
        print "#ifdef CONFIG_KSU_SUSFS_SUS_MAP"
        print "\tif (vma->vm_file && SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))"
        print "\t\treturn 0;"
        print "#endif"
        print ""
        smap_patched = 1
        in_show_smap = 0
        print $0
        next
    }

    in_show_smap && /^}/ {
        in_show_smap = 0
        print $0
        next
    }

    # 其余代码原样透传
    { print }
    ' "$TASK_MMU_FILE" > "${TASK_MMU_FILE}.tmp" && mv "${TASK_MMU_FILE}.tmp" "$TASK_MMU_FILE"
fi

# ---------------------------------------------------------------------
# 4. 修复 fs/super.c 
# ---------------------------------------------------------------------
TARGET_FILE="./fs/super.c"

if [ ! -f "$TARGET_FILE" ]; then
    echo "Error: Target file $TARGET_FILE does not exist!"
    exit 1
fi

awk '
BEGIN {
    state = 0
}

# 1. 匹配函数开头
/^int get_anon_bdev\(dev_t \*p\)/ {
    print $0
    state = 1
    next
}

# 2. 匹配 int dev; 并在其后插入包含完整 SUSFS 逻辑的代码段
state == 1 && /^[[:space:]]*int dev;/ {
    print $0
    print ""
    print "#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT"
    print "\tif (static_branch_unlikely(&susfs_is_sdcard_android_data_not_decrypted)) {"
    print "\t\tif (susfs_is_current_ksu_domain()) {"
    print "\t\t\tdev = ida_alloc_range(&unnamed_dev_ida, DEFAULT_KSU_MNT_MINOR_DEV,"
    print "\t\t\t\t\t     (1 << MINORBITS) - 1, GFP_ATOMIC);"
    print "\t\t\tif (dev == -ENOSPC)"
    print "\t\t\t\tdev = -EMFILE;"
    print "\t\t\tif (dev < 0)"
    print "\t\t\t\treturn dev;"
    print ""
    print "\t\t\t*p = MKDEV(0, dev);"
    print "\t\t\treturn 0;"
    print "\t\t}"
    print "\t}"
    print "#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT"
    state = 2
    next
}

# 其他所有行正常输出
{
    print $0
}
' "$TARGET_FILE" > "${TARGET_FILE}.tmp" && mv "${TARGET_FILE}.tmp" "$TARGET_FILE"

echo "Successfully patched $TARGET_FILE"

# ---------------------------------------------------------------------
# 5. 修复 kernel/sys.c
# ---------------------------------------------------------------------
SYS_FILE="kernel/sys.c"
if [ -f "$SYS_FILE" ]; then
    echo "[+] Patching $SYS_FILE..."
    
    awk '
    BEGIN { header_added = 0; in_newuname = 0; }

    /SYSCALL_DEFINE1\(newuname, struct new_utsname __user \*, name\)/ {
        if (!header_added) {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME"
            print "extern struct static_key_false susfs_is_uname_spoof_buffer_set;"
            print "extern void susfs_spoof_uname(struct new_utsname* tmp);"
            print "#endif"
            header_added = 1
        }
        in_newuname = 1
    }

    /memcpy\(&tmp, utsname\(\), sizeof\(tmp\)\);/ {
        print $0
        if (in_newuname == 1) {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME"
            print "\tif (static_branch_likely(&susfs_is_uname_spoof_buffer_set))"
            print "\t\tsusfs_spoof_uname(&tmp);"
            print "#endif"
            in_newuname = 0
        }
        next
    }

    /^}/ { in_newuname = 0 }

    { print }
    ' "$SYS_FILE" > "${SYS_FILE}.tmp" && mv "${SYS_FILE}.tmp" "$SYS_FILE"
fi

echo "🎉 [SusFS Rescue Engine] Cleaned misapplied hunks & correctly inserted into show_smap!"
