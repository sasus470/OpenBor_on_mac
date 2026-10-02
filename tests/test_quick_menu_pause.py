"""Test the actual engine menu-pause function without launching a game."""

import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / "openbor-src/engine/openbor.c").read_text()
start = source.index("static int hosted_quick_menu_paused(void)\n{")
end = source.index("static void hosted_live_state_export_if_requested()", start)
function = source[start:end]
harness = r'''
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static int _pause, music, samples, changes;
static void sound_pause_music(int paused) { music = paused; ++changes; }
static void sound_pause_sample(int paused) { samples = paused; }
static void write_pause(const char *path, int paused) {
    FILE *handle = fopen(path, "w");
    assert(handle);
    fputc(paused ? '1' : '0', handle);
    fclose(handle);
}
''' + function + r'''
int main(int argc, char **argv) {
    assert(argc == 2);
    setenv("OPENBOR_V2_QUICK_MENU_PAUSE_PATH", argv[1], 1);
    write_pause(argv[1], 0);
    assert(!hosted_quick_menu_paused());
    write_pause(argv[1], 1);
    assert(hosted_quick_menu_paused() && music && samples && !_pause);
    int previous = changes;
    for(int i = 0; i < 100; ++i) assert(hosted_quick_menu_paused());
    assert(changes == previous);
    write_pause(argv[1], 0);
    assert(!hosted_quick_menu_paused() && !music && !samples);
    _pause = 1;
    write_pause(argv[1], 1);
    assert(hosted_quick_menu_paused() && music && samples);
    write_pause(argv[1], 0);
    assert(!hosted_quick_menu_paused() && _pause && music && samples);
    puts("PASS: quick menu pauses audio and preserves the game's own pause.");
}
'''
with tempfile.TemporaryDirectory(prefix="openbor-menu-test-") as directory:
    binary = pathlib.Path(directory) / "menu-test"
    subprocess.run(["clang", "-x", "c", "-std=c99", "-o", str(binary), "-"],
                   input=harness, text=True, check=True)
    subprocess.run([str(binary), str(pathlib.Path(directory) / "pause.txt")], check=True)
