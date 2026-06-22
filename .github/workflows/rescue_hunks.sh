#!/bin/bash

# =====================================================================
# 🚀 SusFS 2.1.0 Patch Fixer for Crux Kernel 4.14.357 (Pure Shell Edition)
# =====================================================================

set -e

echo "🚀 [SusFS Rescue Engine] Starting pure bash repair and logic fix for failed hunks..."

# ---------------------------------------------------------------------
# 1. 修复 fs/namespace.c (适配全新 ida_alloc_min 与 ida_free)
# ---------------------------------------------------------------------
NAMESPACE_FILE="fs/namespace.c"
if [ -f "$NAMESPACE_FILE" ]; then
    echo "[+] Patching $NAMESPACE_FILE..."
    cp "$NAMESPACE_FILE" "${NAMESPACE_FILE}.bak"
    awk '
    # 重写 mnt_free_id
    /static void mnt_free_id\(struct mount \*mnt\)/, /^}/ {
        if ($0 ~ /static void mnt_free_id/) {
            print "static void mnt_free_id(struct mount *mnt)"
            print "{"
            print "#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT"
            print "\tif (mnt->mnt.mnt_flags & VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT)"
            print "\t\treturn;"
            print "#endif"
            print ""
            print "\tida_free(&mnt_id_ida, mnt->mnt_id);"
            print "}"
        }
        next
    }
    # 重写 mnt_alloc_group_id
    /static int mnt_alloc_group_id\(struct mount \*mnt\)/, /^}/ {
        if ($0 ~ /static int mnt_alloc_group_id/) {
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
        }
        next
    }
    { print }
    ' "$NAMESPACE_FILE" > "${NAMESPACE_FILE}.tmp" && mv "${NAMESPACE_FILE}.tmp" "$NAMESPACE_FILE"
fi

# ---------------------------------------------------------------------
# 2. 修复 fs/proc/cmdline.c (解决 Spoof Cmdline 冲突及格式化致命Bug)
# ---------------------------------------------------------------------
CMDLINE_FILE="fs/proc/cmdline.c"
if [ -f "$CMDLINE_FILE" ]; then
    echo "[+] Patching $CMDLINE_FILE..."
    if ! grep -q "susfs_spoof_cmdline_or_bootconfig" "$CMDLINE_FILE"; then
        cp "$CMDLINE_FILE" "${CMDLINE_FILE}.bak"
        awk '
        /static int cmdline_proc_show/ && !header_added {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG"
            print "extern struct static_key_false susfs_is_fake_cmdline_or_bootconfig_buffer_set;"
            print "extern void susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);"
            print "#endif\n"
            header_added = 1
        }
        /seq_printf\(m,\s*"%s\\n",\s*saved_command_line\);/ {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG"
            print "\tif (static_branch_likely(&susfs_is_fake_cmdline_or_bootconfig_buffer_set)) {"
            print "\t\tsusfs_spoof_cmdline_or_bootconfig(m);"
            print "\t\treturn 0;"
            print "\t}"
            print "#endif"
            print $0
            next
        }
        { print }
        ' "$CMDLINE_FILE" > "${CMDLINE_FILE}.tmp" && mv "${CMDLINE_FILE}.tmp" "$CMDLINE_FILE"
    fi
fi

# ---------------------------------------------------------------------
# 3. 修复 fs/proc/task_mmu.c (解决 SMAP 遍历屏蔽冲突及空指针 Bug)
# ---------------------------------------------------------------------
TASK_MMU_FILE="fs/proc/task_mmu.c"
if [ -f "$TASK_MMU_FILE" ]; then
    echo "[+] Patching $TASK_MMU_FILE..."
    if ! grep -q "susfs_def.h" "$TASK_MMU_FILE"; then
        cp "$TASK_MMU_FILE" "${TASK_MMU_FILE}.bak"
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
        # 修复 susfs_open_redirect_spoof_show_map_vma 指针崩溃与内存泄漏
        /extern int susfs_open_redirect_spoof_show_map_vma/ {
            sub(/char \*spoofed_name/, "char **spoofed_name")
        }
        /susfs_open_redirect_spoof_show_map_vma\(inode, &ino, &dev, spoofed_redirected_name\)/ {
            sub(/spoofed_redirected_name/, "\\&spoofed_redirected_name")
        }
        { print }
        ' "$TASK_MMU_FILE" > "${TASK_MMU_FILE}.tmp" && mv "${TASK_MMU_FILE}.tmp" "$TASK_MMU_FILE"
    fi
fi

# ---------------------------------------------------------------------
# 4. 修复 kernel/sys.c (解决 Spoof Uname 冲突及内核栈越界改写)
# ---------------------------------------------------------------------
SYS_FILE="kernel/sys.c"
if [ -f "$SYS_FILE" ]; then
    echo "[+] Patching $SYS_FILE..."
    if ! grep -q "susfs_is_uname_spoof_buffer_set" "$SYS_FILE"; then
        cp "$SYS_FILE" "${SYS_FILE}.bak"
        # 使用 AWK 状态机精准区分 newuname 和 olduname，完美替代长正则
        awk '
        BEGIN { in_old_uname = 0 }
        
        # 标记是否进入了老版本的 uname 系统调用
        /SYSCALL_DEFINE1\((old)?uname,/ { in_old_uname = 1 }
        /^}/ { in_old_uname = 0 }

        /SYSCALL_DEFINE1\(newuname, struct new_utsname __user \*, name\)/ {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME"
            print "extern struct static_key_false susfs_is_uname_spoof_buffer_set;"
            print "extern void susfs_spoof_uname(struct new_utsname* tmp);"
            print "#endif"
        }
        
        /memcpy\(&tmp, utsname\(\), sizeof\(tmp\)\);/ {
            print $0
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME"
            print "\tif (static_branch_likely(&susfs_is_uname_spoof_buffer_set)) {"
            
            if (in_old_uname) {
                # 针对 old_uname 增加安全保护壳，防止结构体大小不一致导致的栈溢出
                print "\t\tstruct new_utsname tmp_new;"
                print "\t\tmemcpy(&tmp_new, utsname(), sizeof(struct new_utsname));"
                print "\t\tsusfs_spoof_uname(&tmp_new);"
                print "\t\tmemcpy(&tmp, &tmp_new, sizeof(struct old_utsname));"
            } else {
                # newuname 正常逻辑
                print "\t\tsusfs_spoof_uname(&tmp);"
            }
            
            print "\t}"
            print "#endif"
            next
        }
        { print }
        ' "$SYS_FILE" > "${SYS_FILE}.tmp" && mv "${SYS_FILE}.tmp" "$SYS_FILE"
    fi
fi

echo "🎉 [SusFS Rescue Engine] All failed hunks fixed successfully! Zero Python dependencies!"
