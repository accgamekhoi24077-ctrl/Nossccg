#import <substrate.h>
#import <UIKit/UIKit.h>
#import <math.h>

#define UDID_TARGET @"00008101-001E68993A78001E"
#define LOCK_SPEED 1.0f
#define HEADSHOT_OFFSET 15.0f
#define LOCK_DISTANCE 9999.0f
#define AUTO_SHOOT 1
#define SILENT_AIM 0
#define AIM_HEAD 1
#define IGNORE_TEAMMATES 1
#define IGNORE_DEAD 1

#define OFF_WORLD_TO_SCREEN  0x2B4C3A0
#define OFF_SET_AIM          0x1E8B2C4
#define OFF_LOCAL_PLAYER     0x2C0F8A0
#define OFF_CAMERA_MAIN      0x2C0F8A4
#define OFF_HEAD_TF          0x638
#define OFF_TRANSFORM_NODE   0x525A516
#define OFF_FIRE_CHECK       0x490
#define OFF_DICT_ENTITIES    0x74
#define OFF_HEALTH           0x14916C2
#define OFF_IS_DEAD          0x13FCA69

static uintptr_t base = 0x100000000;
static bool isLicensed = false;
static bool aimlockEnabled = true;
static float targetYaw = 0, targetPitch = 0;
static bool isLocked = false;
static void* lockedEnemy = NULL;

typedef struct { float x, y, z; } Vector3;

void (*orig_WorldToScreen)(void*, Vector3*, Vector3*);
void (*orig_SetAim)(void*, float, float);
void (*orig_FireCheck)(void*);
float (*orig_GetHealth)(void*);
bool (*orig_IsDead)(void*);

NSString* GetUDID() {
    return [[[UIDevice currentDevice] identifierForVendor] UUIDString];
}

Vector3 GetHeadPosition(void* entity) {
    Vector3 pos = {0,0,0};
    if (!entity) return pos;
    uintptr_t* p = (uintptr_t*)entity;
    uintptr_t transformNode = p[OFF_TRANSFORM_NODE / 4];
    if (!transformNode) return pos;
    uintptr_t headTransform = *(uintptr_t*)(transformNode + OFF_HEAD_TF);
    if (!headTransform) return pos;
    pos.x = *(float*)(headTransform + 0x10);
    pos.y = *(float*)(headTransform + 0x14);
    pos.z = *(float*)(headTransform + 0x18);
    return pos;
}

void* GetLocalPlayer() {
    return (void*)(*(uintptr_t*)(base + OFF_LOCAL_PLAYER));
}

void* GetCamera() {
    return (void*)(*(uintptr_t*)(base + OFF_CAMERA_MAIN));
}

Vector3 GetLocalPosition(void* player) {
    Vector3 pos = {0,0,0};
    if (!player) return pos;
    uintptr_t* p = (uintptr_t*)player;
    uintptr_t node = p[OFF_TRANSFORM_NODE / 4];
    if (!node) return pos;
    pos.x = *(float*)(node + 0x10);
    pos.y = *(float*)(node + 0x14);
    pos.z = *(float*)(node + 0x18);
    return pos;
}

float GetHealth(void* entity) {
    if (!entity || !orig_GetHealth) return 100.0f;
    return orig_GetHealth(entity);
}

bool IsDead(void* entity) {
    if (!entity || !orig_IsDead) return false;
    return orig_IsDead(entity);
}

void* GetBestEnemy() {
    uintptr_t dictEntitiesPtr = base + OFF_DICT_ENTITIES;
    if (!dictEntitiesPtr) return NULL;
    void* dict = *(void**)dictEntitiesPtr;
    if (!dict) return NULL;
    NSDictionary* entityDict = (__bridge NSDictionary*)dict;
    if (!entityDict || entityDict.count == 0) return NULL;
    void* bestEnemy = NULL;
    float bestDist = FLT_MAX;
    Vector3 localPos = GetLocalPosition(GetLocalPlayer());
    void* localPlayer = GetLocalPlayer();
    for (id key in entityDict) {
        void* entity = (__bridge void*)[entityDict objectForKey:key];
        if (!entity || entity == localPlayer) continue;
        #if IGNORE_DEAD
        if (IsDead(entity)) continue;
        #endif
        Vector3 headPos = GetHeadPosition(entity);
        if (headPos.x == 0 && headPos.y == 0 && headPos.z == 0) continue;
        float dx = headPos.x - localPos.x;
        float dy = headPos.y - localPos.y;
        float dz = headPos.z - localPos.z;
        float dist = sqrt(dx*dx + dy*dy + dz*dz);
        if (dist < bestDist && dist < LOCK_DISTANCE) {
            bestDist = dist;
            bestEnemy = entity;
        }
    }
    return bestEnemy;
}

