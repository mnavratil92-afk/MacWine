/*
 * lnkinfo - reads a Windows shortcut (.lnk, MS-SHLLINK) without Wine.
 *
 *   lnkinfo <file.lnk>...
 *
 * Prints one line per shortcut: "<lnk file><TAB><target path><TAB><arguments>" (UTF-8). Shortcuts without a
 * file-system target (e.g. ones that point at a URL or a shell folder only) are skipped.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint8_t *buf;
static size_t len;

static uint32_t rd16(size_t o) { return o + 2 <= len ? (uint32_t)(buf[o] | buf[o + 1] << 8) : 0; }
static uint32_t rd32(size_t o) { return o + 4 <= len ? (uint32_t)buf[o] | buf[o+1] << 8 | buf[o+2] << 16 | (uint32_t)buf[o+3] << 24 : 0; }

/* Appends UTF-16LE code units (count, or until NUL when count < 0) as UTF-8. */
static void utf16_to_utf8(size_t o, long count, char *out, size_t outlen)
{
    size_t n = 0;
    for (long i = 0; (count < 0 || i < count) && o + 2 <= len; i++, o += 2) {
        uint32_t c = rd16(o);
        if (count < 0 && !c) break;
        if (c >= 0xd800 && c < 0xdc00 && o + 4 <= len) {          /* surrogate pair */
            uint32_t lo = rd16(o + 2);
            if (lo >= 0xdc00 && lo < 0xe000) { c = 0x10000 + ((c - 0xd800) << 10) + (lo - 0xdc00); o += 2; i++; }
        }
        char tmp[4]; size_t k;
        if (c < 0x80) { tmp[0] = (char)c; k = 1; }
        else if (c < 0x800) { tmp[0] = (char)(0xc0 | c >> 6); tmp[1] = (char)(0x80 | (c & 0x3f)); k = 2; }
        else if (c < 0x10000) { tmp[0] = (char)(0xe0 | c >> 12); tmp[1] = (char)(0x80 | (c >> 6 & 0x3f)); tmp[2] = (char)(0x80 | (c & 0x3f)); k = 3; }
        else { tmp[0] = (char)(0xf0 | c >> 18); tmp[1] = (char)(0x80 | (c >> 12 & 0x3f)); tmp[2] = (char)(0x80 | (c >> 6 & 0x3f)); tmp[3] = (char)(0x80 | (c & 0x3f)); k = 4; }
        if (n + k >= outlen) break;
        memcpy(out + n, tmp, k); n += k;
    }
    out[n] = 0;
}

/* ANSI strings: Windows-1252 bytes >= 0x80 mapped to Latin-1 code points (good enough for paths). */
static void ansi_to_utf8(size_t o, char *out, size_t outlen)
{
    size_t n = 0;
    for (; o < len && buf[o]; o++) {
        uint8_t c = buf[o];
        if (c < 0x80) { if (n + 1 >= outlen) break; out[n++] = (char)c; }
        else { if (n + 2 >= outlen) break; out[n++] = (char)(0xc0 | c >> 6); out[n++] = (char)(0x80 | (c & 0x3f)); }
    }
    out[n] = 0;
}

static void clean(char *s) { for (; *s; s++) if (*s == '\t' || *s == '\n' || *s == '\r') *s = ' '; }

static int read_lnk(const char *file)
{
    FILE *f = fopen(file, "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END); long fl = ftell(f); fseek(f, 0, SEEK_SET);
    if (fl < 0x4c || fl > 1 << 20) { fclose(f); return 1; }
    len = (size_t)fl; free(buf); buf = malloc(len);
    if (!buf || fread(buf, 1, len, f) != len) { fclose(f); return 1; }
    fclose(f);
    if (rd32(0) != 0x4c) return 1;                           /* HeaderSize */

    uint32_t flags = rd32(0x14);
    int unicode = flags & 0x80;
    size_t p = 0x4c;
    char target[4096] = "", suffix[1024] = "", args[4096] = "";

    if (flags & 0x01) p += 2 + rd16(p);                      /* HasLinkTargetIDList */
    if (flags & 0x02) {                                      /* HasLinkInfo */
        size_t li = p;
        uint32_t li_size = rd32(li), hdr = rd32(li + 4), li_flags = rd32(li + 8);
        if (li_flags & 1) {                                  /* VolumeIDAndLocalBasePath */
            if (hdr >= 0x24 && rd32(li + 0x1c)) utf16_to_utf8(li + rd32(li + 0x1c), -1, target, sizeof(target));
            else ansi_to_utf8(li + rd32(li + 0x10), target, sizeof(target));
            if (hdr >= 0x24 && rd32(li + 0x20)) utf16_to_utf8(li + rd32(li + 0x20), -1, suffix, sizeof(suffix));
            else ansi_to_utf8(li + rd32(li + 0x18), suffix, sizeof(suffix));
            if (suffix[0] && strlen(target) + strlen(suffix) < sizeof(target)) strcat(target, suffix);
        }
        p = li + li_size;
    }
    /* StringData: name, relative path, working dir, arguments, icon - each a counted string */
    static const uint32_t bits[] = {0x04, 0x08, 0x10, 0x20, 0x40};
    for (int i = 0; i < 5; i++) {
        if (!(flags & bits[i])) continue;
        uint32_t count = rd16(p); p += 2;
        if (bits[i] == 0x20) {
            if (unicode) utf16_to_utf8(p, count, args, sizeof(args));
            else { size_t n = count < sizeof(args) - 1 ? count : sizeof(args) - 1; memcpy(args, buf + p, n); args[n] = 0; }
        }
        p += unicode ? count * 2 : count;
    }
    if (!target[0]) return 1;
    clean(target); clean(args);
    printf("%s\t%s\t%s\n", file, target, args);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "usage: lnkinfo <file.lnk>...\n"); return 1; }
    for (int i = 1; i < argc; i++) read_lnk(argv[i]);
    return 0;
}
