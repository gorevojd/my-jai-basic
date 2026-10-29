Basic :: #import "Basic";

// Returns the first matching byte offset, or -1 for no match or an empty substring (like Jai's String module).
// Case-sensitive, byte-exact search; supports embedded zeros and does not require null termination.
// No allocations. Short needles use a direct scan; longer needles use Boyer-Moore-Horspool skips.
// Skips reduce candidate comparisons on varied text, but worst-case time remains O(s.count * substring.count).
find_substring :: (s: string, substring: string) -> int {
    if substring.count == 0 || substring.count > s.count {
        return -1;
    }

    last_start := s.count - substring.count;
    last_byte := substring.count - 1;
    SHORT_NEEDLE_LIMIT :: 4;
    if substring.count <= SHORT_NEEDLE_LIMIT {
        for offset: 0..last_start {
            if s[offset] != substring[0] {
                continue;
            }
            if string.{substring.count, s.data + offset} == substring {
                return offset;
            }
        }
        return -1;
    }

    BYTE_VALUE_COUNT :: 256;
    skip: [BYTE_VALUE_COUNT] int;
    for *distance: skip {
        distance.* = substring.count;
    }
    for index: 0..last_byte - 1 {
        skip[substring[index]] = last_byte - index;
    }

    offset: int = 0;
    while offset <= last_start {
        tail := s[offset + last_byte];
        if tail == substring[last_byte] {
            if string.{substring.count, s.data + offset} == substring {
                return offset;
            }
        }
        distance := skip[tail];
        // Test the remaining range before adding, including for strings near the integer limit.
        if distance > last_start - offset {
            break;
        }
        offset += distance;
    }
    return -1;
}

// Splits on a complete separator string, preserving leading, repeated and trailing empty fields.
// An empty separator returns one field containing s, including when s is empty.
// Fields borrow s's storage. Free only the returned array with Basic.array_free.
split :: (s: string, separator: string = " ") -> [..] string {
    result: [..] string;
    if separator.count == 0 {
        Basic.array_add(*result, s);
        return result;
    }

    first: int = 0;
    cursor: int = 0;
    while cursor <= s.count - separator.count {
        candidate := string.{separator.count, s.data + cursor};
        if candidate == separator {
            Basic.array_add(*result, string.{cursor - first, s.data + first});
            cursor += separator.count;
            first = cursor;
        }
        else {
            cursor += 1;
        }
    }

    Basic.array_add(*result, string.{s.count - first, s.data + first});
    return result;
}

// Allocates one buffer using context.allocator. Free a nonempty result with Basic.free(result.data).
join :: (strings_to_join: [] string, separator: string = "") -> string {
    if strings_to_join.count == 0 {
        return "";
    }

    count := (strings_to_join.count - 1) * separator.count;
    for part: strings_to_join {
        count += part.count;
    }
    if count == 0 {
        return "";
    }

    result := Basic.alloc_string(count);
    cursor := result.data;
    for part, index: strings_to_join {
        if index > 0 && separator.count > 0 {
            memcpy(cursor, separator.data, separator.count);
            cursor += separator.count;
        }
        if part.count > 0 {
            memcpy(cursor, part.data, part.count);
            cursor += part.count;
        }
    }
    return result;
}

// Decodes complete Unicode code points. Each malformed byte becomes U+FFFD.
// Free the returned array with Basic.array_free.
string_to_utf8_codepoints :: (s: string) -> [..] u32 {
    result: [..] u32;
    cursor: int = 0;
    while cursor < s.count {
        code_point, byte_count, valid := decode_utf8_character(s, cursor);
        if !valid {
            code_point = Unicode.UNI_REPLACEMENT_CHAR;
            byte_count = 1;
        }
        Basic.array_add(*result, code_point);
        cursor += byte_count;
    }
    return result;
}

// Encodes Unicode scalar values as UTF-8. Surrogates and values above U+10FFFF become U+FFFD.
// Free a nonempty result with Basic.free(result.data).
utf8_codepoints_to_string :: (codepoints: [] u32) -> string {
    if codepoints.count == 0 {
        return "";
    }

    MAX_UTF8_CHARACTER_BYTES :: 4;
    buffer: [MAX_UTF8_CHARACTER_BYTES] u8;
    count: int = 0;
    for code_point: codepoints {
        encoded := string.{buffer.count, buffer.data};
        Unicode.character_utf32_to_utf8(sanitize_unicode_code_point(code_point), *encoded);
        count += encoded.count;
    }

    result := Basic.alloc_string(count);
    cursor := result.data;
    for code_point: codepoints {
        encoded := string.{buffer.count, buffer.data};
        Unicode.character_utf32_to_utf8(sanitize_unicode_code_point(code_point), *encoded);
        memcpy(cursor, encoded.data, encoded.count);
        cursor += encoded.count;
    }
    return result;
}

