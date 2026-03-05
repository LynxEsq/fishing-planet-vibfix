// vibfix_hooks.c — IL2CPP API, Unity hooks, fishing inline hooks, hook installation

#include "vibfix.h"

// ============ IL2CPP API Pointers ============

il2cpp_domain_get_t api_domain_get = NULL;
il2cpp_domain_get_assemblies_t api_domain_get_assemblies = NULL;
il2cpp_assembly_get_image_t api_assembly_get_image = NULL;
il2cpp_class_from_name_t api_class_from_name = NULL;
il2cpp_class_get_method_from_name_t api_class_get_method_from_name = NULL;
il2cpp_class_get_methods_t api_class_get_methods = NULL;
il2cpp_method_get_name_t api_method_get_name = NULL;
il2cpp_resolve_icall_t api_resolve_icall = NULL;
il2cpp_add_internal_call_t api_add_internal_call = NULL;
il2cpp_class_get_fields_t api_class_get_fields = NULL;
il2cpp_field_get_name_t api_field_get_name = NULL;
il2cpp_field_get_offset_t api_field_get_offset = NULL;
il2cpp_method_get_param_count_t api_method_get_param_count = NULL;
il2cpp_image_get_class_count_t api_image_get_class_count = NULL;
il2cpp_image_get_class_t api_image_get_class = NULL;
il2cpp_class_get_name_t api_class_get_name = NULL;
il2cpp_class_get_namespace_t api_class_get_namespace = NULL;

// ============ Unity Hook Functions ============

#define RMBL_FOURCC 0x524D424C
#define DSBL_FOURCC 0x4453424C
#define ENBL_FOURCC 0x454E424C

volatile int g_vibration_disabled = 0;

static Il2CppMethodPointer orig_ioctl_native = NULL;
static Il2CppMethodPointer orig_ioctl = NULL;
typedef int64_t (*ioctl_fn)(int32_t deviceId, int32_t type, void *buffer, int32_t size);

static int hook_supports_vibration(void) {
    return 1;
}

static int64_t hook_ioctl(int32_t deviceId, int32_t type, void *buffer, int32_t size) {
    static int ioctl_count = 0;
    ioctl_count++;

    char fourcc[5] = {0};
    fourcc[0] = (type >> 24) & 0xFF;
    fourcc[1] = (type >> 16) & 0xFF;
    fourcc[2] = (type >> 8) & 0xFF;
    fourcc[3] = type & 0xFF;

    // Track unique IOCTL types — always log first occurrence with hex dump
    static uint32_t seen_types[64];
    static int seen_count = 0;
    int is_new_type = 1;
    for (int i = 0; i < seen_count; i++) {
        if (seen_types[i] == (uint32_t)type) { is_new_type = 0; break; }
    }
    if (is_new_type && seen_count < 64) {
        seen_types[seen_count++] = (uint32_t)type;
        viblog("IOCTL NEW TYPE: 0x%08X '%s' dev=%d size=%d (total types: %d)",
               type, fourcc, deviceId, size, seen_count);
        if (buffer && size > 0) {
            int dump_len = size < 64 ? size : 64;
            char hex[200] = {0};
            for (int i = 0; i < dump_len; i++)
                snprintf(hex + i*3, 4, "%02X ", ((uint8_t*)buffer)[i]);
            viblog("  hex[%d]: %s", size, hex);
        }
    }

    // Log non-RMBL IOCTL in verbose mode
    if (g_cfg.verbose_log && type != RMBL_FOURCC) {
        viblog("IOCTL #%d: 0x%08X '%s' dev=%d size=%d",
               ioctl_count, type, fourcc, deviceId, size);
    }

    if (type == RMBL_FOURCC && buffer) {
        float low = 0, high = 0;
        if (size >= 16) {
            low  = *(float *)((uint8_t *)buffer + 8);
            high = *(float *)((uint8_t *)buffer + 12);
        } else if (size >= 8) {
            uint32_t hdr = *(uint32_t *)buffer;
            if (hdr == RMBL_FOURCC) {
                low  = *(float *)((uint8_t *)buffer + 8);
                high = *(float *)((uint8_t *)buffer + 12);
            } else {
                low  = *(float *)((uint8_t *)buffer + 0);
                high = *(float *)((uint8_t *)buffer + 4);
            }
        }

        static int rmbl_n = 0;
        rmbl_n++;
        if (g_cfg.verbose_log) {
            char hex[200] = {0};
            int dump_len = size < 64 ? size : 64;
            for (int i = 0; i < dump_len; i++)
                snprintf(hex + i*3, 4, "%02X ", ((uint8_t*)buffer)[i]);
            viblog("RMBL #%d: low=%.4f high=%.4f dev=%d size=%d buf=[%s]",
                   rmbl_n, low, high, deviceId, size, hex);
        } else if (rmbl_n <= 20 || rmbl_n % 100 == 0) {
            viblog("RMBL #%d: low=%.3f high=%.3f dev=%d", rmbl_n, low, high, deviceId);
        }

        sendRumble(low, high);
        return (int64_t)(size > 0 ? size : 16);
    }

    // Track game vibration enable/disable (e.g. boat mode sends DSBL)
    if ((uint32_t)type == DSBL_FOURCC) {
        g_vibration_disabled = 1;
        outputRumble(0, 0, 0, 0);  // force stop on all motors
    } else if ((uint32_t)type == ENBL_FOURCC) {
        g_vibration_disabled = 0;
    }

    if (orig_ioctl_native) return ((ioctl_fn)orig_ioctl_native)(deviceId, type, buffer, size);
    if (orig_ioctl) return ((ioctl_fn)orig_ioctl)(deviceId, type, buffer, size);
    return -1;
}

