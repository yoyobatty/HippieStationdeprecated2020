"""proc: node-graph generation for mapforge (the Houdini way).

A department is a chain of small nodes. Each node takes the geometry (tiles with attributes, rooms, placed pieces),
changes it and hands it on. Nothing is drawn by coordinate: the outline comes from the map, the rooms from a slicing
tree snapped to the outline's fixed doors, the furniture from room assets that read tile fields (which wall is
behind a tile, how far the door is, where people walk). Every node's output can be drawn, so a mistake shows at the
node that made it.

    geo.py      Geo (the geometry), Graph (the node chain), draw() (one schematic picture per node)
    shell.py    outline, slice, tidy, openings, fields: the structure nodes
    place.py    kits (authored groups of pieces with their use tiles) and the placer that sets them on fields
    emit.py     Geo -> a mapforge blueprint (LAYOUT/ROOMS/LEGEND/ROOMDEFS) for forge.build
"""
