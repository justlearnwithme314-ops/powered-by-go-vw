# Transparent building blocks

Adds solid, placeable `building:glass`, using the supplied assorted texture
pack's `default_glass.png`. Smelt one sand into one glass with furnace fuel.
For testing: `/give building:glass 64`.

The glass material uses alpha cutout, so its clear pixels do not cover blocks
behind it or cast solid shadows. Leaves already use the same cutout technique:
leaf pixels cast shade and gaps transmit light. This does not introduce a new
voxel skylight simulation; it uses the existing renderer's lighting and shadows.

The registry's native model adapter maps transparent content metadata to actual
mesher culling properties. Neighbor faces remain visible behind foliage, glass,
water and ice. Opaque blocks keep their face-removal optimization.

Verified with `tests/TransparentBlocksSmoke.tscn`, including actual native mesh
face counts for touching opaque/transparent block pairs.