// ============ IL2CPP Helpers ============

static void *find_gameassembly_handle(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "GameAssembly")) {
            viblog("Found GameAssembly at image #%u: %s", i, name);
            void *handle = dlopen(name, RTLD_NOLOAD | RTLD_NOW);
            if (handle) {
                viblog("dlopen OK: handle=%p", handle);
                return handle;
            } else {
                viblog("dlopen failed: %s", dlerror());
            }
        }
    }
    return NULL;
}

int resolve_il2cpp_api(void) {
    api_domain_get = (il2cpp_domain_get_t)dlsym(RTLD_DEFAULT, "il2cpp_domain_get");
    if (!api_domain_get) {
        void *ga = find_gameassembly_handle();
        if (!ga) return 0;
        api_domain_get = (il2cpp_domain_get_t)dlsym(ga, "il2cpp_domain_get");
        api_domain_get_assemblies = (il2cpp_domain_get_assemblies_t)dlsym(ga, "il2cpp_domain_get_assemblies");
        api_assembly_get_image = (il2cpp_assembly_get_image_t)dlsym(ga, "il2cpp_assembly_get_image");
        api_class_from_name = (il2cpp_class_from_name_t)dlsym(ga, "il2cpp_class_from_name");
        api_class_get_method_from_name = (il2cpp_class_get_method_from_name_t)dlsym(ga, "il2cpp_class_get_method_from_name");
        api_class_get_methods = (il2cpp_class_get_methods_t)dlsym(ga, "il2cpp_class_get_methods");
        api_method_get_name = (il2cpp_method_get_name_t)dlsym(ga, "il2cpp_method_get_name");
        api_resolve_icall = (il2cpp_resolve_icall_t)dlsym(ga, "il2cpp_resolve_icall");
        api_add_internal_call = (il2cpp_add_internal_call_t)dlsym(ga, "il2cpp_add_internal_call");
        api_class_get_fields = (il2cpp_class_get_fields_t)dlsym(ga, "il2cpp_class_get_fields");
        api_field_get_name = (il2cpp_field_get_name_t)dlsym(ga, "il2cpp_field_get_name");
        api_field_get_offset = (il2cpp_field_get_offset_t)dlsym(ga, "il2cpp_field_get_offset");
        api_method_get_param_count = (il2cpp_method_get_param_count_t)dlsym(ga, "il2cpp_method_get_param_count");
        api_image_get_class_count = (il2cpp_image_get_class_count_t)dlsym(ga, "il2cpp_image_get_class_count");
        api_image_get_class = (il2cpp_image_get_class_t)dlsym(ga, "il2cpp_image_get_class");
        api_class_get_name = (il2cpp_class_get_name_t)dlsym(ga, "il2cpp_class_get_name");
        api_class_get_namespace = (il2cpp_class_get_namespace_t)dlsym(ga, "il2cpp_class_get_namespace");
    }

    // RTLD_DEFAULT fallbacks
    if (!api_domain_get_assemblies) api_domain_get_assemblies = (il2cpp_domain_get_assemblies_t)dlsym(RTLD_DEFAULT, "il2cpp_domain_get_assemblies");
    if (!api_assembly_get_image) api_assembly_get_image = (il2cpp_assembly_get_image_t)dlsym(RTLD_DEFAULT, "il2cpp_assembly_get_image");
    if (!api_class_from_name) api_class_from_name = (il2cpp_class_from_name_t)dlsym(RTLD_DEFAULT, "il2cpp_class_from_name");
    if (!api_class_get_method_from_name) api_class_get_method_from_name = (il2cpp_class_get_method_from_name_t)dlsym(RTLD_DEFAULT, "il2cpp_class_get_method_from_name");
    if (!api_class_get_methods) api_class_get_methods = (il2cpp_class_get_methods_t)dlsym(RTLD_DEFAULT, "il2cpp_class_get_methods");
    if (!api_method_get_name) api_method_get_name = (il2cpp_method_get_name_t)dlsym(RTLD_DEFAULT, "il2cpp_method_get_name");
    if (!api_resolve_icall) api_resolve_icall = (il2cpp_resolve_icall_t)dlsym(RTLD_DEFAULT, "il2cpp_resolve_icall");
    if (!api_add_internal_call) api_add_internal_call = (il2cpp_add_internal_call_t)dlsym(RTLD_DEFAULT, "il2cpp_add_internal_call");
    if (!api_class_get_fields) api_class_get_fields = (il2cpp_class_get_fields_t)dlsym(RTLD_DEFAULT, "il2cpp_class_get_fields");
    if (!api_field_get_name) api_field_get_name = (il2cpp_field_get_name_t)dlsym(RTLD_DEFAULT, "il2cpp_field_get_name");
    if (!api_field_get_offset) api_field_get_offset = (il2cpp_field_get_offset_t)dlsym(RTLD_DEFAULT, "il2cpp_field_get_offset");
    if (!api_method_get_param_count) api_method_get_param_count = (il2cpp_method_get_param_count_t)dlsym(RTLD_DEFAULT, "il2cpp_method_get_param_count");
    if (!api_image_get_class_count) api_image_get_class_count = (il2cpp_image_get_class_count_t)dlsym(RTLD_DEFAULT, "il2cpp_image_get_class_count");
    if (!api_image_get_class) api_image_get_class = (il2cpp_image_get_class_t)dlsym(RTLD_DEFAULT, "il2cpp_image_get_class");
    if (!api_class_get_name) api_class_get_name = (il2cpp_class_get_name_t)dlsym(RTLD_DEFAULT, "il2cpp_class_get_name");
    if (!api_class_get_namespace) api_class_get_namespace = (il2cpp_class_get_namespace_t)dlsym(RTLD_DEFAULT, "il2cpp_class_get_namespace");

    if (!(api_domain_get && api_domain_get_assemblies && api_assembly_get_image &&
          api_class_from_name && api_class_get_method_from_name && api_resolve_icall))
        return 0;

    // Verify runtime is actually initialized — symbols resolve before data is ready,
    // calling find_class too early crashes inside GameAssembly (KERN_INVALID_ADDRESS).
    Il2CppDomain *domain = api_domain_get();
    if (!domain) return 0;

    size_t asm_count = 0;
    Il2CppAssembly **assemblies = api_domain_get_assemblies(domain, &asm_count);
    if (!assemblies || asm_count == 0) return 0;

    // Verify that at least one assembly has a valid image with populated class tables.
    // Images can exist before their metadata is loaded — class_from_name on an
    // empty image dereferences uninitialized pointers (KERN_INVALID_ADDRESS 0x135).
    int has_classes = 0;
    for (size_t i = 0; i < asm_count; i++) {
        Il2CppImage *img = api_assembly_get_image(assemblies[i]);
        if (!img) continue;
        if (api_image_get_class_count) {
            size_t class_count = api_image_get_class_count(img);
            if (class_count > 0) { has_classes = 1; break; }
        } else {
            // No class count API — at least verify image pointer is valid
            has_classes = 1;
            break;
        }
    }
    if (!has_classes) return 0;

    return 1;
}

