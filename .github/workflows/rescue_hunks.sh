#!/bin/bash
# =====================================================================
# 🚀 SusFS Rescue Engine (Fully Aligned Edition)
# 场景：GitHub Actions 自动化流水线
# 特性：严格匹配源码结构，补齐 fs/namei.c 及 fs/namespace.c 的真实逻辑
# =====================================================================

set -e

echo "🚀 [SusFS Rescue Engine] Running full-alignment patcher..."

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
# 3. 修复 fs/proc/task_mmu.c
# ---------------------------------------------------------------------
TASK_MMU_FILE="fs/proc/task_mmu.c"
if [ -f "$TASK_MMU_FILE" ]; then
    echo "[+] Patching $TASK_MMU_FILE..."
    
    awk '
    BEGIN { header_added = 0; }

    /#include <linux\/ctype\.h>/ && !header_added {
        print $0
        print "#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)"
        print "#include <linux/susfs_def.h>"
        print "#endif // #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)"
        header_added = 1
        next
    }

    { print }
    ' "$TASK_MMU_FILE" > "${TASK_MMU_FILE}.tmp" && mv "${TASK_MMU_FILE}.tmp" "$TASK_MMU_FILE"
fi

# ---------------------------------------------------------------------
# 4. 修复 fs/namei.c (精确匹配 do_o_path 与 path_openat)
# ---------------------------------------------------------------------
NAMEI_FILE="fs/namei.c"
if [ -f "$NAMEI_FILE" ]; then
    echo "[+] Patching $NAMEI_FILE..."
    
    awk '
    BEGIN { in_do_o_path = 0; in_path_openat = 0; }

    /* 匹配 do_o_path 开头 */
    /static int do_o_path\(struct nameidata \*nd, unsigned flags, struct file \*file\)/ {
        in_do_o_path = 1
        print $0
        next
    }

    in_do_o_path && /struct path path;/ {
        print "#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
        print "\tint old_dfd = nd->dfd;"
        print "\tstruct filename *fake_filename = NULL;"
        print "#endif"
        print $0
        next
    }

    in_do_o_path && /if \(!error\) \{/ {
        print $0
        print "#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
        print "\t\tif (old_dfd != -1 &&"
        print "\t\t\tSUSFS_IS_INODE_OPEN_REDIRECT_WITHOUT_UID_CHECK(path.dentry->d_inode))"
        print "\t\t{"
        print "\t\t\tfake_filename = susfs_open_redirect_spoof_do_sys_openat(path.dentry->d_inode);"
        print "\t\t\tif (fake_filename && !IS_ERR(fake_filename)) {"
        print "\t\t\t\tpath_put(&path);"
        print "\t\t\t\trestore_nameidata();"
        print "\t\t\t\tset_nameidata(nd, old_dfd, fake_filename);"
        print "\t\t\t\terror = path_lookupat(nd, flags, &path);"
        print "\t\t\t\tif (unlikely(error)) {"
        print "\t\t\t\t\tputname(fake_filename);"
        print "\t\t\t\t\treturn error;"
        print "\t\t\t\t}"
        print "\t\t\t}"
        print "\t\t}"
        print "#endif"
        next
    }

    in_do_o_path && /return error;/ {
        print "#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
        print "\tif (fake_filename && !IS_ERR(fake_filename))"
        print "\t\tputname(fake_filename);"
        print "#endif"
        print $0
        in_do_o_path = 0
        next
    }

    /* 匹配 path_openat 开头注入 */
    /static struct file \*path_openat\(struct nameidata \*nd,/ {
        in_path_openat = 1
        print $0
        next
    }

    in_path_openat && /const char \*s;/ {
        print "#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
        print "\tint old_dfd = nd->dfd;"
        print "\tstruct filename *fake_filename = NULL;"
        print "#endif"
        print $0
        in_path_openat = 0
        next
    }

    { print }
    ' "$NAMEI_FILE" > "${NAMEI_FILE}.tmp" && mv "${NAMEI_FILE}.tmp" "$NAMEI_FILE"
fi

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

echo "🎉 [SusFS Rescue Engine] Fully aligned and ready for pipeline build!"
