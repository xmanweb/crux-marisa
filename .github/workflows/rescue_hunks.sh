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
# 修复 fs/proc/task_mmu.c (仅清理 smap_gather_stats 脏块，透传 show_map_vma)
# ---------------------------------------------------------------------
TASK_MMU_FILE="fs/proc/task_mmu.c"
if [ -f "$TASK_MMU_FILE" ]; then
    echo "[+] Safely cleaning smap_gather_stats in $TASK_MMU_FILE..."
    awk '
    BEGIN { 
        header_added = 0; 
        in_smap_gather_stats = 0;
        in_show_smap = 0; 
        smap_patched = 0;
        skip_bad_block = 0;
        skip_next_blank = 0;
    }

    /* 0. 吞掉清除脏块后紧跟的多余空行 */
    skip_next_blank && NF == 0 { skip_next_blank = 0; next }
    skip_next_blank { skip_next_blank = 0 }

    /* 1. 确保头文件注入（如已存在则不重复添加） */
    /#include <linux\/ctype\.h>/ && !header_added {
        print $0
        print "#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)"
        print "#include <linux/susfs_def.h>"
        print "#endif"
        header_added = 1
        next
    }

    /* 2. 严格限定在 smap_gather_stats 内部清理脏块 */
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
        skip_next_blank = 1 /* 吃掉残余空行 */
        next
    }
    skip_bad_block { next }

    in_smap_gather_stats && /^}/ {
        in_smap_gather_stats = 0
        print $0
        next
    }

    /* 3. 补全 show_smap (如果尚未 patch) */
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

    /* 其它所有代码（包括已修补正确的 show_map_vma）全部原样打印 */
    { print }
    ' "$TASK_MMU_FILE" > "${TASK_MMU_FILE}.tmp" && mv "${TASK_MMU_FILE}.tmp" "$TASK_MMU_FILE"
fi

# ---------------------------------------------------------------------
# 4. 修复 fs/namei.c (精确锁定 out: 标号)
# ---------------------------------------------------------------------
NAMEI_FILE="fs/namei.c"
if [ -f "$NAMEI_FILE" ]; then
    echo "[+] Patching $NAMEI_FILE..."
    awk '
    BEGIN { 
        in_do_tmpfile = 0;
        in_tmpfile_out = 0;
        tmpfile_out_injected = 0;

        in_do_o_path = 0; 
        do_o_path_var_added = 0;
        do_o_path_body_injected = 0;
        do_o_path_exit_injected = 0;

        in_path_openat = 0; 
        path_openat_var_added = 0;
    }

    /* === 1. do_tmpfile：严格仅在 out: 标号下的 path_put(&path) 之后注入 === */
    /static int do_tmpfile\(struct nameidata \*nd,/ {
        in_do_tmpfile = 1
        print $0
        next
    }

    in_do_tmpfile && /out:/ {
        in_tmpfile_out = 1
        print $0
        next
    }

    in_tmpfile_out && /path_put\(&path\);/ && !tmpfile_out_injected {
        print $0
        print "#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
        print "\tif (fake_filename && !IS_ERR(fake_filename))"
        print "\t\tputname(fake_filename);"
        print "#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
        tmpfile_out_injected = 1
        in_tmpfile_out = 0
        in_do_tmpfile = 0
        next
    }

    /* === 2. do_o_path === */
    /static int do_o_path\(struct nameidata \*nd,/ {
        in_do_o_path = 1
        print $0
        next
    }

    in_do_o_path && /struct path path;/ && !do_o_path_var_added {
        print "#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
        print "\tint old_dfd = nd->dfd;"
        print "\tstruct filename *fake_filename = NULL;"
        print "#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
        print $0
        do_o_path_var_added = 1
        next
    }

    in_do_o_path && /if \(!error\) \{/ && !do_o_path_body_injected {
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
        print "#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
        do_o_path_body_injected = 1
        next
    }

    in_do_o_path && do_o_path_body_injected && /return error;/ && !do_o_path_exit_injected {
        print "#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
        print "\tif (fake_filename && !IS_ERR(fake_filename))"
        print "\t\tputname(fake_filename);"
        print "#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
        print $0
        do_o_path_exit_injected = 1
        in_do_o_path = 0
        next
    }

    /* === 3. path_openat === */
    /static struct file \*path_openat\(struct nameidata \*nd,/ {
        in_path_openat = 1
        print $0
        next
    }

    in_path_openat && /const char \*s;/ && !path_openat_var_added {
        print "#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
        print "\tint old_dfd = nd->dfd;"
        print "\tstruct filename *fake_filename = NULL;"
        print "#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
        print $0
        path_openat_var_added = 1
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

echo "🎉 [SusFS Rescue Engine] Cleaned misapplied hunks & correctly inserted into show_smap!"
