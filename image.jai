// Gamma corrected (linear) premultiplied alpha format loaded image; RGBA8 format (32bits)
Image :: struct {
    width: u32;
    height: u32;

    width_over_height: float; @NonSerializeField

    data: *u8; @NonSerializeField
}