Il2CppClass* find_class(const char *ns, const char *name) {
    Il2CppDomain *domain = api_domain_get();
    if (!domain) return NULL;

    size_t count = 0;
    Il2CppAssembly **assemblies = api_domain_get_assemblies(domain, &count);

    for (size_t i = 0; i < count; i++) {
        Il2CppImage *image = api_assembly_get_image(assemblies[i]);
        if (!image) continue;
        Il2CppClass *klass = api_class_from_name(image, ns, name);
        if (klass) return klass;
    }
    return NULL;
}

void patch_method_pointer(MethodInfo *method, void *new_func, void **save_orig) {
    if (!method) return;
    if (save_orig) *save_orig = method->methodPointer;
    method->methodPointer = new_func;
}

// Scan __DATA for cached icall pointers and replace them
int scan_image_data(const char *image_substr,
                    uintptr_t find_val, uintptr_t replace_val) {
    uint32_t image_count = _dyld_image_count();
    for (uint32_t i = 0; i < image_count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name || !strstr(name, image_substr)) continue;

        const struct mach_header_64 *mh =
            (const struct mach_header_64 *)_dyld_get_image_header(i);
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        if (!mh || mh->magic != MH_MAGIC_64) continue;

        const uint8_t *lc_ptr = (const uint8_t *)(mh + 1);
        int total = 0;

        for (uint32_t j = 0; j < mh->ncmds; j++) {
            const struct load_command *lc = (const struct load_command *)lc_ptr;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc_ptr;
                if (strcmp(seg->segname, "__DATA") == 0 || strcmp(seg->segname, "__DATA_DIRTY") == 0) {
                    uintptr_t *start = (uintptr_t *)(seg->vmaddr + slide);
                    size_t nwords = (size_t)seg->vmsize / sizeof(uintptr_t);
                    for (size_t k = 0; k < nwords; k++) {
                        if (start[k] == find_val) { start[k] = replace_val; total++; }
                    }
                }
            }
            lc_ptr += lc->cmdsize;
        }
        return total;
    }
    return 0;
}

// ============ ARM64 Inline Hook Engine ============
// Used for fishing hooks on IL2CPP methods.
// Apple Silicon enforces W^X (no page can be both writable and executable).
// Trampoline: allocate RW, write code, then switch to RX.
// Target patch: use mach_vm_remap to get a writable mapping of the code page.

#include <libkern/OSCacheControl.h>
#include <mach/mach_vm.h>

