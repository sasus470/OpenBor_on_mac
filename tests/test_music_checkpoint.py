"""Exercise production music checkpoints with deterministic decoder/mixer state."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / 'openbor-src/engine/source/gamelib/soundmix.c').read_text()
start = source.index('typedef struct\n{\n    musicchannelstruct channel;')
end = source.index('void sound_stop_playback()', start)
harness = r'''
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "soundmix.h"
typedef long long ogg_int64_t;
musicchannelstruct musicchannel;
static int music_type, music_looping, music_atend, current_section, loop_state_set;
static u32 loop_offset;
static short loop_valprev[2], predictor[2];
static char loop_index[2], steps[2];
static int adpcm_handle, locks, fail_seek;
static void *oggfile;
static long long cursor;
int sound_query_music(char *a, char *b) { return 1; }
static void SB_lock_audio(void) { assert(locks++ == 0); }
static void SB_unlock_audio(void) { assert(--locks == 0); }
static ogg_int64_t ov_pcm_tell(void *f) { assert(locks); return cursor; }
static int ov_pcm_seek(void *f, ogg_int64_t p) { assert(locks); if(fail_seek) return -1; cursor=p; return 0; }
static int seekpackfile(int h, int p, int whence) { assert(locks); if(whence == SEEK_SET) cursor=p; return cursor; }
static short adpcm_valprev(int i) { return predictor[i]; }
static char adpcm_index(int i) { return steps[i]; }
static void adpcm_loop_reset(int i, short p, char s) { predictor[i]=p; steps[i]=s; }
'''
harness += source[start:end] + r'''
int main(void) {
    int type, i;
    for(i=0; i<MUSIC_NUM_BUFFERS; ++i) musicchannel.buf[i]=calloc(MUSIC_BUF_SIZE,sizeof(short));
    for(type=0; type<2; ++type) {
        music_type=type; cursor=987654;
        musicchannel.fp_samplepos=12345; musicchannel.playing_buffer=2;
        musicchannel.fp_playto[2]=54321; musicchannel.active=1; musicchannel.paused=0;
        musicchannel.buf[2][17]=789; predictor[0]=345; steps[0]=12;
        music_atend=1; loop_state_set=1; loop_valprev[1]=111;
        void *state=sound_capture_music_checkpoint(); assert(state);
        cursor=999999; musicchannel.fp_samplepos=99; musicchannel.playing_buffer=0;
        musicchannel.fp_playto[2]=0; musicchannel.buf[2][17]=0;
        predictor[0]=0; steps[0]=0; music_atend=0; loop_state_set=0;
        assert(sound_restore_music_checkpoint(state));
        assert(cursor==987654 && musicchannel.fp_samplepos==12345);
        assert(musicchannel.playing_buffer==2 && musicchannel.fp_playto[2]==54321);
        assert(musicchannel.buf[2][17]==789 && predictor[0]==345 && steps[0]==12);
        assert(music_atend==1 && loop_state_set==1 && loop_valprev[1]==111);
        music_type=1-type; assert(!sound_restore_music_checkpoint(state)); music_type=type;
        if(type==1) { fail_seek=1; musicchannel.fp_samplepos=77;
            assert(!sound_restore_music_checkpoint(state)); assert(musicchannel.fp_samplepos==77); fail_seek=0; }
        free(state);
    }
    for(i=0; i<MUSIC_NUM_BUFFERS; ++i) free(musicchannel.buf[i]);
    puts("PASS: OGG/ADPCM checkpoints restore decoder cursor, PCM buffers, mixer position and predictors; failed seek preserves mixer.");
}
'''
with tempfile.TemporaryDirectory(prefix='openbor-checkpoint-test-') as directory:
    binary = pathlib.Path(directory) / 'test'
    subprocess.run(['clang', '-x', 'c', '-I', str(root / 'openbor-src/engine/source/gamelib'),
                    '-I', str(root / 'openbor-src/engine/source'), '-o', str(binary), '-'],
                   input=harness, text=True, check=True)
    subprocess.run([str(binary)], check=True)
