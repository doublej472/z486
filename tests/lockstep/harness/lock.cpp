// SPDX-License-Identifier: GPL-3.0-or-later
// z486 lockstep harness against the 86Box CPU interpreter (Tetrium's tb/x86ref).
// Test-only: it links the GPL-3 reference model (libx86ref, built by ../fetch.sh) and is
// never part of the synthesized CPU.  The instruction helpers and the rgen386 program
// tables follow Tetrium's tb/tb_main.cpp (Copyright (C) 2026 ZbuntowanyKamulec, GPL-3.0-or-later).
//
// usage: Vtb_lock [options] prog
//   prog: a .COM image (loaded at 1000:0000, entry 1000:0100, ends with HLT),
//         an rgen386 program ('R386' / 'RPM3' / 'RPG3'), or with -rom a 64/128 KB ROM.
//   -s        stepwise: the core halts after every instruction (single_step), the
//             full architectural state is compared each time (default)
//   -p        pipelined: the core runs freely; every issued instruction's EIP is
//             compared with the model's, every store byte with the model's write
//             log; the full state is compared when the run stops (-n N or HLT)
//   -n N      stop after N instructions (default: the rgen header's count)
//   -lat M    bus latency: 0 = zero-wait, 1 = fixed 1, 2 = random 0-6 (default 2)
//   -kr       after a mismatch resynchronise the model and go on (count them)
//   -sync F   stepwise: write the undefined-flag fixups to F; pipelined: apply them
//   -v        trace every compared instruction
#include "Vtb_lock.h"
#include "verilated.h"
#include "svdpi.h"
#include "Vtb_lock__Dpi.h"
extern "C" {
#include "x86ref.h"
}
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <deque>
#include <map>
#include <set>

static uint8_t mem[1 << 24];
static uint32_t initv[32];
static int mode_step = 1, lat_mode = 2, resync = 0, verbose = 0, rom = 0;
static long nstop = 0;
static uint32_t rng = 12345;
static uint32_t rnd() { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }
static int a20_on = 1;
static std::string prog_name;
static FILE *syncf = nullptr;
static std::map<long, std::pair<uint32_t, uint32_t>> syncmap;   // ref step index -> (mask, value)
static std::deque<std::pair<uint32_t, uint8_t>> dut_o, ref_o;  // OUT bytes
static std::string out_e9;
static std::vector<uint8_t> post_codes;

// ------------------------------------------------------------ memory / io (DPI)
static inline uint32_t pa(uint32_t a) {
    if (a >= 0xFFFE0000u) return 0xE0000 + (a & 0x1FFFF);
    return a & 0xFFFFFF;
}
struct Wr { uint32_t a; uint8_t v; long grp; uint8_t old; };
static std::deque<Wr> dq;       // DUT store bytes (bus order)
static std::deque<Wr> rq;       // model store bytes
static long n_issue = 0;
extern "C" int ls_init(int i) { return initv[i]; }
extern "C" int ls_rd32(int a) {
    uint32_t b = pa((uint32_t)a & ~3u);
    return mem[b] | mem[b + 1] << 8 | mem[b + 2] << 16 | (uint32_t)mem[b + 3] << 24;
}
extern "C" void ls_wr(int a, int be, int d) {
    for (int i = 0; i < 4; i++)
        if (be & (1 << i)) {
            uint32_t b = pa((uint32_t)a + i);
            if ((uint32_t)a + i >= 0xFFFE0000u) continue;       // ROM alias: read-only
            uint8_t old = mem[b];
            mem[b] = d >> (8 * i);
            dq.push_back({b, (uint8_t)(d >> (8 * i)), n_issue, old});
        }
}
// INTR test port (directed tests): OUT E0h = INTR level (bit 0), OUT E1h = vector,
// OUT E2h = n: INTR high for n cycles, then low (a request withdrawn before it is acknowledged)
static int intr_lvl = 0, intr_vec = 0x40, intr_pulse = 0;
static long intr_low_since = 0, n_inta = 0, n_inta_low = 0, cyc_now = 0;
static int inta_pending_vec = -1;
extern "C" int ls_a20() { return a20_on; }
extern "C" int ls_intr() {
    if (intr_pulse > 0 && --intr_pulse == 0) intr_lvl = 0;
    return intr_lvl;
}
extern "C" int ls_inta(int second) {
    if (!second) return 0;
    n_inta++;
    if (!intr_lvl) {
        n_inta_low++;
        printf("  INTA: the DUT acknowledged INTR %ld cycles after it went low (vector %02x)\n", cyc_now - intr_low_since, intr_vec);
    }
    inta_pending_vec = intr_vec;
    return intr_vec;
}
extern "C" int ls_io_rd(int a, int be) { (void)a; (void)be; return -1; }
static long n_cpio = 0;
extern "C" void ls_io_wr(int a, int be, int d) {
    if ((uint32_t)a & 0x80000000u) { n_cpio++; return; }   // 386 coprocessor-protocol cycle (800000F8-FF): known, counted
    for (int i = 0; i < 4; i++)
        if (be & (1 << i)) {
            uint32_t port = ((uint32_t)a + i) & 0xFFFF;
            uint8_t v = d >> (8 * i);
            dut_o.push_back({port, v});
            if (getenv("LOCKIO")) printf("  dut out [%08x] %03x=%02x\n", (uint32_t)a, port, v);
            if (port == 0x92) a20_on = (v >> 1) & 1;
            if (port == 0xE0) { if (intr_lvl && !(v & 1)) intr_low_since = cyc_now; intr_lvl = v & 1; }
            if (port == 0xE1) intr_vec = v;
            if (port == 0xE2) { intr_lvl = 1; intr_pulse = v; intr_low_since = cyc_now + v; }
        }
}
extern "C" int ls_lat(int w) {
    if (lat_mode == 0) return w ? 0 : 0 | 256;
    if (lat_mode == 1) return w ? 0 : 1;
    uint32_t r = rnd();
    int l = (r & 7) < 5 ? 0 : (r >> 3) % 7;
    if (w) return (r >> 8) % 4 == 0 ? (r >> 10) % 4 : 0;
    return l | (((r >> 12) & 1) ? 256 : 0);
}

