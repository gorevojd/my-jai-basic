/*
    Name is an interned string identifier. make_name stores one immutable copy of each distinct
    byte string in a shared, thread-safe table. Each Name holds a string descriptor referencing
    that canonical storage; copying a Name does not copy its text. Equality compares data pointers,
    and name_hash hashes the pointer with Knuth multiplication, both independent of text length.
    Matching is case-sensitive and byte-exact, without Unicode normalization.

    Good uses:
    - Repeated asset, animation, event or configuration-defined identifiers used as lookup keys.
    - Names shared by many objects, where deduplication avoids storing repeated copies of text.
    - Interning at loading/input boundaries, then retaining Name values for frequent comparisons
      and hash-table lookups. Name_Table(Value_Type) supplies the key type and callbacks.

    Poor uses:
    - One-off strings, mutable text, chat messages or unbounded unique input: interning adds work,
      and this implementation retains every distinct nonempty string until process exit.
    - Repeatedly converting raw strings in a hot loop: make_name still hashes their contents and
      takes a mutex, even when a nonempty name already exists. Retain the returned Name instead.
    - Audio callbacks or other operations with strict latency limits: make_name may wait on a
      mutex, allocate or grow the table. Copying, comparing and hashing existing Names do not.
    - Persistent or network identifiers: pointer identities and hashes are process-local. Serialize
      the text and intern it again on load. A hash is not a unique identifier; collisions are possible.
    - Closed sets of categories or states: prefer a named enum when the set is known in code.

    Construct through make_name; never modify or free name.text or its bytes. The input only needs
    to stay valid and unchanged during the call. A zero-initialized Name is the empty name.
*/
Name :: struct {
    text: string;
}

// Uses the standard Hash_Table operations. No synchronization is added to individual tables.
// Example: scores: Name_Table(s64); HashTable.table_add(*scores.table, make_name("player"), 100);
Name_Table :: struct (Value_Type: Type) {
    using table: Tables.Table(Name, Value_Type, name_hash, names_equal);
}

operator == :: (a: Name, b: Name) -> bool {
    return names_equal(a, b);
}

/*
    Intern once at input boundaries and retain the Name for subsequent lookups.
    Incoming bytes must remain unchanged for this call.

    Do not call on an audio callback for example:
    Because make_name can lock a mutex and allocate memory:
    - Another thread may hold the mutex, forcing the audio callback to wait.
    - A new name requires copying the string and possibly growing the hash table.
    - The first call also initializes synchronization.
*/
make_name :: (text: string) -> Name {
    if text.count == 0 {
        return .{};
    }

    ensure_name_storage();
    Threads.lock(*name_storage.mutex);
    defer Threads.unlock(*name_storage.mutex);

    found, canonical := Tables.table_find(*name_storage.by_text, text);
    if found {
        return .{canonical};
    }

    // Never inherit a caller's temporary allocator. The default allocator must be process-lived.
    Basic.push_allocator(context.default_allocator);
    canonical = Basic.copy_string(text);
    Tables.table_add(*name_storage.by_text, canonical, canonical);
    return .{canonical};
}

name_hash :: (name: Name) -> u32 {
    // Knuth multiplicative hashing: retain high bits, not aligned pointer low bits.
    return cast(u32) (Hash.knuth_hash(cast(u64) name.text.data) >> 32);
}

names_equal :: (a: Name, b: Name) -> bool {
    return a.text.data == b.text.data;
}

#scope_file
Hash :: #import "Hash";
Tables :: #import "Hash_Table";
Threads :: #import "Thread";
Atomics :: #import "Atomics";

Name_Storage_Status :: enum u32 {
    Uninitialized;
    Initializing;
    Ready;
}

Name_Storage :: struct {
    status: Name_Storage_Status;
    mutex: Threads.Mutex;
    by_text: Tables.Table(string, string);
}

name_storage: Name_Storage;

ensure_name_storage :: () {
    if compare_and_swap(*name_storage.status, .Uninitialized, .Initializing) {
        Threads.init(*name_storage.mutex);
        Atomics.atomic_swap(*name_storage.status, .Ready);
        return;
    }
    // CAS supplies synchronization even where the standard atomic_read is just a plain load.
    while !compare_and_swap(*name_storage.status, .Ready, .Ready) {
        Basic.sleep_milliseconds(0);
    }
}
