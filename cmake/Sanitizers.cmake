# Adds AddressSanitizer + UndefinedBehaviorSanitizer when DIPPER_SANITIZERS=ON.
function(dipper_enable_sanitizers target)
    if(DIPPER_SANITIZERS AND NOT MSVC)
        target_compile_options(${target} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
        target_link_options(${target} PRIVATE -fsanitize=address,undefined)
    endif()
endfunction()
