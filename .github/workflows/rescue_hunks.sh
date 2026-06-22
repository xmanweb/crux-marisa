#!/bin/bash
# =====================================================================
# 🚀 SusFS 2.1.0 Total Patch Fixer (Function-Rewrite Ultimate Edition)
# 场景：GitHub Actions 自动化流水线 (全量、零污染、纯 BASH + AWK)
# 特性：namespace.c/cmdline.c/sys.c 状态机隔离，task_mmu.c 核心函数全量重写
# =====================================================================

set -e

echo "🚀 [SusFS Rescue Engine] Starting total precision patch integration..."

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
        in_cmdline_show = 0;
    }

    /static int cmdline_proc_show/ {
        if (!header_added) {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG"
            print "extern int susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);"
            print "#endif"
            print ""
            header_added = 1
        }
        in_cmdline_show = 1
    }

    /#ifdef CONFIG_INITRAMFS_IGNORE_SKIP_FLAG/ {
        if (in_cmdline_show == 1) {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG"
            print "\tif (!susfs_spoof_cmdline_or_bootconfig(m)) {"
            print "\t\tseq_putc(m, '\''\\n'\'');"
            print "\t\treturn 0;"
            print "\t}"
            print "#endif"
            in_cmdline_show = 0
        }
    }

    /^}/ {
        in_cmdline_show = 0
    }

    { print }
    ' "$CMDLINE_FILE" > "${CMDLINE_FILE}.tmp" && mv "${CMDLINE_FILE}.tmp" "$CMDLINE_FILE"
fi

# ---------------------------------------------------------------------
# 3. 修复 fs/proc/task_mmu.c (对 show_smap 函数体进行全量外科重写)
# ---------------------------------------------------------------------
TASK_MMU_FILE="fs/proc/task_mmu.c"
if [ -f "$TASK_MMU_FILE" ]; then
    echo "[+] Patching $TASK_MMU_FILE (Injecting full re-written show_smap)..."
    
    awk '
    BEGIN { 
        header_added = 0; 
        rewrite_smap = 0; 
    }

    # 1. 在合适的位置添加头文件声明
    /#include <linux\/ctype\.h>/ && !header_added {
        print $0
        print "#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)"
        print "#include <linux/susfs_def.h>"
        print "#endif"
        header_added = 1
        next
    }

    # 2. 匹配到旧的 static int show_smap 函数头部，开启拦截并注入你提供的新全量代码
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
            print "\t\t\tSEQ_PUT_DEC(\" kB\\\\nKernelPageSize: \", vma_kernel_pagesize(vma));"
            print "\t\t\tSEQ_PUT_DEC(\" kB\\\\nMMUPageSize:    \", vma_mmu_pagesize(vma));"
            print "\t\t\tseq_puts(m, \" kB\\\\n\");"
            print "\t\t\t__show_smap(m, &mss, false);"
            print "\t\t\tif (arch_pkeys_enabled())"
            print "\t\t\t\t\tseq_printf(m, \"ProtectionKey:  %8u\\\\n\", vma_pkey(vma));"
            print "\t\t\tseq_puts(m, \"VmFlags: mr mw me\");"
            print "\t\t\tseq_putc(m, '\''\\\\n'\'');"
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
            print "\t\tseq_putc(m, '\''\\\\n'\'');"
            print "\t}"
            print ""
            print "\tSEQ_PUT_DEC(\"Size:           \", vma->vm_end - vma->vm_start);"
            print "\tSEQ_PUT_DEC(\" kB\\\\nKernelPageSize: \", vma_kernel_pagesize(vma));"
            print "\tSEQ_PUT_DEC(\" kB\\\\nMMUPageSize:    \", vma_mmu_pagesize(vma));"
            print "\tseq_puts(m, \" kB\\\\n\");"
            print ""
            print "\t__show_smap(m, &mss, false);"
            print ""
            print "\tif (arch_pkeys_enabled())"
            print "\t\tseq_printf(m, \"ProtectionKey:  %8u\\\\n\", vma_pkey(vma));"
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
        next # 抛弃原本旧函数体内的所有旧行
    }

    # 3. 对同文件内可能存在的 open_redirect 修复补丁保留适配
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

    /SYSCALL_DEFINE1\(newuname, struct new_utsname __user \*, name\)/ {
        if (!header_added) {
            print "#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME"
            print "extern void susfs_spoof_uname(struct new_utsname* tmp);"
            print "#endif"
            header_added = 1
        }
        in_newuname = 1
    }

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

echo "🎉 [SusFS Rescue Engine] Master rewrite executed successfully! Pipeline is ready to build."