#define TRAMPOLINE_SIZE 32   // 16 bytes saved instructions + 16 bytes jump-back
#define HOOK_PATCH_SIZE 16   // 4 ARM64 instructions overwritten at target
#define PAGE_SIZE_16K 0x4000 // Apple Silicon page size

static uint8_t *g_trampoline_pool = NULL;
static int g_trampoline_next = 0;
#define MAX_TRAMPOLINES 16

static uint8_t *alloc_trampoline(void) {
    if (!g_trampoline_pool) {
        // Allocate as RW (will switch to RX after writing)
        vm_size_t pool_size = MAX_TRAMPOLINES * TRAMPOLINE_SIZE;
        // Round up to page size
        pool_size = (pool_size + PAGE_SIZE_16K - 1) & ~(PAGE_SIZE_16K - 1);
        mach_vm_address_t addr = 0;
        kern_return_t kr = mach_vm_allocate(mach_task_self(), &addr, pool_size, VM_FLAGS_ANYWHERE);
        if (kr != KERN_SUCCESS) {
            viblog("trampoline alloc failed: %d", kr);
            return NULL;
        }
        // Leave as RW — will protect as RX after each trampoline is written
        g_trampoline_pool = (uint8_t *)addr;
        viblog("trampoline pool at %p (RW)", g_trampoline_pool);
    }
    if (g_trampoline_next >= MAX_TRAMPOLINES) return NULL;
    uint8_t *t = g_trampoline_pool + g_trampoline_next * TRAMPOLINE_SIZE;
    g_trampoline_next++;
    return t;
}

// Finalize trampoline pool: switch from RW to RX
static void finalize_trampolines(void) {
    if (!g_trampoline_pool || g_trampoline_next == 0) return;
    vm_size_t pool_size = MAX_TRAMPOLINES * TRAMPOLINE_SIZE;
    pool_size = (pool_size + PAGE_SIZE_16K - 1) & ~(PAGE_SIZE_16K - 1);
    sys_icache_invalidate(g_trampoline_pool, pool_size);
    kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)g_trampoline_pool,
                                  pool_size, 0, VM_PROT_READ | VM_PROT_EXECUTE);
    viblog("trampoline pool → RX: %s", kr == KERN_SUCCESS ? "ok" : "FAILED");
}

// Write ARM64 absolute branch: LDR X16, [PC, #8]; BR X16; .quad addr
static void write_abs_jump(uint8_t *dst, void *target) {
    uint32_t *code = (uint32_t *)dst;
    code[0] = 0x58000050;  // LDR X16, [PC, #8]
    code[1] = 0xD61F0200;  // BR X16
    *(uint64_t *)(code + 2) = (uint64_t)target;
}

// Get a writable mapping of a code page via mach_vm_remap
static uint8_t *remap_page_writable(uintptr_t target_page) {
    mach_vm_address_t remap_addr = 0;
    vm_prot_t cur_prot, max_prot;
    kern_return_t kr = mach_vm_remap(mach_task_self(), &remap_addr, PAGE_SIZE_16K, 0,
                                      VM_FLAGS_ANYWHERE,
                                      mach_task_self(), (mach_vm_address_t)target_page,
                                      FALSE, &cur_prot, &max_prot, VM_INHERIT_NONE);
    if (kr != KERN_SUCCESS) {
        viblog("mach_vm_remap failed for page %p: %d", (void *)target_page, kr);
        return NULL;
    }
    // Make the remapped page writable
    kr = vm_protect(mach_task_self(), (vm_address_t)remap_addr, PAGE_SIZE_16K, 0,
                    VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        viblog("remap vm_protect RW failed: %d", kr);
        mach_vm_deallocate(mach_task_self(), remap_addr, PAGE_SIZE_16K);
        return NULL;
    }
    return (uint8_t *)remap_addr;
}

