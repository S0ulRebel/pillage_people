# Corrected stern and decks

Bow visual correction: use ../../09-symmetric-closed-bow-v1.png instead of the U_BOW and F_BOW panels in sheet 08. Both sides mirror about the centreline, join at the closed prow and leave the broad rear open. This illustration pass does not change the supplied metric mesh; its nose remains narrowly capped, not mathematically sharp.

This revision replaces v2 for multi-deck construction. Use this folder's contract, meshes and assembled examples. Keep the base v1 bow and middle hull sections, but replace H03_STERN with H03_ROUND_STERN.

U_STERN is a constant-height rounded rear wall, open fore, top and bottom. Its upper and lower footprints match. F_STERN follows its inner curved outline; R_STERN is for the topmost deck only. Raised cabin structures remain separate attachments above the highest deck.

F_BOW is tapered, F_MID rectangular and F_STERN rounded. All have flat surfaces and 0.18 m thickness. No raised corner columns, posts or curbs. Floors sit at 2.6, 5.2 and optionally 7.8 m. Stairs and slots retain the v2 layout and dimensions.

Use ../../08-corrected-stern-and-decks-v1.png for material styling. Use drawings/corrected-modules.png for an exact projected mesh preview. The concept image cannot establish dimensions. Earlier concept sheets with elevated stern sections or floor posts are superseded for these modules.

The package contains construction blockouts, not finished textured game models. Preserve metre scale and connection vertices within 1 mm. Add styling away from the 0.10 m protected join zones. The new lower stern's fore interface remains HULL_U6. Do not combine rounded upper stern tiers with the old flat transom hull.

Regenerate with ../build_rounded_stern.py. Validation checks exported connection footprints and flat floor bounds. Final model collision and gameplay traversal still need testing after modeling.