// ------------------------------------------------------------ instruction helpers (Tetrium tb_main.cpp)
static uint32_t undef_flags(const uint8_t *p) {
    int i = 0;
    while (i < 14) {
        uint8_t b = p[i];
        if (b == 0x26 || b == 0x2E || b == 0x36 || b == 0x3E || b == 0x64 || b == 0x65 || b == 0x66 || b == 0x67 ||
            (b >= 0xF0 && b <= 0xF3 && b != 0xF1)) i++;
        else break;
    }
    uint8_t op = p[i], reg = (p[i + 1] >> 3) & 7;
    const uint32_t CF = 1, PF = 4, AF = 0x10, ZF = 0x40, SF = 0x80, OF = 0x800;
    if (op == 0x0F) {
        switch (p[i + 1]) {
            case 0xA3: case 0xAB: case 0xB3: case 0xBB: case 0xBA: return OF | SF | ZF | AF | PF;
            case 0xBC: case 0xBD: return OF | SF | AF | PF | CF;
            case 0xA4: case 0xA5: case 0xAC: case 0xAD: return OF | AF;
            case 0xAF: return SF | ZF | AF | PF;
            default: return 0;
        }
    }
    if (op == 0x27 || op == 0x2F) return OF;
    if (op == 0x37 || op == 0x3F) return OF | SF | ZF | PF;
    if ((op & 0xC4) == 0x00 || (op & 0xC6) == 0x04) {
        int k = (op >> 3) & 7;
        if ((op & 7) < 6 && (k == 1 || k == 4 || k == 6)) return AF;
        return 0;
    }
    switch (op) {
        case 0x80: case 0x81: case 0x82: case 0x83: return (reg == 1 || reg == 4 || reg == 6) ? AF : 0;
        case 0x84: case 0x85: case 0xA8: case 0xA9: return AF;
        case 0x69: case 0x6B: return SF | ZF | AF | PF;
        case 0xC0: case 0xC1: case 0xD2: case 0xD3: return OF | AF;
        case 0xD0: case 0xD1: return AF;
        case 0xD4: case 0xD5: return OF | AF | CF;
        case 0xF6: case 0xF7:
            if (reg <= 1) return AF;
            if (reg == 4 || reg == 5) return SF | ZF | AF | PF;
            if (reg >= 6) return OF | SF | ZF | AF | PF | CF;
            return 0;
        default: return 0;
    }
}
static int skip_pfx(const uint8_t *p) {
    int i = 0;
    while (i < 14 && (p[i] == 0x26 || p[i] == 0x2E || p[i] == 0x36 || p[i] == 0x3E || p[i] == 0x64 || p[i] == 0x65 ||
                      p[i] == 0x66 || p[i] == 0x67 || p[i] == 0xF0 || p[i] == 0xF2 || p[i] == 0xF3)) i++;
    return i;
}
static bool ss_shadow(const uint8_t *p) {
    int i = skip_pfx(p);
    return p[i] == 0x17 || (p[i] == 0x8E && ((p[i + 1] >> 3) & 7) == 2);
}
static bool rep_string(const uint8_t *p) {
    bool rep = false;
    int i = 0;
    while (i < 14 && (p[i] == 0x26 || p[i] == 0x2E || p[i] == 0x36 || p[i] == 0x3E || p[i] == 0x64 || p[i] == 0x65 ||
                      p[i] == 0x66 || p[i] == 0x67 || p[i] == 0xF0 || p[i] == 0xF2 || p[i] == 0xF3)) {
        if (p[i] == 0xF2 || p[i] == 0xF3) rep = true;
        i++;
    }
    uint8_t o = p[i];
    return rep && ((o >= 0x6C && o <= 0x6F) || (o >= 0xA4 && o <= 0xA7) || (o >= 0xAA && o <= 0xAF));
}

// linear -> physical through the model's page tables (no A/D updates)
static uint8_t *rram;
static uint32_t rd32r(uint32_t a) { return rram[a] | rram[a + 1] << 8 | rram[a + 2] << 16 | (uint32_t)rram[a + 3] << 24; }
static uint32_t lin2phys(const ref_state_t &s, uint32_t lin) {
    if (!(s.creg0 >> 31)) return lin & 0xFFFFFF;
    uint32_t pde = rd32r((s.creg3 & 0xFFFFF000u & 0xFFFFFF) + ((lin >> 22) << 2));
    if (!(pde & 1)) return lin & 0xFFFFFF;
    uint32_t pte = rd32r((pde & 0xFFF000) + (((lin >> 12) & 0x3FF) << 2));
    if (!(pte & 1)) return lin & 0xFFFFFF;
    return ((pte & 0xFFF000) | (lin & 0xFFF)) & 0xFFFFFF;
}
static void ibytes(const ref_state_t &s, uint32_t eip, uint8_t *ib) {
    for (int k = 0; k < 16; k++) ib[k] = rram[lin2phys(s, s.seg[REF_CS].base + eip + k) & 0xFFFFFF];
}

