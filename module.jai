#load "string_utils.jai";
#load "name.jai";
#load "image.jai";
#load "sound.jai";
#load "binary.jai";
#load "checked_allocation.jai";

/**
 * @brief Copies a string, returning false before copying if allocation fails.
 * @param[in] source Valid source bytes.
 * @return Owned string and success flag. Free the string in the allocation context. Empty strings succeed without allocating.
 */
try_copy_string :: (source: string) -> string, bool {
    if source.count < 0 || (source.count > 0 && source.data == null) {
        return "", false;
    }

    if source.count == 0 {
        return "", true;
    }

    result: string;
    result.data = cast(*u8)alloc(source.count);
    if result.data == null {
        return "", false;
    }

    result.count = source.count;
    memcpy(result.data, source.data, source.count);
    return result, true;
}

#scope_module
#import "Basic";

