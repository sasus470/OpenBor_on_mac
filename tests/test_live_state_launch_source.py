"""The native progress file must not overwrite imported live player state."""
import pathlib
import subprocess
import tempfile

source = (pathlib.Path(__file__).resolve().parents[1] / 'openbor-src/engine/openbor.c').read_text()
start = source.index('else if(skiptoset >= 0)\n        {')
end = source.index('\n        else\n        {', start)
branch = source[start:end].replace('else if', 'if', 1)
harness = r'''
#include <assert.h>
#include <stdio.h>
static struct { int loaded, set, applied; } hosted_live_boot_state;
static int skiptoset = 0, useSet = 0, useSave = 1, players[4];
static int native_loads, player_from_snapshot = 1;
static int loadGameFile(void) { ++native_loads; player_from_snapshot = 0; return 1; }
static void playgame(int *p, int set, int save) { (void)p; (void)set; (void)save; }
static void launch(void) {
''' + branch + r'''
}
int main(void) {
    hosted_live_boot_state.loaded = 1;
    hosted_live_boot_state.set = 0;
    launch();
    assert(native_loads == 0 && player_from_snapshot);
    hosted_live_boot_state.set = -1;
    launch();
    assert(native_loads == 1 && !player_from_snapshot);
    hosted_live_boot_state.set = 0;
    hosted_live_boot_state.applied = 1;
    launch();
    assert(native_loads == 2);
    puts("PASS: a pending live snapshot takes precedence over native stage progress.");
}
'''
with tempfile.TemporaryDirectory(prefix='openbor-live-launch-') as directory:
    binary = pathlib.Path(directory) / 'launch-test'
    subprocess.run(['clang', '-x', 'c', '-o', str(binary), '-'], input=harness, text=True, check=True)
    subprocess.run([str(binary)], check=True)
