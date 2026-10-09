# Vibe Remote app icon

Updated on 2026-10-08 with the built-in image_gen tool. The user requested the silver
Xiaomi Bluetooth Remote 2 Pro from their product photo, followed by a prominent "Vibe"
wordmark. The hardware silhouette, direction ring and button layout follow that reference;
mint lettering and a microphone highlight identify this independent voice-control app.
No Xiaomi/MI wordmarks are included. The supplied reference photo is not bundled.

On 2026-10-09, the enlarged remote + Vibe design was promoted from
`Proposals/AppIcon-pro2-vibe-closeup.png` to the canonical `AppIcon.png` for 0.2.4.
Its full prompt and reference provenance remain in `Proposals/README.md`.
The 0.2.2–0.2.3 full-remote design is retained as `AppIcon-pro2-vibe-full.png`;
the historical prompts below describe that earlier design.

`AppIcon.png` is the unmodified close-up generated source with real transparency.
`../AppIcon.icns` contains ten standard 16–1024 pixel representations. Rebuild it with
`bash scripts/build_macos_icon.sh` (sips/iconutil resizing and format conversion only).
Normal app builds consume the checked-in ICNS and require no image-generation service.
The branded Pro 2 design starts in 0.2.2.

Earlier designs are preserved: `AppIcon-v1.png` is the generic remote (prompt in
`README-v1.md`); `AppIcon-pro2.png` is the silver Pro 2 without the wordmark.

## Hardware-reference edit prompt

Use case: precise-object-edit. Asset type: finished Vibe Remote macOS app icon. Image 1 is the current icon to update; image 2 is the user's Xiaomi Bluetooth Remote 2 Pro product reference. Replace ONLY the central generic white capsule remote from image 1 with an original polished rendering clearly recognizable as the actual silver Xiaomi Remote 2 Pro in image 2. Preserve image 1's dark graphite rounded-square tile, subtle dimensional finish and real transparent exterior. Hardware identity is critical: long straight slim brushed-silver rectangular body, nearly flat ends with softly rounded edges, two small outlined circular power/microphone keys at the top, very prominent large black circular directional ring with black circular OK center, below it black round back/home/menu/TV buttons on the left/lower portion and the vertical black plus/minus rocker on the right. Keep this recognizable real button arrangement. Use simplified clean engraved symbols without tiny labels. Show the whole remote large and centered, gently tilted about 12 degrees with top to the right, front face readable; proportions faithful to the reference rather than the old capsule. Restrained silver metal highlights, high-quality tactile macOS icon rendering, clean geometry readable at small sizes. A subtle mint highlight around the microphone key can connect to the app's voice function. No orange MI logo, no Xiaomi wordmark, no NFC lettering, no app name, no text outside the hardware, no waves floating around it, no additional objects, no multi-option sheet, no mockup scene. Do not copy the white product-photo backdrop. Square canvas, icon fills canvas with modest transparent outer margin, genuine alpha around the rounded-square tile, no exterior shadow.

## Final brand edit prompt

Use case: text-localization and precise-object-edit. Edit this Vibe Remote app icon to make the brand much more prominent. Preserve the recognizable Xiaomi Remote 2 Pro silver rectangular hardware, black circular directional pad, authentic button layout, mint-highlighted microphone key, dark graphite rounded-square macOS tile and real alpha outside the tile. Make the silver remote stand out more with brighter clean metal edges and stronger controlled contrast against a slightly darker tile. Add exactly the word "Vibe" (capital V, lowercase i b e), large and highly legible, as the foreground brand word across the lower part of the tile. This is the primary requested change: Vibe should be unmistakable and still readable at a small app-icon size. Use a bold rounded geometric sans-serif wordmark, substantial letter strokes, crisp mint-teal color with restrained tactile thickness, approximately 65–70% of the tile width. Recompose the remote slightly upward if needed, keeping the important top keys, black direction ring, lower control buttons and most of the silver body visible. Let the Vibe wordmark overlap a little in front of the remote's lower blank body, with clean purposeful separation and comfortable bottom padding. The wordmark must be nearly horizontal; the remote can retain its modest diagonal tilt. Keep one coherent premium utility-app icon, not a poster. No additional text, no Xiaomi or MI logos, no promotional badges, no extra symbols, no mockup scene, no heavy glow. Transparent corners and outer margin. Exact visible text: Vibe.