void CalculateAngle(Vector3 target, Vector3 local, float* yaw, float* pitch) {
    Vector3 delta = { target.x - local.x, target.y - local.y, target.z - local.z };
    float dist = sqrt(delta.x*delta.x + delta.y*delta.y + delta.z*delta.z);
    if (dist < 0.001f) return;
    *yaw = atan2(delta.y, delta.x) * 180.0f / M_PI;
    *pitch = asin(delta.z / dist) * 180.0f / M_PI;
}

void hook_WorldToScreen(void* camera, Vector3* worldPos, Vector3* screenPos) {
    orig_WorldToScreen(camera, worldPos, screenPos);
    if (!isLicensed || !aimlockEnabled) return;
    if (lockedEnemy && !IsDead(lockedEnemy)) {
        Vector3 headPos = GetHeadPosition(lockedEnemy);
        Vector3 localPos = GetLocalPosition(GetLocalPlayer());
        float yaw, pitch;
        CalculateAngle(headPos, localPos, &yaw, &pitch);
        targetYaw = yaw;
        targetPitch = pitch;
        isLocked = true;
        return;
    }
    void* enemy = GetBestEnemy();
    if (!enemy) {
        isLocked = false;
        lockedEnemy = NULL;
        return;
    }
    lockedEnemy = enemy;
    Vector3 headPos = GetHeadPosition(enemy);
    Vector3 localPos = GetLocalPosition(GetLocalPlayer());
    float yaw, pitch;
    CalculateAngle(headPos, localPos, &yaw, &pitch);
    targetYaw = yaw;
    targetPitch = pitch;
    isLocked = true;
}

void hook_SetAim(void* player, float x, float y) {
    if (!isLicensed || !aimlockEnabled || !isLocked || !lockedEnemy) {
        orig_SetAim(player, x, y);
        return;
    }
    Vector3 headPos = GetHeadPosition(lockedEnemy);
    Vector3 localPos = GetLocalPosition(GetLocalPlayer());
    float yaw, pitch;
    CalculateAngle(headPos, localPos, &yaw, &pitch);
    #if AIM_HEAD
    pitch -= HEADSHOT_OFFSET;
    #endif
    #if SILENT_AIM
    #else
    orig_SetAim(player, yaw, pitch);
    #endif
}

void hook_FireCheck(void* weapon) {
    #if AUTO_SHOOT
    if (isLicensed && aimlockEnabled && isLocked) {}
    #endif
    orig_FireCheck(weapon);
}

float hook_GetHealth(void* entity) {
    if (!entity) return 0;
    return orig_GetHealth(entity);
}

bool hook_IsDead(void* entity) {
    if (!entity) return true;
    return orig_IsDead(entity);
}

%ctor {
    isLicensed = [GetUDID() isEqualToString:UDID_TARGET];
    if (!isLicensed) {
        NSLog(@"[AimLock] UDID không khớp");
        return;
    }
    base = (uintptr_t)dlopen("/var/containers/Bundle/Application/.../FreeFire.app/Frameworks/UnityFramework.framework/UnityFramework", RTLD_NOW);
    if (!base) {
        base = (uintptr_t)dlopen("/var/containers/Bundle/Application/.../FreeFire.app/Frameworks/libil2cpp.dylib", RTLD_NOW);
    }
    if (!base) base = 0x100000000;
    MSHookFunction((void*)(base + OFF_WORLD_TO_SCREEN), (void*)hook_WorldToScreen, (void**)&orig_WorldToScreen);
    MSHookFunction((void*)(base + OFF_SET_AIM), (void*)hook_SetAim, (void**)&orig_SetAim);
    MSHookFunction((void*)(base + OFF_FIRE_CHECK), (void*)hook_FireCheck, (void**)&orig_FireCheck);
    if (OFF_HEALTH != 0) {
        MSHookFunction((void*)(base + OFF_HEALTH), (void*)hook_GetHealth, (void**)&orig_GetHealth);
    }
    if (OFF_IS_DEAD != 0) {
        MSHookFunction((void*)(base + OFF_IS_DEAD), (void*)hook_IsDead, (void**)&orig_IsDead);
    }
    NSLog(@"[AimLock MAX] Loaded on UDID: %@", GetUDID());
}