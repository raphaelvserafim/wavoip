#include <windows.h>

BOOL WINAPI DllMain(HINSTANCE h, DWORD r, LPVOID p) { return TRUE; }

/* Minimal IActivationFactory vtable - returns error codes instead of crashing */
static HRESULT WINAPI stub_QueryInterface(void* self, REFIID riid, void** out) {
    *out = NULL;
    return E_NOINTERFACE;
}
static ULONG WINAPI stub_AddRef(void* self) { return 1; }
static ULONG WINAPI stub_Release(void* self) { return 1; }
static HRESULT WINAPI stub_GetIids(void* self, ULONG* c, void** i) { *c = 0; return S_OK; }
static HRESULT WINAPI stub_GetRuntimeClassName(void* self, void** n) { *n = NULL; return S_OK; }
static HRESULT WINAPI stub_GetTrustLevel(void* self, int* t) { *t = 0; return S_OK; }
static HRESULT WINAPI stub_ActivateInstance(void* self, void** inst) { *inst = NULL; return E_NOTIMPL; }

static void* factory_vtbl[] = {
    stub_QueryInterface, stub_AddRef, stub_Release,
    stub_GetIids, stub_GetRuntimeClassName, stub_GetTrustLevel,
    stub_ActivateInstance
};

static struct { void* vtbl; } factory_instance = { factory_vtbl };

__declspec(dllexport) HRESULT WINAPI DllGetActivationFactory(void* classId, void** factory) {
    if (factory) {
        *factory = &factory_instance;
        return S_OK;
    }
    return E_POINTER;
}