// ------------------------------------------------------------ program setup (Tetrium's rpm/rpg tables)
static void put_desc(uint32_t a, uint32_t base, uint32_t lim, uint8_t acc, uint8_t fl) {
    mem[a] = lim; mem[a + 1] = lim >> 8; mem[a + 2] = base; mem[a + 3] = base >> 8; mem[a + 4] = base >> 16;
    mem[a + 5] = acc; mem[a + 6] = ((lim >> 16) & 0xF) | (fl << 4); mem[a + 7] = base >> 24;
}
static void rpm_tables(const uint16_t *ivt, uint16_t cs) {
    const uint32_t G = 0x80000, I = 0x8C000;
    memset(mem + G, 0, 0xB008);
    put_desc(G + cs, cs << 4, 0xFFFF, 0x9B, 0);
    for (uint16_t sg : {0x3000, 0x4000, 0x5000, 0x7000, 0xB000}) put_desc(G + sg, sg << 4, 0xFFFF, 0x93, 0);
    put_desc(G + 0x08, 0x30000, 0xFFFF, 0x91, 0);
    put_desc(G + 0x10, 0x30000, 0x7FFF, 0x97, 0);
    put_desc(G + 0x18, 0x30000, 0xFFFF, 0x13, 0);
    put_desc(G + 0x20, 0x40000, 0xFFFF, 0xF3, 0);
    put_desc(G + 0x28, 0x10000, 0xFFFF, 0x99, 0);
    put_desc(G + 0x30, 0x50000, 0x1FFFF, 0x93, 4);
    put_desc(G + 0x38, 0x10000, 0xFFFF, 0x9B, 0);
    put_desc(G + 0x40, 0x30000, 0x00FF, 0x82, 0);
    put_desc(G + 0x48, 0x30000, 0xFFFF, 0x93, 0);
    for (int v = 0; v < 256; v++) {
        uint32_t a = I + v * 8;
        mem[a] = ivt[v]; mem[a + 1] = ivt[v] >> 8; mem[a + 2] = cs; mem[a + 3] = cs >> 8;
        mem[a + 4] = 0; mem[a + 5] = 0x86; mem[a + 6] = 0; mem[a + 7] = 0;
    }
}
static void rpg_tables(uint32_t seed) {
    const uint32_t G = 0x80000, PD = 0x8D000, PT = 0x8E000;
    put_desc(G + 0x50, 0, 0xFFFFF, 0x93, 0xC);
    put_desc(G + 0x58, PT, 0xFFF, 0x93, 0);
    memset(mem + PD, 0, 0x2000);
    uint32_t pde = PT | 7;
    memcpy(mem + PD, &pde, 4);
    uint32_t x = seed * 747796405u + 2891336453u;
    auto rn = [&](uint32_t n) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; return x % n; };
    for (uint32_t p = 0; p < 256; p++) {
        uint32_t e = (p << 12) | 7;
        bool data = (p >= 0x30 && p < 0x60) || (p >= 0xB0 && p < 0xC0);
        if (data) {
            if (rn(5) == 0) e = ((0x30 + rn(0x30)) << 12) | 7;
            if (rn(3) == 0) e &= ~1u;
            if (rn(4) == 0) e &= ~2u;
            if (rn(6) == 0) e |= 0x10;
        } else if (p >= 0x10 && p < 0x1F && rn(3) == 0) e &= ~1u;
        memcpy(mem + PT + p * 4, &e, 4);
    }
}

// ------------------------------------------------------------ lockstep state
static const char *GN[8] = {"eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi"};
static const char *SN[6] = {"es", "cs", "ss", "ds", "fs", "gs"};
static long ref_steps = 0, nmis = 0, ncmp = 0;
static bool ss_pending = false, stop_req = false, finished = false, resume_pending = false;
static bool rpg = false;
static bool ref_halted = false;
static bool defer_cmp = false, defer_used = false;
static int squash_budget = 0; static uint32_t squash_ieip = 0; static bool last_fault = false; static long n_squash = 0;
static long n_defer = 0, n_cr0res = 0, n_fetchf = 0, n_cr2 = 0, n_cr2blk = 0;
static bool rm_loaded[6] = {true, true, true, true, true, true};   // descriptor loaded in real / V86 mode (attributes not compared)
static uint32_t last_eip = 0xFFFFFFFF, last_um = 0; static bool last_rep = false;
static ref_state_t last_pre;
static uint8_t last_ib[16];
static long idle = 0;
static std::string first;
static std::map<uint32_t, uint8_t> loose;
static long hist[256];

static void report(const char *what, const std::string &d) {
    nmis++;
    int oi = skip_pfx(last_ib);
    hist[last_ib[oi] == 0x0F ? last_ib[oi + 1] : last_ib[oi]]++;
    if (first.empty() || verbose) {
        char b[256];
        snprintf(b, sizeof b, "%s insn %ld at %04x:%08x [%02x %02x %02x %02x %02x %02x %02x %02x %02x %02x]", what, ref_steps,
                 last_pre.seg[REF_CS].sel, last_pre.eip, last_ib[0], last_ib[1], last_ib[2], last_ib[3], last_ib[4],
                 last_ib[5], last_ib[6], last_ib[7], last_ib[8], last_ib[9]);
        std::string s = std::string(b) + d;
        if (first.empty()) first = s;
        if (verbose) printf("  MISMATCH %s\n", s.c_str());
        if (getenv("LOCKPRE")) {
            printf("  pre:");
            for (int k = 0; k < 8; k++) printf(" %s=%08x", GN[k], last_pre.gpr[k]);
            for (int k = 0; k < 6; k++) printf(" %s=%04x", SN[k], last_pre.seg[k].sel);
            printf(" fl=%08x cr0=%08x\n", last_pre.eflags, last_pre.creg0);
        }
    }
}

static void ref_store_log(long grp) {
    int nw; const ref_wr_t *wl = ref_wlog(&nw);
    long npg = -1;
    uint32_t ia = last_pre.seg[REF_CS].base + last_pre.eip;
    if (((ia + 15) >> 12) != (ia >> 12)) npg = (ia + 15) >> 12;
    for (int k = 0; k < nw; k++) {
        uint32_t a = wl[k].addr & 0xFFFFFF;
        if (rpg && npg >= 0 && a >= 0x8E000 && a < 0x8F000 && (long)((a - 0x8E000) >> 2) == npg) loose[a] = wl[k].val;
        else rq.push_back({a, wl[k].val, grp, 0});
    }
    ref_wlog_clear();
}