// Trims spaces, newlines, carriage returns and tabs. Other UTF-8 bytes remain unchanged.
// Returns a borrowed slice; never free it separately from s.
trim :: (s: string) -> string {
    if s.count == 0 {
        return s;
    }

    ASCII_VALUE_COUNT :: 128;
    character_should_be_trimmed_map: [ASCII_VALUE_COUNT] bool;
    character_should_be_trimmed_map[cast(int) #char "\n"] = true;
    character_should_be_trimmed_map[cast(int) #char "\r"] = true;
    character_should_be_trimmed_map[cast(int) #char "\t"] = true;
    character_should_be_trimmed_map[cast(int) #char " "] = true;

    first: int = 0;
    end := s.count;

    while (first < end &&
           s[first] < character_should_be_trimmed_map.count &&
           character_should_be_trimmed_map[s[first]]) {
        first += 1;
    }

    while (end > first &&
           s[end - 1] < character_should_be_trimmed_map.count &&
           character_should_be_trimmed_map[s[end - 1]]) {
        end -= 1;
    }

    return string.{end - first, s.data + first};
}

// Trims complete Unicode code points from the set supplied in trim_characters.
// Matching is exact, without normalization or grapheme-cluster matching.
// Returns a borrowed slice. Malformed UTF-8 in either argument leaves s unchanged.
trim :: (s: string, trim_characters: string) -> string {
    if s.count == 0 || trim_characters.count == 0 {
        return s;
    }

    character_should_be_trimmed_map: HashTable.Table(u32, bool);
    defer HashTable.deinit(*character_should_be_trimmed_map);

    cursor: int = 0;
    while cursor < trim_characters.count {
        code_point, byte_count, valid := decode_utf8_character(trim_characters, cursor);
        if !valid {
            return s;
        }
        HashTable.table_add(*character_should_be_trimmed_map, code_point, true);
        cursor += byte_count;
    }

    // Scan complete code points, recording the first and last characters outside the trim set.
    // This also validates interior UTF-8 before returning a modified slice.
    first := s.count;
    end := s.count;
    cursor = 0;
    while cursor < s.count {
        code_point, byte_count, valid := decode_utf8_character(s, cursor);
        if !valid {
            return s;
        }
        if !HashTable.table_contains(*character_should_be_trimmed_map, code_point) {
            if first == s.count {
                first = cursor;
            }
            end = cursor + byte_count;
        }
        cursor += byte_count;
    }

    return string.{end - first, s.data + first};
}

// Splits "Group|SubGroup|SubSubGroup" and trims whitespace around every entry, preserving empty entries.
// Entries borrow groups_string's storage. Free only the returned array with Basic.array_free.
decode_groups :: (groups_string: string) -> [..] string {
    groups := split(groups_string, "|");
    for *group: groups {
        group.* = trim(group.*);
    }
    return groups;
}

#scope_file
Unicode :: #import "Unicode";
HashTable :: #import "Hash_Table";

decode_utf8_character :: (s: string, offset: int) -> (code_point: u32, byte_count: int, valid: bool) {
    // The standard decoder's strict mode still accepts a lone continuation byte as ASCII.
    // Reject invalid leading bytes before asking it to validate the remaining sequence.
    FIRST_MULTIBYTE_LEAD :: 0xC2;
    LAST_MULTIBYTE_LEAD :: 0xF4;
    ASCII_VALUE_COUNT :: 128;
    lead := s[offset];
    if lead >= ASCII_VALUE_COUNT && (lead < FIRST_MULTIBYTE_LEAD || lead > LAST_MULTIBYTE_LEAD) {
        return 0, 0, false;
    }

    code_point, byte_count, result := Unicode.character_utf8_to_utf32(s.data + offset, s.count - offset, true);
    return code_point, byte_count, result == .CONVERSION_OK;
}

sanitize_unicode_code_point :: (code_point: u32) -> u32 {
    MAX_UNICODE_CODE_POINT :: 0x10FFFF;
    SURROGATE_FIRST :: 0xD800;
    SURROGATE_LAST :: 0xDFFF;
    if code_point > MAX_UNICODE_CODE_POINT || (code_point >= SURROGATE_FIRST && code_point <= SURROGATE_LAST) {
        return Unicode.UNI_REPLACEMENT_CHAR;
    }
    return code_point;
}