// Install inline hook using mach_vm_remap for code patching
static int install_inline_hook(void *target, void *hook, void **orig_out) {
    uint8_t *func = (uint8_t *)target;

    // Safety check: ARM64 PC-relative instructions cannot be safely copied to a
    // trampoline at a different address unless their branch target stays within
    // the copied region [0, HOOK_PATCH_SIZE].
    //
    // Rules:
    //   ADRP, ADR, BL, LDR-literal — always unsafe (absolute address computation)
    //   B / B.cond / CBZ / CBNZ / TBZ / TBNZ — unsafe only if branch target
    //     falls outside [0, HOOK_PATCH_SIZE] relative to function start
    for (int i = 0; i < HOOK_PATCH_SIZE; i += 4) {
        uint32_t insn;
        memcpy(&insn, func + i, 4);

        // ADRP / ADR — always unsafe
        if ((insn & 0x1F000000) == 0x10000000) {
            viblog("inline hook: ADRP/ADR at +%d (0x%08X) in %p — skipping", i, insn, target);
            return -3;
        }
        // BL — always unsafe (call to relative address)
        if ((insn & 0xFC000000) == 0x94000000) {
            viblog("inline hook: BL at +%d (0x%08X) in %p — skipping", i, insn, target);
            return -3;
        }
        // LDR literal — always unsafe
        if ((insn & 0x3B000000) == 0x18000000) {
            viblog("inline hook: LDR-lit at +%d (0x%08X) in %p — skipping", i, insn, target);
            return -3;
        }

        // For conditional/relative branches: decode target and check it stays
        // within [0, HOOK_PATCH_SIZE] (target == HOOK_PATCH_SIZE means it lands
        // exactly on our jump-back, which is the same as the original intent).
        int32_t branch_target = -1;

        if ((insn & 0xFC000000) == 0x14000000) {
            // B (unconditional): imm26 at bits[25:0]
            int32_t imm = (int32_t)(insn & 0x03FFFFFF);
            if (imm & 0x02000000) imm |= (int32_t)~0x03FFFFFF;
            branch_target = i + imm * 4;
        } else if ((insn & 0xFF000010) == 0x54000000) {
            // B.cond: imm19 at bits[23:5]
            int32_t imm = (int32_t)((insn >> 5) & 0x7FFFF);
            if (imm & 0x40000) imm |= (int32_t)~0x7FFFF;
            branch_target = i + imm * 4;
        } else if ((insn & 0x7E000000) == 0x34000000) {
            // CBZ / CBNZ: imm19 at bits[23:5]
            int32_t imm = (int32_t)((insn >> 5) & 0x7FFFF);
            if (imm & 0x40000) imm |= (int32_t)~0x7FFFF;
            branch_target = i + imm * 4;
        } else if ((insn & 0x7E000000) == 0x36000000) {
            // TBZ / TBNZ: imm14 at bits[18:5]
            int32_t imm = (int32_t)((insn >> 5) & 0x3FFF);
            if (imm & 0x2000) imm |= (int32_t)~0x3FFF;
            branch_target = i + imm * 4;
        }

        if (branch_target != -1 && (branch_target < 0 || branch_target > HOOK_PATCH_SIZE)) {
            viblog("inline hook: branch at +%d (0x%08X) → target +%d outside [0,%d] in %p — skipping",
                   i, insn, branch_target, HOOK_PATCH_SIZE, target);
            return -3;
        }
    }

    // Allocate trampoline (still RW at this point)
    uint8_t *tramp = alloc_trampoline();
    if (!tramp) {
        viblog("inline hook: no trampoline for %p", target);
        return -1;
    }

    // Copy first 16 bytes of original function to trampoline
    memcpy(tramp, func, HOOK_PATCH_SIZE);
    // Write jump-back: trampoline+16 → target+16
    write_abs_jump(tramp + HOOK_PATCH_SIZE, func + HOOK_PATCH_SIZE);

    // Save original via trampoline
    if (orig_out) *orig_out = (void *)tramp;

    // Get writable mapping of target code page via remap
    uintptr_t page = (uintptr_t)func & ~(PAGE_SIZE_16K - 1);
    uintptr_t offset = (uintptr_t)func - page;
    uint8_t *writable = remap_page_writable(page);
    if (!writable) {
        viblog("inline hook: remap failed for %p", target);
        return -2;
    }

    // Write jump to hook function via the writable mapping
    write_abs_jump(writable + offset, hook);

    // Flush instruction cache at the ORIGINAL address
    sys_icache_invalidate(func, HOOK_PATCH_SIZE);

    // Release the writable mapping (original page now has our patch)
    mach_vm_deallocate(mach_task_self(), (mach_vm_address_t)writable, PAGE_SIZE_16K);

    viblog("inline hook: %p → %p (trampoline=%p)", func, hook, tramp);
    return 0;
}

// ============ Hook Installation ============

static void install_fishing_hooks(void);

void install_hooks(void) {
    viblog("--- Installing hooks ---");

    // Hook SystemInfo.supportsVibration
    Il2CppClass *sysinfo = find_class("UnityEngine", "SystemInfo");
    if (sysinfo) {
        const char *names[] = {"get_supportsVibration", "SupportsVibration",
                               "get_SupportsVibration", "supportsVibration", NULL};
        for (int i = 0; names[i]; i++) {
            MethodInfo *m = api_class_get_method_from_name(sysinfo, names[i], 0);
            if (m) { patch_method_pointer(m, (void *)hook_supports_vibration, NULL); break; }
        }
    }

    // Overwrite icall map entries
    void *native_sv = NULL, *native_io = NULL;
    if (api_resolve_icall && api_add_internal_call) {
        const char *sv_names[] = {"UnityEngine.SystemInfo::get_supportsVibration",
                                   "UnityEngine.SystemInfo::SupportsVibration",
                                   "UnityEngine.SystemInfo::get_SupportsVibration", NULL};
        for (int i = 0; sv_names[i]; i++) {
            void *p = api_resolve_icall(sv_names[i]);
            if (p) {
                native_sv = p;
                api_add_internal_call(sv_names[i], (Il2CppMethodPointer)hook_supports_vibration);
                viblog("icall '%s' hooked", sv_names[i]);
            }
        }
        native_io = api_resolve_icall("UnityEngineInternal.Input.NativeInputSystem::IOCTL");
        if (native_io) {
            orig_ioctl_native = (Il2CppMethodPointer)native_io;
            api_add_internal_call("UnityEngineInternal.Input.NativeInputSystem::IOCTL",
                                  (Il2CppMethodPointer)hook_ioctl);
            viblog("icall IOCTL hooked (native=%p)", native_io);
        }
    }

    // Hook IOCTL via MethodInfo patch too
    Il2CppClass *nis = find_class("UnityEngineInternal.Input", "NativeInputSystem");
    if (nis) {
        MethodInfo *m = api_class_get_method_from_name(nis, "IOCTL", 4);
        if (!m) for (int i = 0; i <= 6; i++) { m = api_class_get_method_from_name(nis, "IOCTL", i); if (m) break; }
        if (m) patch_method_pointer(m, (void *)hook_ioctl, (void **)&orig_ioctl);
    }

    // Scan __DATA for cached pointers
    if (native_sv) {
        int n = scan_image_data("GameAssembly", (uintptr_t)native_sv, (uintptr_t)hook_supports_vibration);
        viblog("SupportsVibration cache: %d replacements", n);
    }
    if (native_io) {
        int n = scan_image_data("GameAssembly", (uintptr_t)native_io, (uintptr_t)hook_ioctl);
        viblog("IOCTL cache: %d replacements", n);
    }

    viblog("--- Hooks installed ---");

    // Install fishing hooks (line tension, fish force, rod force, haptic pulse)
    install_fishing_hooks();

    // Finalize inline hook trampolines — switch pool RW → RX
    finalize_trampolines();
}

