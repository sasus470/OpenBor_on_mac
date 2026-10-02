"""Exercise the engine's actual wave-spawn branch outside the game window."""

import pathlib
import subprocess
import tempfile


root = pathlib.Path(__file__).resolve().parents[1]
source = (root / "openbor-src/engine/openbor.c").read_text()
scroller = source[source.index("void update_scroller()") :]
start = scroller.index("else if(count_ents(TYPE_ENEMY) < groupmin)")
end = scroller.index("    for(i = 0; i < levelsets[current_set].maxplayers; i++)", start)
branch = scroller[start:end].replace("else if(", "if(", 1)

harness = r'''
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define TYPE_ENEMY 8
#define MAX_BUFFER_LEN 1024
#define BLEND_MODE_MODEL -1
#define BLEND_MODE_NONE 0
typedef struct {
    int at, musicfade, musicoffset, wait, groupmin, groupmax, nojoin;
    unsigned scrollminz, scrollmaxz, scrollminx, scrollmaxx;
    int blockade, palette, shadowcolor, shadowalpha, shadowopacity;
    struct { int x, y; } light;
    char music[1024];
} Entry;
typedef struct { int numspawns, pos, waiting; Entry *spawnpoints; } Level;
static Level *level;
static int enemies, spawned, groupmin, groupmax, current_spawn;
static int go_time, nojoin, _time, musicoffset, musicloop;
static int shadowcolor, shadowalpha, shadowopacity;
static float musicfade[2], scrollminz, scrollmaxz, scrollminx, scrollmaxx;
static float advancey, blockade;
static char musicname[1024];
static struct { int x, y; } light;
static struct { int musicvol; } savedata;
static int count_ents(int type) { (void)type; return enemies; }
static void smartspawn(Entry *entry) { (void)entry; ++enemies; ++spawned; }
static void change_system_palette(int palette) { (void)palette; }
static void tick(void) {
'''

harness += branch + r'''
}
int main(void) {
    Entry entries[4] = {{0}};
    Level lv = {4, 0, 1, entries};
    level = &lv;
    entries[0].groupmin = 2;
    entries[0].groupmax = 5;

    /* The captured state still has its two blocking entities. */
    groupmin = groupmax = enemies = 2;
    current_spawn = spawned = 0;
    for(int i = 0; i < 60; ++i) tick();
    assert(spawned == 0 && current_spawn == 0);

    /* Defeating one entity legitimately releases the next wave. */
    enemies = 1;
    tick();
    assert(spawned == 3 && current_spawn == 4 && enemies == 4);

    /* Reproduce the old restore: reset limits prematurely release enemies. */
    groupmin = groupmax = 100;
    enemies = 2;
    current_spawn = spawned = 0;
    tick();
    assert(spawned == 3 && current_spawn == 4);
    puts("PASS: saved wave limits prevent early spawns; old defaults reproduce the bug.");
}
'''

with tempfile.TemporaryDirectory(prefix="openbor-wave-test-") as directory:
    binary = pathlib.Path(directory) / "wave-test"
    subprocess.run(
        ["clang", "-x", "c", "-std=c99", "-o", str(binary), "-"],
        input=harness,
        text=True,
        check=True,
    )
    subprocess.run([str(binary)], check=True)
