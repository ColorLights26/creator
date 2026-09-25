#ifndef CREATOR_ABI_H
#define CREATOR_ABI_H
#include <stdint.h>
#include <stddef.h>
#if defined(_WIN32)
#define CP_API __declspec(dllexport)
#else
#define CP_API __attribute__((visibility("default"))) __attribute__((used))
#endif
#ifdef __cplusplus
extern "C" {
#endif
typedef struct CPInstance CPInstance;
// ABI 1. Returned command memory is owned by the instance, until its next
// update/render/reset/destruction. Consume synchronously; never retain pointers.
CP_API uint32_t cp_abi_version(void);
CP_API void* cp_allocate(size_t size);
CP_API void cp_free(void* memory);
CP_API const char* cp_program_hash(const char* program);
CP_API CPInstance* cp_create(const char* program, const char* expected_hash, uint32_t seed);
CP_API void cp_destroy(CPInstance* instance);
CP_API const char* cp_error(CPInstance* instance);
CP_API int32_t cp_reset(CPInstance* instance, uint32_t seed);
// options: intensity,speed,detail,glow followed by 4 straight RGBA colors.
CP_API int32_t cp_configure(CPInstance* instance, const float* options, uint32_t count,
                           int32_t reactive, int32_t playing, double host_time);
CP_API int32_t cp_consume(CPInstance* instance, const uint8_t* bytes, uint32_t size);
CP_API int32_t cp_update(CPInstance* instance, double width, double height,
                        double host_time, int32_t reduced_motion);
CP_API int32_t cp_draw(CPInstance* instance);
CP_API const float* cp_commands(CPInstance* instance);
CP_API uint32_t cp_command_length(CPInstance* instance);
CP_API double cp_update_micros(CPInstance* instance);
#ifdef __cplusplus
}
#endif
#endif