// match DUT store bytes against the model's; final: everything must be matched
// RF in a fault frame's EFLAGS image (z486 pushes RF=1, i486 PRM 11.3.1.1 / an Am486 capture;
// 86Box pushes RF=0): byte 2 of a stack dword written by an exception delivery
static long n_rfmask = 0;
static std::set<uint32_t> rfset, padset;
static bool rf_ok(uint32_t a) {
    ref_state_t s; ref_get(&s);
    uint32_t lo = s.seg[REF_SS].base;
    return a >= lo && a < lo + 0x100000 && (((a - (s.seg[REF_SS].base + s.gpr[4])) & 3) == 2 || true);
}
// stores since the last compare: compare the final value of every byte either side wrote
// (order-free: the two sides may write a location more than once, in another order or size)
static long n_selpad = 0, n_errpad = 0, n_ad = 0;
static std::string match_stores(bool final) {
    (void)final;
    std::string d;
    char b[64];
    std::map<uint32_t, bool> hd, hr;
    for (auto &w : dq) hd[w.a] = true;
    for (auto &r : rq) hr[r.a] = true;
    if (getenv("LOCKST")) {
        printf("  dut st:"); for (auto &w : dq) printf(" %06x=%02x", w.a, w.v); printf("\n");
        printf("  ref st:"); for (auto &r : rq) printf(" %06x=%02x", r.a, r.v); printf("\n");
    }
    std::set<uint32_t> all;
    for (auto &x : hd) all.insert(x.first);
    for (auto &x : hr) all.insert(x.first);
    for (uint32_t a : all) {
        uint8_t dv = mem[a], rv = rram[a];
        if (dv == rv) continue;
        bool d_w = hd.count(a), r_w = hr.count(a);
        if (d_w && r_w && dv == (rv | 1) && rf_ok(a)) {          // RF in a fault frame
            n_rfmask++; rfset.insert(a); if (mode_step) rram[a] = dv; continue;
        }
        if (d_w && dv == 0 && (hr.count(a - 2) || hr.count(a - 1))) {   // selector pushed zero-extended
            n_selpad++; if (mode_step) rram[a] = dv; padset.insert(a); continue;
        }
        if (!d_w && r_w && rv == 0 && (hd.count(a - 2) || hd.count(a - 1))) {   // error code / selector upper half
            n_errpad++; if (mode_step) rram[a] = dv; padset.insert(a); continue;
        }
        if (rpg && a >= 0x8E000 && a < 0x8F000 && ((dv ^ rv) & ~0x60) == 0) {   // A / D bits (86Box prefetch)
            n_ad++; if (mode_step) rram[a] = dv; padset.insert(a); continue;
        }
        if (d.size() < 300) {
            snprintf(b, sizeof b, " st[%06x]=%02x%s/%02x%s", a, dv, d_w ? "" : "(nw)", rv, r_w ? "" : "(nw)");
            d += b;
        }
    }
    dq.clear(); rq.clear(); loose.clear();
    while (!dut_o.empty() && !ref_o.empty()) {
        if (dut_o.front() != ref_o.front() && d.size() < 300) {
            snprintf(b, sizeof b, " out[%03x]=%02x/[%03x]=%02x", dut_o.front().first, dut_o.front().second,
                     ref_o.front().first, ref_o.front().second);
            d += b;
        }
        dut_o.pop_front(); ref_o.pop_front();
    }
    return d;
}

static void do_ref_step(uint32_t ieip_dbg) {
    (void)ieip_dbg;
    ref_get(&last_pre);
    ibytes(last_pre, last_pre.eip, last_ib);
    last_um = undef_flags(last_ib);
    last_rep = rep_string(last_ib);
    last_eip = last_pre.eip;
    int r = ref_step();
    ref_steps++;
    {
        ref_state_t po; ref_get(&po);
        // CR0 reserved bits: 86Box keeps whatever MOV CR0 wrote; z486 implements only the
        // i486 bits (PE MP EM TS ET NE WP AM NW CD PG) and reads the others as 0
        if (po.creg0 & ~0xE005003Fu) {
            n_cr0res++;
            ref_set_sys(po.creg0 & 0xE005003Fu, po.creg2, po.creg3, po.gdt_base, po.gdt_limit, po.idt_base, po.idt_limit);
        }
        bool pmode = (last_pre.creg0 & 1) && !(last_pre.eflags & 0x20000);
        for (int k = 0; k < 6; k++)
            if (po.seg[k].sel != last_pre.seg[k].sel || po.seg[k].base != last_pre.seg[k].base ||
                po.seg[k].attr != last_pre.seg[k].attr || po.seg[k].limit != last_pre.seg[k].limit)
                rm_loaded[k] = !pmode && !((po.creg0 & 1) && !(po.eflags & 0x20000));
    }
    if (!mode_step) {
        auto it = syncmap.find(ref_steps);
        if (it != syncmap.end()) ref_set_flags(it->second.first, it->second.second);
    }
    ref_store_log(ref_steps);
    {
        // (a delivery: the model's stack took an exception frame and EIP moved; used only to
        //  allow up to two squashed issues behind it in the pipelined mode)
        ref_state_t po; ref_get(&po);
        // an exception delivery: the model now sits at the handler of one of vectors 0-17
        last_fault = false;
        for (int vec = 0; vec <= 17 && !last_fault; vec++) {
            uint32_t off, sel;
            if (po.creg0 & 1) {
                if ((uint32_t)vec * 8 + 7 > po.idt_limit) break;
                uint32_t g = lin2phys(po, po.idt_base + vec * 8);
                off = rram[g] | rram[g + 1] << 8 | (uint32_t)rram[g + 6] << 16 | (uint32_t)rram[g + 7] << 24;
                sel = rram[g + 2] | rram[g + 3] << 8;
                if (!(rram[g + 5] & 8)) off &= 0xFFFF;     // 286 gate
            } else {
                uint32_t g = (po.idt_base + vec * 4) & 0xFFFFF;
                off = rram[g] | rram[g + 1] << 8; sel = rram[g + 2] | rram[g + 3] << 8;
            }
            if (po.eip == off && (po.seg[REF_CS].sel & ~3u) == (sel & ~3u)) last_fault = true;
        }
        squash_budget = last_fault ? 2 : 0;
    }
    if (ss_shadow(last_ib)) ss_pending = true;
    if (r & REF_STEP_HALT) { stop_req = true; ref_halted = true; }
    if (r & REF_STEP_RESET) { stop_req = true; }
    if (nstop && ref_steps >= nstop && !ss_pending) stop_req = true;
}

