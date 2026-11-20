# Adds AddressSanitizer + UndefinedBehaviorSanitizer when HTTPLOGGER_SANITIZERS=ON.
function(httplogger_enable_sanitizers target)
    if(HTTPLOGGER_SANITIZERS AND NOT MSVC)
        target_compile_options(${target} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
        target_link_options(${target} PRIVATE -fsanitize=address,undefined)
    endif()
endfunction()
