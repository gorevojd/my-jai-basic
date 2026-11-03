// Uses MyHashSet operations on names.set; Name storage is interned and must not be freed.
// Example: names: Name_Set; add(*names.set, make_name("player"));
Name_Set :: struct {
    using set: HashSet(Name, name_hash, names_equal);
}