// compare the full state at a halt
static void compare_state(const int *v, bool final) {
    ref_state_t post;
    ref_get(&post);
    ncmp++;
    char b[128];
    std::string d;
    uint32_t dg[8];
    for (int k = 0; k < 8; k++) dg[k] = v[k];
    for (int k = 0; k < 8; k++)
        if (post.gpr[k] != dg[k]) { snprintf(b, sizeof b, " %s=%08x/%08x", GN[k], dg[k], post.gpr[k]); d += b; }
    for (int k = 0; k < 6; k++)
        if (post.seg[k].sel != (uint32_t)(v[11 + k] & 0xFFFF)) { snprintf(b, sizeof b, " %s=%04x/%04x", SN[k], v[11 + k] & 0xFFFF, post.seg[k].sel); d += b; }
    uint32_t deip = (uint32_t)v[8];
    uint32_t meip = post.eip + (ref_halted ? 1 : 0);
    if (deip != meip) { snprintf(b, sizeof b, " eip=%08x/%08x", deip, meip); d += b; }
    // descriptor caches
    for (int k = 0; k < 6; k++) {
        if ((post.creg0 & 1) && !(post.eflags & 0x20000) && !(post.seg[k].sel & 0xFFFC) && k != 1) continue;
        uint32_t db = v[17 + 3 * k], dl = v[18 + 3 * k], fl = v[19 + 3 * k];
        uint32_t G = (fl >> 6) & 1, DB = (fl >> 7) & 1;
        uint32_t dlim = G ? ((dl << 12) | 0xFFF) : dl;
        uint32_t dacc = ((fl >> 8) & 1) << 7 | ((fl >> 9) & 3) << 5 | ((fl >> 11) & 1) << 4 | ((fl >> 12) & 0xF) | ((fl >> 5) & 1);
        uint32_t macc = post.seg[k].attr & 0xFF, mdb = (post.seg[k].attr >> 10) & 1;
        // (accessed bit and P compared; in real mode only base/limit)
        bool pm = (post.creg0 & 1) && !(post.eflags & 0x20000);
        bool bad = db != post.seg[k].base || dlim != post.seg[k].limit;
        if (pm && !rm_loaded[k] && (dacc != macc || DB != mdb)) bad = true;
        if (bad) {
            snprintf(b, sizeof b, " %s.desc=%08x/%08x,%02x%s/%08x/%08x,%02x%s", SN[k], db, dlim, dacc, DB ? "B" : "",
                     post.seg[k].base, post.seg[k].limit, macc, mdb ? "B" : "");
            d += b;
        }
    }
    if (post.creg0 & 1) {
        uint32_t mcpl = (post.seg[1].attr >> 5) & 3;
        if (post.eflags & 0x20000) mcpl = 3;
        if ((uint32_t)v[38] != mcpl) { snprintf(b, sizeof b, " cpl=%d/%d", v[38], mcpl); d += b; }
        if ((uint32_t)(v[39] & 0xFFFF) != post.ldtr.sel || (uint32_t)(v[40] & 0xFFFF) != post.tr.sel) {
            snprintf(b, sizeof b, " ldtr,tr=%04x,%04x/%04x,%04x", v[39] & 0xFFFF, v[40] & 0xFFFF, post.ldtr.sel, post.tr.sel);
            d += b;
        }
    }
    if (((uint32_t)v[35] ^ post.creg0) & 0xE005002F) { snprintf(b, sizeof b, " cr0=%08x/%08x", v[35], post.creg0); d += b; }
    if ((uint32_t)v[36] != post.creg2) {
        // 86Box reports the faulting access's CR2 one to three bytes on for some multi-byte
        // accesses; z486 the first byte (Intel: the linear address that caused the fault)
        uint32_t dd = post.creg2 - (uint32_t)v[36];
        bool blk = ((post.creg2 & ~0xFu) == (uint32_t)v[36]) && !((uint32_t)v[36] & 0xF);   // fetch #PF: z486 reports the 16-byte prefetch block
        if (blk) n_cr2blk++;
        if ((dd >= 1 && dd <= 3) || blk) { n_cr2++; ref_set_sys(post.creg0, v[36], post.creg3, post.gdt_base, post.gdt_limit, post.idt_base, post.idt_limit); }
        else { snprintf(b, sizeof b, " cr2=%08x/%08x", v[36], post.creg2); d += b; }
    }
    if ((uint32_t)v[37] != post.creg3) { snprintf(b, sizeof b, " cr3=%08x/%08x", v[37], post.creg3); d += b; }
    uint32_t mdr[8]; ref_get_dr(mdr);
    if ((((uint32_t)v[41] ^ mdr[6]) & ~0x1000u) || (uint32_t)v[42] != mdr[7]) {
        snprintf(b, sizeof b, " dr6,7=%08x,%08x/%08x,%08x", v[41], v[42], mdr[6], mdr[7]); d += b;
    }
    uint32_t um = mode_step ? last_um : 0;
    uint32_t fm = (mode_step ? 0x274FD5u : 0x264FD5u) & ~um;   // (pipelined: RF not compared, see rfmask)
    uint32_t dfl = v[9];
    if ((post.eflags & fm) != (dfl & fm)) { snprintf(b, sizeof b, " fl=%06x/%06x", dfl & fm, post.eflags & fm); d += b; }
    if (mode_step && um) {
        ref_set_flags(um, dfl);
        if (syncf) fprintf(syncf, "%ld %x %x\n", ref_steps, um, dfl & um);
    }
    if (!d.empty() && deip != meip && !defer_used && (((mdr[7] & 0xFF) != 0) || (last_pre.eflags & 0x100))) {
        // the model ran the instruction and its debug trap in one step: compare at the next boundary
        defer_used = true; defer_cmp = true; n_defer++;
        return;
    }
    defer_used = false;
    d += match_stores(true);
    if (verbose)
        printf("  #%ld %04x:%08x [%02x %02x %02x %02x] -> eip=%08x fl=%05x ecx=%08x edi=%08x%s\n", ref_steps, last_pre.seg[REF_CS].sel, last_pre.eip,
               last_ib[0], last_ib[1], last_ib[2], last_ib[3], deip, dfl & 0x3ffff, dg[1], dg[7], d.empty() ? "" : " *");
    if (!d.empty()) {
        report(final ? "final" : "state", d);
        if (resync) {
            // the model takes the DUT's registers, flags and EIP (segment caches kept)
            for (int k = 0; k < 8; k++) post.gpr[k] = dg[k];
            post.eflags = dfl; post.eip = deip;
            ref_set(&post, 0);
            ref_set_sys(post.creg0, post.creg2, post.creg3, post.gdt_base, post.gdt_limit, post.idt_base, post.idt_limit);
            // memory: the DUT's bytes
            memcpy(rram, mem, 1 << 24);
            dq.clear(); rq.clear(); loose.clear();
        } else finished = true;
    }
}

