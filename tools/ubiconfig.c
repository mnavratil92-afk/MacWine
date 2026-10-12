/*
 * ubiconfig - lists the games in Ubisoft Connect's product cache without the launcher running.
 *
 *   ubiconfig <...\Ubisoft Game Launcher\cache\configuration\configurations>
 *
 * The file is a protobuf list of {uplay_id, install_id, configuration (YAML)} for the products of the
 * signed-in account. Prints "uplay_id<TAB>name<TAB>thumb_image" for every game Ubisoft Connect itself
 * starts (root.start_game present, no root.third_party_platform such as Steam). Exit 1 = unreadable file.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int varint(const uint8_t *b, size_t len, size_t *i, uint64_t *out)
{
    uint64_t r = 0; int s = 0;
    while (*i < len && s < 64) {
        uint8_t c = b[(*i)++];
        r |= (uint64_t)(c & 0x7f) << s; s += 7;
        if (c < 0x80) { *out = r; return 0; }
    }
    return 1;
}

/* Value of a "key: value" line at exactly the given indent inside the "root:" block (empty if missing). */
static void root_value(const char *y, const char *key, char *out, size_t outlen)
{
    out[0] = 0;
    const char *r = strstr(y, "\nroot:\n");
    if (!r && !strncmp(y, "root:\n", 6)) r = y - 1;
    if (!r) return;
    const char *p = r + 7;
    size_t kl = strlen(key);
    while (*p) {
        const char *e = strchr(p, '\n'); if (!e) e = p + strlen(p);
        if (p[0] != ' ' && p[0] != '#' && e > p) break;             /* left the root block */
        if (!strncmp(p, "  ", 2) && p[2] != ' ' && !strncmp(p + 2, key, kl) && p[2 + kl] == ':') {
            const char *v = p + 2 + kl + 1;
            while (v < e && *v == ' ') v++;
            size_t n = (size_t)(e - v);
            while (n && (v[n-1] == ' ' || v[n-1] == '\r')) n--;
            if (n >= 2 && (v[0] == '"' || v[0] == '\'') && v[n-1] == v[0]) { v++; n -= 2; }
            if (n >= outlen) n = outlen - 1;
            memcpy(out, v, n); out[n] = 0;
            return;
        }
        p = *e ? e + 1 : e;
    }
}

/* Resolves a localization key (e.g. "l1") from "localizations:\n  default:\n    l1: ..." */
static void localize(const char *y, char *val, size_t len)
{
    const char *d = strstr(y, "\nlocalizations:\n  default:\n");
    if (!d || !val[0] || strchr(val, ' ')) return;
    const char *p = d + strlen("\nlocalizations:\n  default:\n");
    size_t kl = strlen(val);
    while (*p && !strncmp(p, "    ", 4)) {
        const char *e = strchr(p, '\n'); if (!e) e = p + strlen(p);
        if (!strncmp(p + 4, val, kl) && p[4 + kl] == ':') {
            const char *v = p + 4 + kl + 1;
            while (v < e && *v == ' ') v++;
            size_t n = (size_t)(e - v);
            while (n && (v[n-1] == ' ' || v[n-1] == '\r')) n--;
            if (n >= 2 && (v[0] == '"' || v[0] == '\'') && v[n-1] == v[0]) { v++; n -= 2; }
            if (n >= len) n = len - 1;
            memcpy(val, v, n); val[n] = 0;
            return;
        }
        p = *e ? e + 1 : e;
    }
}

static void clean(char *s) { for (; *s; s++) if (*s == '\t' || *s == '\n' || *s == '\r') *s = ' '; }

int main(int argc, char **argv)
{
    if (argc != 2) { fprintf(stderr, "usage: ubiconfig <configurations>\n"); return 1; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    fseek(f, 0, SEEK_END); long fl = ftell(f); fseek(f, 0, SEEK_SET);
    if (fl <= 0 || fl > 512L * 1024 * 1024) { fclose(f); return 1; }
    size_t len = (size_t)fl;
    uint8_t *b = malloc(len);
    if (!b || fread(b, 1, len, f) != len) { fclose(f); return 1; }
    fclose(f);

    size_t i = 0;
    while (i < len) {
        uint64_t key, l;
        if (varint(b, len, &i, &key) || (key & 7) != 2 || varint(b, len, &i, &l) || l > len - i) return 1;
        size_t end = i + (size_t)l, j = i;
        uint64_t id = 0; char *yaml = NULL;
        while (j < end) {
            uint64_t k, v;
            if (varint(b, end, &j, &k)) break;
            if ((k & 7) == 0) { if (varint(b, end, &j, &v)) break; if ((k >> 3) == 1) id = v; }
            else if ((k & 7) == 2) {
                if (varint(b, end, &j, &v) || v > end - j) break;
                if ((k >> 3) == 3) { yaml = malloc((size_t)v + 2); yaml[0] = '\n'; memcpy(yaml + 1, b + j, (size_t)v); yaml[v + 1] = 0;
                    char *w = yaml; for (char *r = yaml; *r; r++) if (*r != '\r') *w++ = *r; *w = 0; }   /* CRLF -> LF */
                j += (size_t)v;
            } else break;
        }
        if (id && yaml && strstr(yaml, "\n  start_game:") && !strstr(yaml, "\n  third_party_platform:")) {
            char name[512], thumb[256];
            root_value(yaml, "name", name, sizeof name); localize(yaml, name, sizeof name);
            root_value(yaml, "thumb_image", thumb, sizeof thumb); localize(yaml, thumb, sizeof thumb);
            clean(name); clean(thumb);
            if (name[0]) printf("%llu\t%s\t%s\n", (unsigned long long)id, name, thumb);
        }
        free(yaml);
        i = end;
    }
    return 0;
}