// ============ Fishing Vibration Hooks ============
// Hook game methods to read line tension / fish force and drive vibration.
// IL2CPP instance method ABI: ReturnType func(void *this, MethodInfo *method)

// Globals for fishing state (read by hooks, consumed by fight vibration thread)
float g_line_tension = 0.0f;      // from GetLineTensionFactor (0..~32)
float g_fish_force = 0.0f;        // from Fish1stBehaviour.get_CurrentForce
float g_rod_force = 0.0f;         // from Rod1stBehaviour.GetRodForce (0..~103)
float g_reel_speed = 0.0f;        // from Reel1stBehaviour.get_CurrentRelativeSpeed (0..1)
float g_reel_force = 0.0f;        // from Reel1stBehaviour.get_CurrentForce (load on reel)
int   g_fishing_hooks_active = 0; // how many hooks installed
volatile uint32_t g_fish_force_tick = 0;  // incremented by get_CurrentForce hook
volatile int g_shutting_down = 0;         // set on process exit

// Original method pointers
typedef float (*il2cpp_float_getter_t)(void *thisptr, void *methodInfo);
typedef void (*il2cpp_void_method_t)(void *thisptr, void *methodInfo);

static il2cpp_float_getter_t orig_GetLineTensionFactor = NULL;
static il2cpp_float_getter_t orig_GetCurrentForce = NULL;
static il2cpp_float_getter_t orig_GetRodForce = NULL;
static il2cpp_void_method_t  orig_TriggerHapticPulse = NULL;
static il2cpp_float_getter_t orig_GetReelRelativeSpeed = NULL;
typedef void (*il2cpp_void_fn_t)(void *thisptr, void *methodInfo);
static il2cpp_void_fn_t orig_CalculateAppliedForce = NULL;

// --- Hook: Line1stBehaviour.GetLineTensionFactor ---
static float hook_GetLineTensionFactor(void *thisptr, void *methodInfo) {
    float val = orig_GetLineTensionFactor(thisptr, methodInfo);
    g_line_tension = val;

    static int count = 0;
    count++;
    if (count <= 50 || count % 200 == 0)
        viblog("[FISH] LineTension=%.4f (#%d)", val, count);
    return val;
}

// --- Hook: IFishController.get_CurrentForce ---
static float hook_GetCurrentForce(void *thisptr, void *methodInfo) {
    float val = orig_GetCurrentForce(thisptr, methodInfo);
    g_fish_force = val;
    g_fish_force_tick++;

    static int count = 0;
    count++;
    if (count <= 50 || count % 200 == 0)
        viblog("[FISH] FishForce=%.4f (#%d)", val, count);
    return val;
}

// --- Hook: Rod1stBehaviour.GetRodForce ---
static float hook_GetRodForce(void *thisptr, void *methodInfo) {
    float val = orig_GetRodForce(thisptr, methodInfo);
    g_rod_force = val;

    static int count = 0;
    count++;
    if (count <= 50 || count % 200 == 0)
        viblog("[FISH] RodForce=%.4f (#%d)", val, count);
    return val;
}

// --- Hook: Reel1stBehaviour.get_CurrentRelativeSpeed ---
static float hook_GetReelRelativeSpeed(void *thisptr, void *methodInfo) {
    float val = orig_GetReelRelativeSpeed(thisptr, methodInfo);
    g_reel_speed = val;

    static int count = 0;
    count++;
    if (count <= 50 || count % 500 == 0)
        viblog("[REEL] RelativeSpeed=%.4f (#%d)", val, count);
    return val;
}