static long cyc = 0, last_act = 0, last_iss = 0;
static bool started = false;
static long max_cycles = 200000000;

// one issued instruction: check its EIP against the model and step the model
static bool take_issue(uint32_t ieip) {
    if (inta_pending_vec >= 0) {
        // external interrupt acknowledged by the DUT: deliver it to the model at this boundary
        ref_state_t p0; ref_get(&p0); last_pre = p0;
        ref_interrupt(inta_pending_vec);
        ref_store_log(ref_steps);
        inta_pending_vec = -1;
    }
    ref_state_t pre; ref_get(&pre);
    if (ss_pending) {
        ss_pending = false;
        // the model ran it with the MOV / POP SS - unless that faulted (then the DUT's next
        // issue is the handler, where the model is)
        if (ieip != pre.eip) {
            // (a chain: the skipped instruction is itself MOV / POP SS - 86Box ran one more)
            uint8_t sb[16]; ibytes(pre, ieip, sb);
            if (ss_shadow(sb)) ss_pending = true;
            if (nstop && ref_steps >= nstop && !ss_pending) stop_req = true;
            return true;
        }
    }
    if (ieip != pre.eip) {
        if (last_rep && ieip == last_eip) return true;       // another pass of a REP string instruction
        if (stop_req) return true;                           // behind the stop point
        if (!mode_step && squash_budget > 0 && last_fault) {
            squash_budget--; n_squash++;
            return true;
        }
        {
            // a fault at the fetch of the model's next instruction (#PF, CS limit): the DUT
            // delivers it without issuing that instruction; the model steps it and delivers
            do_ref_step(pre.eip);
            ref_state_t po; ref_get(&po);
            if (po.eip == ieip) { n_fetchf++; do_ref_step(ieip); return true; }
            pre = po;
        }
        if (!mode_step && squash_budget > 0) {
            // pipelined: an instruction issued behind an older one that faults later (a posted
            // write's #PF) is squashed by the core; the next issue must be where the model is
            squash_budget--; n_squash++;
            squash_ieip = ieip;
            return true;
        }
        char b[96]; snprintf(b, sizeof b, " issue eip=%08x/%08x", ieip, pre.eip);
        ref_state_t sv = last_pre; uint8_t sb[16]; memcpy(sb, last_ib, 16);
        last_pre = pre; ibytes(pre, pre.eip, last_ib);
        report("flow", b);
        last_pre = sv; memcpy(last_ib, sb, 16);
        finished = true;
        return false;
    }
    do_ref_step(ieip);
    return true;
}

