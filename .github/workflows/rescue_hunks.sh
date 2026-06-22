#!/bin/bash
# =====================================================================
# 🚀 SusFS 2.1.0 Total Patch Fixer (ASCII Escape-Safe Edition)
# 场景：GitHub Actions 自动化流水线 (全量、零污染、纯 BASH + AWK)
# 特性：全面采用 ASCII 码及双引号替换脆弱的单引号转义，彻底解决编译阻断
# =====================================================================

set -e

echo "🚀 [SusFS Rescue Engine] Starting ASCII safe dual-function rewrite..."

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
# 3. 修复 fs/proc/task_mmu.c (对 show_smap 与 show_smaps_rollup 全量重写，安全转义)
# ---------------------------------------------------------------------
TASK_MMU_FILE="fs/proc/task_mmu.c"
if [ -f "$TASK_MMU_FILE" ]; then
    echo "[+] Patching $TASK_MMU_FILE (Injecting clear ASCII rewritten show_smap and rollup)..."
    
    awk '
    BEGIN { 
        header_added = 0; 
        rewrite_smap = 0; 
        rewrite_rollup = 0;
    }

    # 头文件注入
    /#include <linux\/ctype\.h>/ && !header_added {
        print $0
        print "#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)"
        print "#include <linux/susfs_def.h>"
        print "#endif"
        header_added = 1
        next
    }

    # 拦截并重写第一个目标函数：show_smap
    /static int show_smap\(struct seq_file \*m, void \*v\)/, /^}/ {
        if (!rewrite_smap) {
            print "static int show_smap(struct seq_file *m, void *v)"
            print "{"
            print "\tstruct vm_area_struct *vma = v;"
            print "\tstruct mem_size_stats mss;"
            print ""
            print "\tmemset(&mss, 0, sizeof(mss));"
            print ""
            print "#ifdef CONFIG_KSU_SUSFS_SUS_MAP"
            print "\tif (vma->vm_file) {"
            print "\t\tstruct inode *inode = file_inode(vma->vm_file);"
            print "\t\tif (SUSFS_IS_INODE_SUS_MAP(inode)) {"
            print "\t\t\tshow_map_vma(m, vma);"
            print "\t\t\tSEQ_PUT_DEC(\"Size:           \", vma->vm_end - vma->vm_start);"
            print "\t\t\tSEQ_PUT_DEC(\" kB\\nKernelPageSize: \", vma_kernel_pagesize(vma));"
            print "\t\t\tSEQ_PUT_DEC(\" kB\\nMMUPageSize:    \", vma_mmu_pagesize(vma));"
            print "\t\t\tseq_puts(m, \" kB\\n\");"
            print "\t\t\t__show_smap(m, &mss, false);"
            print "\t\t\tif (arch_pkeys_enabled())"
            print "\t\t\t\t\tseq_printf(m, \"ProtectionKey:  %8u\\n\", vma_pkey(vma));"
            print "\t\t\tseq_puts(m, \"VmFlags: mr mw me\");"
            print "\t\t\tseq_putc(m, 10);" # 彻底解决多字节常量警告
            print "\t\t\tgoto bypass_orig_flow;"
            print "\t\t}"
            print "\t}"
            print "#endif"
            print ""
            print "\tsmap_gather_stats(vma, &mss);"
            print ""
            print "\tshow_map_vma(m, vma);"
            print "\tif (vma_get_anon_name(vma)) {"
            print "\t\tseq_puts(m, \"Name:           \");"
            print "\t\tseq_print_vma_name(m, vma);"
            print "\t\tseq_putc(m, 10);" # 彻底解决多字节常量警告
            print "\t}"
            print ""
            print "\tSEQ_PUT_DEC(\"Size:           \", vma->vm_end - vma->vm_start);"
            print "\tSEQ_PUT_DEC(\" kB\\nKernelPageSize: \", vma_kernel_pagesize(vma));"
            print "\tSEQ_PUT_DEC(\" kB\\nMMUPageSize:    \", vma_mmu_pagesize(vma));"
            print "\tseq_puts(m, \" kB\\n\");"
            print ""
            print "\t__show_smap(m, &mss, false);"
            print ""
            print "\tif (arch_pkeys_enabled())"
            print "\t\tseq_printf(m, \"ProtectionKey:  %8u\\n\", vma_pkey(vma));"
            print "\tshow_smap_vma_flags(m, vma);"
            print ""
            print "#ifdef CONFIG_KSU_SUSFS_SUS_MAP"
            print "bypass_orig_flow:"
            print "#endif"
            print "\tm_cache_vma(m, vma);"
            print ""
            print "\treturn 0;"
            print "}"
            rewrite_smap = 1
        }
        next
    }

    # 拦截并重写第二个目标函数：show_smaps_rollup
    /static int show_smaps_rollup\(struct seq_file \*m, void \*v\)/, /^}/ {
        if (!rewrite_rollup) {
            print "static int show_smaps_rollup(struct seq_file *m, void *v)"
            print "{"
            print "\tstruct proc_maps_private *priv = m->private;"
            print "\tstruct mem_size_stats mss;"
            print "\tstruct mm_struct *mm;"
            print "\tstruct vm_area_struct *vma;"
            print "\tunsigned long last_vma_end = 0;"
            print "\tint ret = 0;"
            print ""
            print "\tpriv->task = get_proc_task(priv->inode);"
            print "\tif (!priv->task)"
            print "\t\treturn -ESRCH;"
            print ""
            print "\tmm = priv->mm;"
            print "\tif (!mm || !mmget_not_zero(mm)) {"
            print "\t\tret = -ESRCH;"
            print "\t\tgoto out_put_task;"
            print "\t}"
            print ""
            print "\tmemset(&mss, 0, sizeof(mss));"
            print ""
            print "\tdown_read(&mm->mmap_sem);"
            print "\thold_task_mempolicy(priv);"
            print ""
            print "\tfor (vma = priv->mm->mmap; vma; vma = vma->vm_next) {"
            print "#ifdef CONFIG_KSU_SUSFS_SUS_MAP"
            print "\t\tif (vma->vm_file) {"
            print "\t\t\tstruct inode *inode = file_inode(vma->vm_file);"
            print "\t\t\tif (SUSFS_IS_INODE_SUS_MAP(inode)) {"
            print "\t\t\t\tmemset(&mss, 0, sizeof(mss));"
            print "\t\t\t\tgoto bypass_orig_flow;"
            print "\t\t\t}"
            print "\t\t}"
            print "#endif"
            print "\t\tsmap_gather_stats(vma, &mss);"
            print "#ifdef CONFIG_KSU_SUSFS_SUS_MAP"
            print "bypass_orig_flow:"
            print "#endif"
            print "\t\tlast_vma_end = vma->vm_end;"
            print "\t}"
            print ""
            print "\tshow_vma_header_prefix(m, priv->mm->mmap->vm_start,"
            print "\t\t\t       last_vma_end, 0, 0, 0, 0);"
            print "\tseq_pad(m, 32);" # 使用 ASCII 码 32 代替空格单引号，彻底解决编译错误
            print "\tseq_puts(m, \"[rollup]\\n\");"
            print ""
            print "\t__show_smap(m, &mss, true);"
            print ""
            print "\trelease_task_mempolicy(priv);"
            print "\tup_read(&mm->mmap_sem);"
            print "\tmmput(mm);"
            print ""
            print "out_put_task:"
            print "\tput_task_struct(priv->task);"
            print "\tpriv->task = NULL;"
            print ""
            print "\treturn ret;"
            print "}"
            rewrite_rollup = 1
        }
        next
    }

    # 保持对 open_redirect 补丁的潜在相容性
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


echo "🎉 [SusFS Rescue Engine] ASCII-Safe patch completed. Safe to compile now!"
