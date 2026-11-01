// Owns its storage. Struct copies share ownership; clear the storage only once.
Binary :: struct {
    data: [..]u8;
}

// Borrows mutable bytes; the backing storage must outlive the view.
BinaryView :: []u8;

// Creates a zero-filled buffer.
make_binary :: inline (size: s64) -> Binary {
    return make_binary(size, 0);
}

make_binary :: inline (size: s64, default_value: u8) -> Binary {
    result: Binary;
    array_resize(*result.data, size, false);
    if size > 0 {
        memset(result.data.data, default_value, size);
    }
    return result;
}

shallow_copy_binary :: inline (data: *u8, size: s64) -> Binary {
    result: Binary;
    result.data.data = data;
    result.data.count = size;
    result.data.allocated = size;
    remember_allocators(*result.data);
    return result;
}

deep_copy_binary :: inline (data: *u8, size: s64) -> Binary {
    result: Binary;
    array_resize(*result.data, size, false);
    if size > 0 {
        memcpy(result.data.data, data, size);
    }
    return result;
}

shallow_copy_binary :: inline (binary: Binary) -> Binary {
    shallow_copy_binary(binary.data, binary.size);
}

deep_copy_binary :: inline (binary: Binary) -> Binary {
    deep_copy_binary(binary.data, binary.size);
}

try_make_binary :: inline (size: s64, default_value: u8 = 0) -> Binary, bool {
    if size < 0 {
        return .{}, false;
    }

    if size == 0 {
        return .{}, true;
    }

    data := cast(*u8)alloc(size);
    if data == null {
        return .{}, false;
    }

    memset(data, default_value, size);
    return shallow_copy_binary(data, size), true;
}

try_deep_copy_binary :: inline (data: *u8, size: s64) -> Binary, bool {
    if size < 0 || (size > 0 && data == null) {
        return .{}, false;
    }

    if size == 0 {
        return .{}, true;
    }

    copy := cast(*u8)alloc(size);
    if copy == null {
        return .{}, false;
    }

    memcpy(copy, data, size);
    return shallow_copy_binary(copy, size), true;
}

get_binary_data :: inline (binary: Binary) -> *u8 {
    return binary.data.data;
}

get_binary_size :: inline (binary: Binary) -> s64 {
    return binary.data.count;
}

clear_binary :: inline (binary: *Binary) {
    if binary == null {
        return;
    }
    array_reset(*binary.data);
    binary.* = .{};
}

make_binary_view :: inline (binary: Binary) -> BinaryView {
    return make_binary_view(binary.data.data, binary.data.count);
}

make_binary_view :: inline (data: *u8, size: s64) -> BinaryView {
    result: BinaryView;
    result.data = data;
    result.count = size;
    return result;
}

is_empty_binary_view :: inline (view: BinaryView) -> bool {
    return view.count == 0;
}

#scope_file
#import "Basic";
