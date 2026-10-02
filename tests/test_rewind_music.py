"""Check the production rewind music policy without restarting the decoder."""
import pathlib
import subprocess
import tempfile

source = (pathlib.Path(__file__).resolve().parents[1] / 'openbor-src/engine/openbor.c').read_text()
start = source.index('static void hosted_live_state_restore_music(void)\n{')
end = source.index('static void hosted_live_state_apply_boot_after_level_load(void)\n{', start)
helper = source[start:end]
harness = r'''
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stddef.h>
static struct { char music_name[128]; int music_loop, music_offset; } hosted_live_boot_state;
static int hosted_rewind_restoring, decoder_open, open_calls;
static char currentmusic[128];
static int sound_query_music(char *a, char *t) { (void)a; (void)t; return decoder_open; }
static void writeToLogFile(const char *format, ...) { (void)format; }
static void music(char *name, int loop, long offset) { (void)name; (void)loop; (void)offset; ++open_calls; }
'''
harness += helper + r'''
int main(void) {
    strcpy(currentmusic, "stage.ogg");
    strcpy(hosted_live_boot_state.music_name, "stage.ogg");
    hosted_rewind_restoring = decoder_open = 1;
    hosted_live_state_restore_music();
    assert(open_calls == 0);
    strcpy(hosted_live_boot_state.music_name, "boss.ogg");
    hosted_live_state_restore_music();
    assert(open_calls == 1);
    strcpy(hosted_live_boot_state.music_name, "stage.ogg");
    decoder_open = 0;
    hosted_live_state_restore_music();
    assert(open_calls == 2);
    hosted_rewind_restoring = 0;
    decoder_open = 1;
    hosted_live_state_restore_music();
    assert(open_calls == 3); /* A new process still needs to open its music. */
    puts("PASS: rewind retains an unchanged live song; missing or changed tracks still open.");
}
'''
with tempfile.TemporaryDirectory(prefix='openbor-music-test-') as directory:
    binary = pathlib.Path(directory) / 'test'
    subprocess.run(['clang', '-x', 'c', '-o', str(binary), '-'], input=harness, text=True, check=True)
    subprocess.run([str(binary)], check=True)