// --- Hook: Reel1stBehaviour.CalculateAppliedForce ---
// Non-virtual computation method — starts with STP x29/x30, safe to copy.
// Called every frame during fishing. Reads reel state from backing fields:
//   0xa0 — <IsReeling>k__BackingField   (bool / uint8_t)
//   0xac — currentReelSpeedSection      (int32_t, 0 = stopped .. 3+ = fast)
//   0xb4 — <AppliedForce>k__BackingField (float, resistance force on handle)
static void hook_CalculateAppliedForce(void *thisptr, void *methodInfo) {
    orig_CalculateAppliedForce(thisptr, methodInfo);  // compute first

    if (thisptr) {
        uint8_t is_reeling  = *((uint8_t  *)thisptr + 0xa0);
        int32_t speed_sect  = *((int32_t  *)((uint8_t *)thisptr + 0xac));
        float   applied     = *((float    *)((uint8_t *)thisptr + 0xb4));

        g_reel_force = applied;
        // Normalize section: typically 0–3, sometimes up to 5
        float spd = is_reeling ? (speed_sect / 4.0f) : 0.0f;
        if (spd > 1.0f) spd = 1.0f;
        g_reel_speed = spd;

        static int count = 0;
        count++;
        if (count <= 50 || count % 200 == 0)
            viblog("[REEL] applied=%.4f reeling=%d sect=%d speed=%.2f (#%d)",
                   applied, (int)is_reeling, speed_sect, spd, count);
    }
}

// --- Hook: Rod1stBehaviour.TriggerHapticPulseOnRod ---
static void hook_TriggerHapticPulse(void *thisptr, void *methodInfo) {
    static int count = 0;
    count++;
    viblog("[FISH] TriggerHapticPulse (#%d) tension=%.3f fishForce=%.3f rodForce=%.3f",
           count, g_line_tension, g_fish_force, g_rod_force);

    // Call original — this triggers the game's own RMBL vibration (BITE via IOCTL)
    if (orig_TriggerHapticPulse)
        orig_TriggerHapticPulse(thisptr, methodInfo);

    // Also send our own pulse using pulse_* config
    uint8_t mL  = (uint8_t)(g_cfg.pulse_left * 255.0f);
    uint8_t mR  = (uint8_t)(g_cfg.pulse_right * 255.0f);
    uint8_t mLT = (uint8_t)(g_cfg.pulse_trigger_left * 255.0f);
    uint8_t mRT = (uint8_t)(g_cfg.pulse_trigger_right * 255.0f);
    if (mL || mR || mLT || mRT) {
        outputRumble(mL, mR, mLT, mRT);
        // Auto-stop after 200ms — fight thread may not be active (e.g. trash/debris catch)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            outputRumble(0, 0, 0, 0);
        });
    }
}

// Helper: find method and return its native code address
static void *find_method_addr_ns(const char *ns, const char *class_name, const char *method_name, int arg_count) {
    Il2CppClass *klass = find_class(ns, class_name);
    if (!klass) return NULL;
    MethodInfo *m = api_class_get_method_from_name(klass, method_name, arg_count);
    if (m && m->methodPointer) return (void *)m->methodPointer;
    return NULL;
}

static void *find_method_addr(const char *class_name, const char *method_name, int arg_count) {
    return find_method_addr_ns("", class_name, method_name, arg_count);
}

// Scan all classes for methods matching keywords — discovery tool
static void scan_classes_for_keywords(const char **keywords, int num_keywords) {
    viblog("[SCAN] Starting class scan...");
    Il2CppDomain *domain = api_domain_get();
    if (!domain) { viblog("[SCAN] no domain"); return; }
    size_t asm_count = 0;
    Il2CppAssembly **assemblies = api_domain_get_assemblies(domain, &asm_count);
    if (!assemblies) { viblog("[SCAN] no assemblies"); return; }
    if (!api_image_get_class_count || !api_image_get_class) {
        viblog("[SCAN] missing class iteration API (count=%p get=%p)",
               (void*)api_image_get_class_count, (void*)api_image_get_class);
        return;
    }
    if (!api_class_get_name) { viblog("[SCAN] missing class_get_name"); return; }
    if (!api_class_get_methods || !api_method_get_name) {
        viblog("[SCAN] missing method iteration API");
        return;
    }

    viblog("[SCAN] Scanning %zu assemblies for keywords...", asm_count);
    int total_matches = 0;

    for (size_t i = 0; i < asm_count; i++) {
        Il2CppImage *img = api_assembly_get_image(assemblies[i]);
        if (!img) continue;
        size_t class_count = api_image_get_class_count(img);

        for (size_t c = 0; c < class_count; c++) {
            Il2CppClass *klass = api_image_get_class(img, c);
            if (!klass) continue;
            const char *cname = api_class_get_name(klass);
            if (!cname) continue;

            // Check if class name matches any keyword
            int class_match = 0;
            for (int k = 0; k < num_keywords; k++) {
                if (strcasestr(cname, keywords[k])) { class_match = 1; break; }
            }
            if (!class_match) continue;

            const char *ns = api_class_get_namespace ? api_class_get_namespace(klass) : "";
            viblog("[SCAN] Class: %s%s%s", ns && ns[0] ? ns : "", ns && ns[0] ? "." : "", cname);
            total_matches++;

            // Dump all methods
            void *iter = NULL;
            const MethodInfo *method;
            while ((method = api_class_get_methods(klass, &iter)) != NULL) {
                const char *mname = api_method_get_name(method);
                int params = api_method_get_param_count ? api_method_get_param_count(method) : -1;
                viblog("[SCAN]   method: %s(%d) @ %p", mname ? mname : "?", params,
                       method->methodPointer);
            }

            // Dump all fields
            if (api_class_get_fields && api_field_get_name) {
                void *fiter = NULL;
                Il2CppFieldInfo field;
                while ((field = api_class_get_fields(klass, &fiter)) != NULL) {
                    const char *fname = api_field_get_name(field);
                    size_t foff = api_field_get_offset ? api_field_get_offset(field) : 0;
                    viblog("[SCAN]   field: %s (offset=0x%zx)", fname ? fname : "?", foff);
                }
            }
        }
    }
    viblog("[SCAN] Done: %d matching classes found", total_matches);
}

