/*
 * exeicon - extracts the largest icon from a Windows program (.exe/.dll) without Wine.
 *
 *   exeicon <program.exe> <output-without-extension>
 *
 * Writes <output>.png (256 px icons are stored in the PE file as PNG) or
 * <output>.ico (a single bitmap icon) that `sips` can convert.
 * Exit code: 0 = ok, 1 = file error, 2 = the program has no icon.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define RT_ICON       3
#define RT_GROUP_ICON 14

static uint8_t *data;
static size_t size;

static uint16_t u16(size_t off) { return off + 2 <= size ? (uint16_t)(data[off] | data[off + 1] << 8) : 0; }
static uint32_t u32(size_t off) { return off + 4 <= size ? (uint32_t)u16(off) | (uint32_t)u16(off + 2) << 16 : 0; }

struct section { uint32_t va, vsize, raw, rawsize; };
static struct section *sections;
static unsigned nsections;
static uint32_t rsrc_rva;
static size_t rsrc_off;

static size_t rva_to_off(uint32_t rva)
{
    for (unsigned i = 0; i < nsections; i++) {
        uint32_t len = sections[i].vsize > sections[i].rawsize ? sections[i].vsize : sections[i].rawsize;
        if (rva >= sections[i].va && rva < sections[i].va + len)
            return sections[i].raw + (rva - sections[i].va);
    }
    return (size_t)-1;
}

/* Finds a resource directory entry by ID (id < 0 = first entry). Returns the offset of its target. */
static int find_entry(size_t dir, int id, uint32_t *target, int *found_id)
{
    uint16_t named = u16(dir + 12), ids = u16(dir + 14);
    for (unsigned i = 0; i < (unsigned)named + ids; i++) {
        size_t e = dir + 16 + i * 8;
        uint32_t name = u32(e), off = u32(e + 4);
        if (name & 0x80000000) { if (id >= 0) continue; }
        else if (id >= 0 && (int)name != id) continue;
        *target = off;
        if (found_id) *found_id = (name & 0x80000000) ? -1 : (int)name;
        return 1;
    }
    return 0;
}

/* Walks the three levels (type -> name -> language) and returns the resource data. */
static uint8_t *get_resource(int type, int name, uint32_t *len)
{
    uint32_t t, n, l;
    if (!find_entry(rsrc_off, type, &t, NULL) || !(t & 0x80000000)) return NULL;
    if (!find_entry(rsrc_off + (t & 0x7fffffff), name, &n, NULL) || !(n & 0x80000000)) return NULL;
    if (!find_entry(rsrc_off + (n & 0x7fffffff), -1, &l, NULL) || (l & 0x80000000)) return NULL;
    size_t de = rsrc_off + l;
    size_t off = rva_to_off(u32(de));
    *len = u32(de + 4);
    if (off == (size_t)-1 || off + *len > size) return NULL;
    return data + off;
}

int main(int argc, char **argv)
{
    if (argc != 3) { fprintf(stderr, "usage: exeicon <program.exe> <output-without-extension>\n"); return 1; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    fseek(f, 0, SEEK_END); size = (size_t)ftell(f); fseek(f, 0, SEEK_SET);
    data = malloc(size);
    if (!data || fread(data, 1, size, f) != size) { fclose(f); return 1; }
    fclose(f);

    if (u16(0) != 0x5a4d) { fprintf(stderr, "not a PE file\n"); return 1; }
    size_t pe = u32(0x3c);
    if (u32(pe) != 0x4550) { fprintf(stderr, "not a PE file\n"); return 1; }
    nsections = u16(pe + 6);
    uint16_t optsize = u16(pe + 20);
    size_t opt = pe + 24;
    int pe64 = u16(opt) == 0x20b;
    size_t datadir = opt + (pe64 ? 112 : 96);
    rsrc_rva = u32(datadir + 2 * 8);
    if (!rsrc_rva) return 2;
    sections = calloc(nsections, sizeof(*sections));
    size_t sh = opt + optsize;
    for (unsigned i = 0; i < nsections; i++, sh += 40) {
        sections[i].vsize = u32(sh + 8); sections[i].va = u32(sh + 12);
        sections[i].rawsize = u32(sh + 16); sections[i].raw = u32(sh + 20);
    }
    rsrc_off = rva_to_off(rsrc_rva);
    if (rsrc_off == (size_t)-1) return 2;

    /* First icon group (the main program icon). */
    uint32_t t, g;
    if (!find_entry(rsrc_off, RT_GROUP_ICON, &t, NULL) || !(t & 0x80000000)) return 2;
    if (!find_entry(rsrc_off + (t & 0x7fffffff), -1, &g, NULL) || !(g & 0x80000000)) return 2;
    uint32_t l;
    if (!find_entry(rsrc_off + (g & 0x7fffffff), -1, &l, NULL)) return 2;
    size_t de = rsrc_off + l;
    size_t grp = rva_to_off(u32(de));
    if (grp == (size_t)-1) return 2;
    uint16_t count = u16(grp + 4);

    /* Pick the largest icon (width 0 means 256); on a tie, the higher color depth. */
    int best = -1, best_w = 0, best_bpp = 0;
    for (int i = 0; i < count; i++) {
        size_t e = grp + 6 + i * 14;
        int w = data[e] ? data[e] : 256, bpp = u16(e + 6);
        if (w > best_w || (w == best_w && bpp > best_bpp)) { best = i; best_w = w; best_bpp = bpp; }
    }
    if (best < 0) return 2;
    size_t e = grp + 6 + best * 14;
    int icon_id = u16(e + 12);
    uint32_t len;
    uint8_t *img = get_resource(RT_ICON, icon_id, &len);
    if (!img || len < 8) return 2;

    char path[4096];
    int is_png = !memcmp(img, "\x89PNG\r\n\x1a\n", 8);
    snprintf(path, sizeof(path), "%s.%s", argv[2], is_png ? "png" : "ico");
    FILE *o = fopen(path, "wb");
    if (!o) { perror(path); return 1; }
    if (!is_png) {
        /* ICO header with one entry; the image data follows right after it (offset 22). */
        uint8_t hdr[22] = { 0, 0, 1, 0, 1, 0 };
        memcpy(hdr + 6, data + e, 12);
        hdr[18] = 22; hdr[19] = hdr[20] = hdr[21] = 0;
        hdr[14] = len & 0xff; hdr[15] = len >> 8 & 0xff; hdr[16] = len >> 16 & 0xff; hdr[17] = len >> 24;
        fwrite(hdr, 1, sizeof(hdr), o);
    }
    fwrite(img, 1, len, o);
    fclose(o);
    printf("%s\n", path);
    return 0;
}
