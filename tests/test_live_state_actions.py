"""Test restored action dispatch, including legacy temporary player moves."""
import pathlib
import re
import subprocess
import tempfile

source = (pathlib.Path(__file__).resolve().parents[1] / 'openbor-src/engine/openbor.c').read_text()
table_start = source.index('static void (*const hosted_live_actions[])(void)')
table = source[table_start:source.index('static int hosted_live_action_id', table_start)]
start = source.index('static void hosted_live_state_restore_entity_action(')
helper = source[start:source.index('static entity *hosted_live_state_spawn_entity(', start)]
names = re.findall(r'\b(?:common_\w+|normal_prepare|upper_prepare|npc_recall|player_die|suicide|bomb_explode)\b', table)
harness = r'''
#include <assert.h>
#include <stdio.h>
#include <stddef.h>
#define TYPE_PLAYER 4
#define ATTACKING_ACTIVE 1
#define ANI_IDLE 1
#define ANI_WALK 2
#define ANI_RUN 3
#define ANI_SPAWN 4
#define ANI_RESPAWN 5
typedef struct {
    int has_action_state, action_id, attacking, charging, running, jumping;
    int tocost, weapon_state, smartbomb, inpain, rising, ducking, blocking, falling, idling;
    unsigned long pausetime, stalltime;
} s_hosted_live_entity_boot;
typedef struct {
    struct { int type; } modeldata;
    void (*takeaction)(void);
    int animnum, attacking, charging, running, jumping, tocost, weapon_state;
    int inpain, rising, ducking, blocking;
    unsigned long pausetime, stalltime;
} entity;
static entity *smartbomber;
'''
harness += '\n'.join(f'static void {name}(void) {{}}' for name in dict.fromkeys(names))
harness += '\n' + table + helper + r'''
int main(void) {
    entity ent = {0};
    s_hosted_live_entity_boot state = {0};
    ent.modeldata.type = TYPE_PLAYER;
    ent.animnum = 72; /* A temporary special animation, as in the reported slot. */
    hosted_live_state_restore_entity_action(&ent, &state);
    assert(ent.takeaction == common_attack_proc && ent.attacking == ATTACKING_ACTIVE);
    ent.animnum = ANI_IDLE;
    hosted_live_state_restore_entity_action(&ent, &state);
    assert(ent.takeaction == NULL);
    state.has_action_state = 1;
    state.action_id = 1;
    state.attacking = 1;
    state.tocost = state.smartbomb = 1;
    state.pausetime = 12;
    state.stalltime = 15;
    hosted_live_state_restore_entity_action(&ent, &state);
    assert(ent.takeaction == common_attack_proc && smartbomber == &ent);
    assert(ent.tocost && ent.pausetime == 12 && ent.stalltime == 15);
    state.action_id = 0;
    hosted_live_state_restore_entity_action(&ent, &state);
    assert(ent.takeaction == NULL);
    puts("PASS: temporary moves regain their finishing callback; V7 restores action flags.");
}
'''
with tempfile.TemporaryDirectory(prefix='openbor-action-test-') as directory:
    binary = pathlib.Path(directory) / 'action-test'
    subprocess.run(['clang', '-x', 'c', '-o', str(binary), '-'], input=harness, text=True, check=True)
    subprocess.run([str(binary)], check=True)