static void install_fishing_hooks(void) {
    viblog("[FISH] --- Installing fishing hooks (inline) ---");
    int hooked = 0;

    // Line1stBehaviour.GetLineTensionFactor
    void *addr = find_method_addr("Line1stBehaviour", "GetLineTensionFactor", 0);
    if (addr) {
        if (install_inline_hook(addr, (void *)hook_GetLineTensionFactor,
                                (void **)&orig_GetLineTensionFactor) == 0) {
            viblog("[FISH] Hooked Line1stBehaviour.GetLineTensionFactor @ %p", addr);
            hooked++;
        }
    } else {
        viblog("[FISH] Line1stBehaviour.GetLineTensionFactor not found");
    }

    // Rod1stBehaviour.GetRodForce
    addr = find_method_addr("Rod1stBehaviour", "GetRodForce", 0);
    if (addr) {
        if (install_inline_hook(addr, (void *)hook_GetRodForce,
                                (void **)&orig_GetRodForce) == 0) {
            viblog("[FISH] Hooked Rod1stBehaviour.GetRodForce @ %p", addr);
            hooked++;
        }
    } else {
        viblog("[FISH] Rod1stBehaviour.GetRodForce not found");
    }

    // FishAI.Fish1stBehaviour.get_CurrentForce
    addr = find_method_addr_ns("FishAI", "Fish1stBehaviour", "get_CurrentForce", 0);
    if (addr) {
        if (install_inline_hook(addr, (void *)hook_GetCurrentForce,
                                (void **)&orig_GetCurrentForce) == 0) {
            viblog("[FISH] Hooked FishAI.Fish1stBehaviour.get_CurrentForce @ %p", addr);
            hooked++;
        }
    } else {
        viblog("[FISH] FishAI.Fish1stBehaviour.get_CurrentForce not found");
    }

    // NOTE: get_CurrentRelativeForce and get_IsFightingMode removed — too small for 16-byte
    // inline hook patch (only ~8 bytes each), overwrites adjacent functions and crashes.

    // Rod1stBehaviour.TriggerHapticPulseOnRod — try different arg counts
    for (int args = 0; args <= 2 && !orig_TriggerHapticPulse; args++) {
        addr = find_method_addr("Rod1stBehaviour", "TriggerHapticPulseOnRod", args);
        if (addr) {
            if (install_inline_hook(addr, (void *)hook_TriggerHapticPulse,
                                    (void **)&orig_TriggerHapticPulse) == 0) {
                viblog("[FISH] Hooked Rod1stBehaviour.TriggerHapticPulseOnRod(%d) @ %p", args, addr);
                hooked++;
            }
        }
    }
    // Also try on RodBehaviour
    if (!orig_TriggerHapticPulse) {
        for (int args = 0; args <= 2; args++) {
            addr = find_method_addr("RodBehaviour", "TriggerHapticPulseOnRod", args);
            if (addr) {
                if (install_inline_hook(addr, (void *)hook_TriggerHapticPulse,
                                        (void **)&orig_TriggerHapticPulse) == 0) {
                    viblog("[FISH] Hooked RodBehaviour.TriggerHapticPulseOnRod(%d) @ %p", args, addr);
                    hooked++;
                }
            }
        }
    }
    if (!orig_TriggerHapticPulse)
        viblog("[FISH] TriggerHapticPulseOnRod not found in any class");

    // Reel1stBehaviour.CalculateAppliedForce — non-virtual, starts with STP frame
    // Reads IsReeling/speedSection/AppliedForce fields from thisptr after calling original.
    addr = find_method_addr("Reel1stBehaviour", "CalculateAppliedForce", 0);
    if (addr) {
        if (install_inline_hook(addr, (void *)hook_CalculateAppliedForce,
                                (void **)&orig_CalculateAppliedForce) == 0) {
            viblog("[REEL] Hooked Reel1stBehaviour.CalculateAppliedForce @ %p", addr);
            hooked++;
        }
    } else {
        viblog("[REEL] Reel1stBehaviour.CalculateAppliedForce not found");
    }

    g_fishing_hooks_active = hooked;
    viblog("[FISH] --- %d fishing hooks installed ---", hooked);
}