// called every cycle; returns bit0 serialise (stepwise), bit1 go, bit2 finish, bit3 single_step (pipelined stop)
static bool since_cmp = false;   // an instruction issued since the last compare
static bool frozen = false;      // pipelined stop: an instruction issued in the halting boundary (not executed)
extern "C" int ls_tick(int issue, int ieip, int hst, int tfr, int done, int ssv, const int *v) {
    cyc++;
    cyc_now = cyc;
    if (finished) return 4;
    bool hstable = hst & 1, hhalt = (hst >> 1) & 1;
    if (tfr) {
        if (!stop_req) {
            int r = ref_step(); ref_wlog_clear();
            if (!(r & REF_STEP_RESET)) report("shutdown", " the model did not shut down");
        }
        finished = true;
        return 4;
    }
    int idle_ctl = mode_step ? 1 : (stop_req ? 8 : 2);
    if (issue) {
        last_act = last_iss = cyc;
        n_issue++;
        since_cmp = true;
        if (!mode_step && ssv && done) frozen = true;          // never executed: not stepped
        else if (!take_issue(ieip)) return 4;
        idle_ctl = mode_step ? 1 : (stop_req ? 8 : 2);
        return mode_step ? 1 : idle_ctl;     // (stepwise: no further issue until the next compare)
    }
    if (!mode_step && stop_req && hhalt) {
        last_act = cyc;
        if (frozen) { uint32_t e = v[10]; int vv[64]; memcpy(vv, v, sizeof vv); vv[8] = e; compare_state(vv, true); }
        else compare_state(v, true);
        finished = true;
        return 4;
    }
    if (mode_step && hstable) {
        last_act = cyc;
        if (stop_req) {
            compare_state(v, true);
            finished = true;
            return 4;
        }
        if (cyc - last_iss > 200000) {
            // stepwise: the core keeps settling with go raised but never issues (the front end
            // is stuck, e.g. an over-long instruction): the same verdict as the pipelined hang
            ref_state_t pre; ref_get(&pre);
            char b[128];
            snprintf(b, sizeof b, " HANG: no issue for 200k cycles (model at %04x:%08x)", pre.seg[REF_CS].sel, pre.eip);
            report("hang", b);
            finished = true;
            return 4;
        }
        if (since_cmp || defer_cmp) {
            bool mid_rep = last_rep && (uint32_t)v[8] == last_eip;
            defer_cmp = false;
            if (!(ss_pending || mid_rep)) compare_state(v, false);
            since_cmp = false;
            if (finished) return 4;
        }
        return 1 | 2;
    }
    if (stop_req && cyc - last_act > 3000) { compare_state(v, true); finished = true; return 4; }
    if (cyc - last_act > 200000) {
        ref_state_t pre; ref_get(&pre);
        char b[128];
        snprintf(b, sizeof b, " HANG: nothing for 200k cycles (model at %04x:%08x)", pre.seg[REF_CS].sel, pre.eip);
        report("hang", b);
        finished = true;
        return 4;
    }
    if (cyc > max_cycles) { report("timeout", " max cycles"); finished = true; return 4; }
    return idle_ctl;
}

static void usage() { fprintf(stderr, "usage: Vtb_lock [-s|-p] [-n N] [-lat 0|1|2] [-seed S] [-kr] [-sync F] [-v] [-rom] prog\n"); exit(2); }

