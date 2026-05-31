#include <windows.h>

typedef struct { void* vtbl; } IUnknown;
typedef long HRESULT;

BOOL WINAPI DllMain(HINSTANCE h, DWORD r, LPVOID p) { return TRUE; }

/* Minimal IActivationFactory vtable - returns error codes instead of crashing */
static HRESULT WINAPI stub_QueryInterface(void* self, void* riid, void** out) {
    *out = NULL;
    return 0x80004002L; /* E_NOINTERFACE */
}
static unsigned long WINAPI stub_AddRef(void* self) { return 1; }
static unsigned long WINAPI stub_Release(void* self) { return 1; }
static HRESULT WINAPI stub_GetIids(void* self, unsigned long* c, void** i) { *c = 0; return 0; }
static HRESULT WINAPI stub_GetRuntimeClassName(void* self, void** n) { *n = NULL; return 0; }
static HRESULT WINAPI stub_GetTrustLevel(void* self, int* t) { *t = 0; return 0; }
static HRESULT WINAPI stub_ActivateInstance(void* self, void** inst) { *inst = NULL; return 0x80004001L; }

static void* factory_vtbl[] = {
    stub_QueryInterface, stub_AddRef, stub_Release,
    stub_GetIids, stub_GetRuntimeClassName, stub_GetTrustLevel,
    stub_ActivateInstance
};

static IUnknown factory_instance = { factory_vtbl };

__declspec(dllexport) HRESULT WINAPI DllGetActivationFactory(void* classId, void** factory) {
    if (factory) {
        *factory = &factory_instance;
        return 0; /* S_OK - return dummy factory instead of NULL */
    }
    return 0x80004003L; /* E_POINTER */
}
