/*
 * steamappinfo - reads Steam's appcache/appinfo.vdf (binary format v28/v29) without Steam running.
 *
 *   steamappinfo <appinfo.vdf> [appid...]        "appid<TAB>type<TAB>name"
 *   steamappinfo -l <appinfo.vdf> [appid...]     "appid<TAB>executable" - the first Windows launch option
 *                                                (relative to the game's install folder, as Steam stores it)
 *
 * Prints one line per given app ID (or for all apps when none are given). Exit 1 = unreadable / unsupported file.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint8_t *buf;
static size_t len;
static char **strtab;      /* v29: keys are indices into a string table at the end of the file */
static uint32_t nstr;
static int v29;

static uint32_t rd32(size_t o) { return o + 4 <= len ? (uint32_t)buf[o] | buf[o+1] << 8 | buf[o+2] << 16 | (uint32_t)buf[o+3] << 24 : 0; }
static uint64_t rd64(size_t o) { return (uint64_t)rd32(o) | (uint64_t)rd32(o + 4) << 32; }

/* Reads a key at *p (string table index in v29, C string in v28). */
static const char *key(size_t *p)
{
    if (v29) { uint32_t i = rd32(*p); *p += 4; return i < nstr ? strtab[i] : ""; }
    const char *s = (const char *)buf + *p; *p += strlen(s) + 1; return s;
}

/* Launch options: config/launch/<n>/executable and config/launch/<n>/config/oslist */
#define MAX_LAUNCH 16
struct launch { const char *exe; const char *oslist; };
static struct launch launches[MAX_LAUNCH];

/* Walks a binary KeyValues object. path[0..depth) are the enclosing keys. Collects common/name, common/type
 * and the launch options. Returns 1 on an unknown value type (stop this entry). */
static int walk(size_t *p, size_t end, const char **path, int depth, const char **name, const char **type)
{
    while (*p < end) {
        uint8_t t = buf[(*p)++];
        if (t == 8) return 0;                        /* end of object */
        const char *k = key(p);
        switch (t) {
        case 0:                                      /* nested object */
            if (depth < 8) path[depth] = k;
            if (walk(p, end, path, depth + 1, name, type)) return 1;
            break;
        case 1: {                                    /* string */
            const char *v = (const char *)buf + *p;
            size_t l = strnlen(v, end - *p);
            /* the entry's root object is "appinfo", so sections start at depth 1 */
            if (depth == 2 && !strcmp(path[1], "common")) {
                if (!strcmp(k, "name")) *name = v;
                if (!strcmp(k, "type")) *type = v;
            }
            if (depth >= 4 && depth <= 5 && !strcmp(path[1], "config") && !strcmp(path[2], "launch")) {
                int n = atoi(path[3]);
                if (n >= 0 && n < MAX_LAUNCH) {
                    if (depth == 4 && !strcmp(k, "executable")) launches[n].exe = v;
                    if (depth == 5 && !strcmp(path[4], "config") && !strcmp(k, "oslist")) launches[n].oslist = v;
                }
            }
            *p += l + 1;
            break;
        }
        case 2: case 4: case 6: *p += 4; break;      /* int32, float, pointer */
        case 7: case 10: *p += 8; break;             /* uint64, int64 */
        default: return 1;                           /* unknown type: stop this entry */
        }
    }
    return 0;
}

int main(int argc, char **argv)
{
    int launch_mode = argc > 1 && !strcmp(argv[1], "-l");
    if (launch_mode) { argv++; argc--; }
    if (argc < 2) { fprintf(stderr, "usage: steamappinfo [-l] <appinfo.vdf> [appid...]\n"); return 1; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    fseek(f, 0, SEEK_END); len = (size_t)ftell(f); fseek(f, 0, SEEK_SET);
    buf = malloc(len + 1);
    if (!buf || fread(buf, 1, len, f) != len) { fclose(f); return 1; }
    fclose(f);
    buf[len] = 0;

    uint32_t magic = rd32(0);
    if (magic == 0x07564429) v29 = 1;
    else if (magic != 0x07564428) { fprintf(stderr, "unsupported appinfo.vdf version %08x\n", magic); return 1; }

    size_t p = 8, end = len;
    if (v29) {
        uint64_t so = rd64(8); p = 16;
        if (so >= len) return 1;
        nstr = rd32(so);
        strtab = calloc(nstr ? nstr : 1, sizeof(char *));
        size_t q = so + 4;
        for (uint32_t i = 0; i < nstr && q < len; i++) { strtab[i] = (char *)buf + q; q += strlen(strtab[i]) + 1; }
        end = so;
    }

    while (p + 8 <= end) {
        uint32_t appid = rd32(p);
        if (appid == 0) break;
        uint32_t size = rd32(p + 4);
        size_t next = p + 8 + size;
        size_t kv = p + 8 + 4 + 4 + 8 + 20 + 4 + 20;   /* state, updated, token, sha1, change, binary sha1 */
        int wanted = argc == 2;
        for (int i = 2; i < argc && !wanted; i++) wanted = (uint32_t)strtoul(argv[i], NULL, 10) == appid;
        if (wanted && kv < next && next <= end) {
            const char *name = "", *type = "", *path[8];
            size_t q = kv;
            memset(launches, 0, sizeof(launches));
            walk(&q, next, path, 0, &name, &type);
            if (!launch_mode) printf("%u\t%s\t%s\n", appid, type, name);
            else {
                /* first launch option for Windows (or without an OS restriction) */
                for (int i = 0; i < MAX_LAUNCH; i++) {
                    const char *os = launches[i].oslist;
                    if (!launches[i].exe || !launches[i].exe[0]) continue;
                    if (os && os[0] && !strstr(os, "windows")) continue;
                    printf("%u\t%s\n", appid, launches[i].exe);
                    break;
                }
            }
        }
        p = next;
    }
    return 0;
}