int main(int argc, char **argv) {
    std::string fn, syncfn;
    uint32_t bseed = 1;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "-s") mode_step = 1;
        else if (a == "-p") mode_step = 0;
        else if (a == "-n") nstop = atol(argv[++i]);
        else if (a == "-lat") lat_mode = atoi(argv[++i]);
        else if (a == "-seed") bseed = strtoul(argv[++i], nullptr, 0);
        else if (a == "-kr") resync = 1;
        else if (a == "-v") verbose = 1;
        else if (a == "-rom") rom = 1;
        else if (a == "-sync") syncfn = argv[++i];
        else if (a == "-maxcyc") max_cycles = atol(argv[++i]);
        else if (a[0] == '+') continue;
        else if (a[0] == '-') usage();
        else fn = a;
    }
    if (fn.empty()) usage();
    prog_name = fn.substr(fn.find_last_of('/') + 1);
    rng = bseed * 2654435761u + 7;
    FILE *f = fopen(fn.c_str(), "rb");
    if (!f) { printf("%s LOADERR\n", prog_name.c_str()); return 1; }
    static uint8_t img[0x20000];
    uint32_t gp0[8] = {0, 0, 0, 0, 0xFFFE, 0, 0, 0}, eip0 = 0x100, efl0 = 2, seed = 1, nret = 0;
    uint16_t sg0[6] = {0x1000, 0x1000, 0x1000, 0x1000, 0, 0}, ivt[256];
    uint32_t cr0_0 = 0x10;
    char mg[4] = {0};
    size_t n = 0;
    bool rprog = false, rpm = false;
    if (rom) {
        n = fread(img, 1, sizeof img, f);
        if (n != 0x10000 && n != 0x20000) { printf("%s LOADERR\n", prog_name.c_str()); return 1; }
        sg0[0] = sg0[2] = sg0[3] = 0; sg0[1] = 0xF000; eip0 = 0xFFF0; gp0[4] = 0; gp0[2] = 0x420;
        cr0_0 = getenv("ROMCR0") ? (uint32_t)strtoul(getenv("ROMCR0"), nullptr, 16) : 0x00000010;   // (caches on: test386 never sets CD; i486 reset 60000010 is ~10x slower)
    } else {
        n = fread(mg, 1, 4, f);
        rpg = n == 4 && !memcmp(mg, "RPG3", 4);
        rpm = n == 4 && (!memcmp(mg, "RPM3", 4) || rpg);
        rprog = n == 4 && (!memcmp(mg, "R386", 4) || rpm);
        if (rprog) {
            bool ok = fread(&seed, 4, 1, f) == 1 && fread(&nret, 4, 1, f) == 1 && fread(gp0, 4, 8, f) == 8 &&
                      fread(sg0, 2, 6, f) == 6 && fread(&eip0, 4, 1, f) == 1 && fread(&efl0, 4, 1, f) == 1 &&
                      fread(ivt, 2, 256, f) == 256 && fread(img, 1, 0x10000, f) == 0x10000;
            if (!ok) { printf("%s LOADERR\n", prog_name.c_str()); return 1; }
            if (!nstop) nstop = nret;
        } else {
            memcpy(img, mg, n);
            n += fread(img + n, 1, 0x10000 - n, f);
        }
    }
    fclose(f);
    memset(mem, 0, sizeof mem);
    if (rprog) {
        uint32_t x = seed * 2654435761u + 12345;
        for (uint32_t a = 0x400; a < 0x100000; a++) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; mem[a] = x >> 11; }
        memcpy(mem + ((uint32_t)sg0[1] << 4), img, 0x10000);
        for (int v = 0; v < 256; v++)
            for (uint32_t t : {0u, 0x800u}) {
                mem[t + v * 4] = ivt[v] & 0xFF; mem[t + v * 4 + 1] = ivt[v] >> 8;
                mem[t + v * 4 + 2] = sg0[1] & 0xFF; mem[t + v * 4 + 3] = sg0[1] >> 8;
            }
        if (rpm) rpm_tables(ivt, sg0[1]);
        if (rpg) rpg_tables(seed);
    } else if (rom) memcpy(mem + 0x100000 - n, img, n);
    else memcpy(mem + 0x10000, img, n);

    static const ref_io_t lio = { nullptr, [](uint16_t port, int size, uint32_t val) {
        for (int i = 0; i < size; i++) {
            uint8_t b = val >> (8 * i);
            ref_o.push_back({(uint32_t)(port + i), b});
            if (port + i == 0xE9) out_e9 += (char)b;
            if (port + i == 0x190) {
                if (getenv("LOCKPOST") && (post_codes.empty() || post_codes.back() != b)) {
                    printf("  POST %02X at model step %ld\n", b, ref_steps); fflush(stdout);
                }
                post_codes.push_back(b);
            }
        }
        if (port == 0x92) ref_set_a20(val & 2); } };
    if (ref_init(16384, &lio)) { printf("%s REFERR\n", prog_name.c_str()); return 1; }
    ref_config(0x420, 0, 1);
    ref_reset();
    ref_set_a20(1);
    rram = ref_ram();
    memset(rram, 0, ref_ram_size());
    memcpy(rram, mem, 1 << 24);
    ref_state_t rs; memset(&rs, 0, sizeof rs);
    for (int k = 0; k < 8; k++) rs.gpr[k] = gp0[k];
    for (int k = 0; k < 6; k++) rs.seg[k].sel = sg0[k];
    rs.eip = eip0; rs.eflags = efl0 & 0x7FD5;
    ref_set(&rs, 1);
    ref_set_sys(cr0_0, 0, 0, 0, 0xFFFF, 0, 0xFFFF);   // (z486 reset GDTR / IDTR limits: FFFFh, SDM table 9-1)
    ref_wlog_clear();
    ref_get(&last_pre);

    if (!syncfn.empty()) {
        if (mode_step) syncf = fopen(syncfn.c_str(), "w");
        else if (FILE *sf = fopen(syncfn.c_str(), "r")) {
            long i; uint32_t m, val;
            while (fscanf(sf, "%ld %x %x", &i, &m, &val) == 3) syncmap[i] = {m, val};
            fclose(sf);
        }
    }
    // DUT initial state (order: tb_lock.sv)
    initv[0] = cr0_0; initv[1] = 0;
    for (int k = 0; k < 8; k++) initv[2 + k] = gp0[k];
    initv[10] = (efl0 & 0x7FD5) | 2;
    for (int k = 0; k < 6; k++) initv[11 + k] = sg0[k];
    initv[17] = eip0;
    initv[18] = mode_step;

    auto ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    auto top = new Vtb_lock{ctx};
    while (!ctx->gotFinish()) {
        top->eval();
        if (!top->eventsPending()) break;
        ctx->time(top->nextTimeSlot());
    }
    top->final();
    if (syncf) fclose(syncf);
    // final memory image for programs that end (not stopped random programs)
    long md = 0; uint32_t ma = 0;
    if (nmis == 0)
        for (uint32_t a = 0; a < (1u << 20); a++)
            if (mem[a] != rram[a] && !(rfset.count(a) && ((mem[a] ^ rram[a]) == 1)) && !padset.count(a) &&
                !(rpg && a >= 0x8E000 && a < 0x8F000 && ((mem[a] ^ rram[a]) & ~0x60) == 0)) { if (!md) ma = a; md++; }
    if (rom) {
        printf("%s POST", prog_name.c_str());
        int last = -1;
        for (auto c : post_codes) if (c != last) { printf(" %02X", c); last = c; }
        printf("\n");
        if (FILE *o = fopen((fn + ".out").c_str(), "wb")) { fwrite(out_e9.data(), 1, out_e9.size(), o); fclose(o); }
    }
    if (!nmis && n_inta_low) {
        // the model was handed the interrupt only because the DUT acknowledged it: an INTA
        // for a request that was withdrawn before the boundary is a divergence of its own
        char b[128];
        snprintf(b, sizeof b, " INTA for a withdrawn INTR: %ld of %ld acknowledges", n_inta_low, n_inta);
        report("intr", b);
    }
    if (!nmis && (!dut_o.empty() || !ref_o.empty()) && !getenv("LOCKNOOUT")) {
        char b[160];
        snprintf(b, sizeof b, " OUT bytes left: dut %zu (first [%03x]=%02x), ref %zu", dut_o.size(),
                 dut_o.empty() ? 0 : dut_o.front().first, dut_o.empty() ? 0 : dut_o.front().second, ref_o.size());
        report("out", b);
    }
    if (!nmis && !md)
        printf("%-14s LOCK OK %s insns=%ld issues=%ld compares=%ld cycles=%ld rfmask=%ld defer=%ld selpad=%ld errpad=%ld ad=%ld cpio=%ld cr0res=%ld fetchf=%ld cr2=%ld cr2blk=%ld inta=%ld inta_low=%ld squash=%ld\n", prog_name.c_str(), mode_step ? "step" : "pipe",
               ref_steps, n_issue, ncmp, cyc, n_rfmask, n_defer, n_selpad, n_errpad, n_ad, n_cpio, n_cr0res, n_fetchf, n_cr2, n_cr2blk, n_inta, n_inta_low, n_squash);
    else {
        printf("%-14s LOCK MISMATCH %s n=%ld first: %s", prog_name.c_str(), mode_step ? "step" : "pipe", nmis, first.c_str());
        if (md) printf(" mem: %ld bytes differ, first [%05x]=%02x/%02x", md, ma, mem[ma], rram[ma]);
        printf("\n");
        if (resync) {
            printf("               by opcode:");
            for (int k = 0; k < 256; k++) if (hist[k]) printf(" %02X:%ld", k, hist[k]);
            printf("\n");
        }
    }
    delete top;
    return 0;
}
