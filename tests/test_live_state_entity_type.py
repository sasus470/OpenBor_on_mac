"""Check effective entity types when restoring weapon/player models."""

import pathlib
import subprocess
import tempfile


root = pathlib.Path(__file__).resolve().parents[1]
source = (root / "openbor-src/engine/openbor.c").read_text()
start = source.index("static entity *hosted_live_state_spawn_entity(")
end = source.index("static void hosted_live_state_restore_music(void)\n{", start)
helper = source[start:end]

harness = r'''
#include <assert.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#define MODEL_INDEX_NONE -1
typedef struct {
    struct { int type; char name[64]; } modeldata;
    char default_model_name[64];
    int exists, player_behavior, animating, idling, lifespancountdown;
    float speedmul, base, movex, movez;
    unsigned autokill;
} entity;
typedef struct {
    float x, y, z;
    int direction, model_type;
    char model_name[64];
    char default_model_name[64];
    int animating, idling, lifespan_countdown;
    float speed_multiplier, base, move_x, move_z;
    int has_lifecycle_state;
    unsigned autokill;
} s_hosted_live_entity_boot;
static entity pooled_entity;
static int pak_type, init_calls;
static entity *spawn(float x, float z, float y, int dir, char *name, int index, void *model) {
    (void)x; (void)z; (void)y; (void)dir; (void)name; (void)index; (void)model;
    pooled_entity.modeldata.type = pak_type;
    strcpy(pooled_entity.modeldata.name, name);
    strcpy(pooled_entity.default_model_name, name);
    pooled_entity.exists = 1;
    pooled_entity.player_behavior = 0;
    return &pooled_entity;
}
static void ent_default_init(entity *ent) {
    ++init_calls;
    ent->player_behavior = (ent->modeldata.type == 4);
}
static void set_model_ex(entity *ent, char *name, int index, void *model, int anim_flag) {
    (void)index; (void)model; (void)anim_flag;
    strcpy(ent->modeldata.name, name);
}
'''
harness += helper + r'''
int main(void) {
    s_hosted_live_entity_boot state = {0};
    state.model_type = 4;
    strcpy(state.model_name, "Lloyd3");
    strcpy(state.default_model_name, "Lloyd");
    pak_type = 1; /* TYPE_NONE, as used by Lloyd4 and Keith4 weapon models. */
    entity *ent = hosted_live_state_spawn_entity(&state);
    assert(ent->exists && ent->modeldata.type == 4 && ent->player_behavior);
    assert(init_calls == 1);
    assert(!strcmp(ent->modeldata.name, "Lloyd3"));
    assert(!strcmp(ent->default_model_name, "Lloyd"));
    /* weaponframe 0 returns to the retained base model after the entry. */
    set_model_ex(ent, ent->default_model_name, -1, NULL, 0);
    assert(!strcmp(ent->modeldata.name, "Lloyd"));

    state.model_type = pak_type = 8; /* Ordinary enemy retains its model type. */
    strcpy(state.model_name, "cruser2");
    strcpy(state.default_model_name, "cruser2");
    ent = hosted_live_state_spawn_entity(&state);
    assert(ent->exists && ent->modeldata.type == 8);
    assert(init_calls == 1);

    /* A finishing cutscene must not regain a full lifespan or start playing. */
    ent->animating = 1;
    ent->lifespancountdown = 1080;
    ent->speedmul = 1;
    state.animating = 0;
    state.idling = 2;
    state.lifespan_countdown = 5;
    state.speed_multiplier = 0.25f;
    state.base = 12;
    state.move_x = -2;
    state.move_z = 3;
    hosted_live_state_restore_entity_progress(ent, &state);
    assert(ent->animating == 0 && ent->lifespancountdown == 5);
    assert(ent->speedmul == 0.25f && ent->idling == 2);
    assert(ent->base == 12 && ent->movex == -2 && ent->movez == 3);
    state.has_lifecycle_state = 1;
    state.autokill = 2;
    ent->autokill = 0;
    hosted_live_state_restore_entity_progress(ent, &state);
    assert(ent->autokill == 2);
    state.has_lifecycle_state = 0; /* Legacy V6/V7 retain the model defaults. */
    ent->autokill = 4;
    hosted_live_state_restore_entity_progress(ent, &state);
    assert(ent->autokill == 4);
    puts("PASS: weapon models regain the saved player type and behavior.");
    puts("PASS: the temporary spawn model retains the base model for weaponframe 0.");
    puts("PASS: stopped animations and remaining lifespan survive restoration.");
    puts("PASS: V8 preserves effect cleanup flags; legacy snapshots keep model defaults.");
}
'''
with tempfile.TemporaryDirectory(prefix="openbor-type-test-") as directory:
    binary = pathlib.Path(directory) / "type-test"
    subprocess.run(
        ["clang", "-x", "c", "-std=c99", "-o", str(binary), "-"],
        input=harness,
        text=True,
        check=True,
    )
    subprocess.run([str(binary)], check=True)
