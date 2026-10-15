// Local C ABI for the pinned whisper.cpp runtime. Audio and text stay in memory.
#include "whisper.h"
#include <algorithm>
#include <cstring>
#include <string>
#include <thread>
static void quiet_log(enum ggml_log_level, const char *, void *) {}
extern "C" {
void * saywing_whisper_open(const char * model) {
    try {
        whisper_log_set(quiet_log, nullptr);
        auto params = whisper_context_default_params();
        params.use_gpu = false;
        return whisper_init_from_file_with_params(model, params);
    } catch (...) { return nullptr; }
}
void saywing_whisper_close(void * context) {
    if (context) whisper_free(static_cast<whisper_context *>(context));
}
int saywing_whisper_tokens(void * context, const char * text) {
    if (!context || !text) return -1;
    return -whisper_tokenize(static_cast<whisper_context *>(context), text, nullptr, 0);
}
int saywing_whisper_transcribe(void * context, const float * samples, int count,
                              const char * language, const char * prompt, char * output, int capacity) {
    if (!context || !samples || count < 1 || count > 16000 * 60 || !output || capacity < 1) return -1;
    try {
        auto ctx = static_cast<whisper_context *>(context);
        auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        params.n_threads = std::min(8u, std::max(1u, std::thread::hardware_concurrency() / 2));
        params.translate = false; params.no_context = true; params.no_timestamps = true;
        params.print_realtime = params.print_progress = params.print_timestamps = params.print_special = false;
        params.language = language; params.initial_prompt = prompt;
        params.temperature = 0.0f; params.temperature_inc = 0.0f; params.suppress_nst = true;
        if (whisper_full(ctx, params, samples, count) != 0) return -2;
        std::string text;
        for (int i = 0; i < whisper_full_n_segments(ctx); ++i) {
            const char * segment = whisper_full_get_segment_text(ctx, i);
            if (!segment || text.size() + std::strlen(segment) >= static_cast<size_t>(capacity)) return -3;
            text += segment;
        }
        std::memcpy(output, text.c_str(), text.size() + 1);
        return static_cast<int>(text.size());
    } catch (...) { return -4; }
}
}
