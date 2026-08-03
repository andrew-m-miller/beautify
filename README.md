# MT_BeautyFS

A frequency separation beauty shader for Autodesk Flame, built as a multi-pass
Matchbox. It splits the front into three frequency bands, lets you soften or
boost each one independently, and can generate procedural skin texture to put
pore-level detail back after the natural texture has been smoothed away.

## Files

| File | Purpose |
| --- | --- |
| `MT_BeautyFS.xml` | Shader definition: passes, inputs, UI |
| `MT_BeautyFS.1.glsl` | Front passthrough plus procedural texture generation |
| `MT_BeautyFS.2.glsl` / `.3.glsl` | Separable detail-radius blur |
| `MT_BeautyFS.4.glsl` / `.5.glsl` | Separable base-radius blur |
| `MT_BeautyFS.6.glsl` | Band recombination and composite |

Drop all seven files into a Matchbox directory (for example
`/opt/Autodesk/presets/<version>/matchbox/shaders`, or any folder pointed at by
your Matchbox path) and load `MT_BeautyFS.xml` from the Matchbox browser.

## Inputs

| Input | Notes |
| --- | --- |
| **Front** | The image to retouch. Required. |
| **Matte** | Drives the strength of the effect: white is full effect, black leaves the front untouched. Defaults to white when nothing is connected. |
| **ST map** | Optional UV pass. Red and green are read as texture coordinates so the procedural texture tracks with the skin. Defaults to black, which produces no texture, so leave *Texture space* on **Screen** unless you have connected one. |

## How it works

Two blurs produce three bands:

```
fine = front - mid      pores, grain, fine skin texture
mid  = mid   - base     blemishes, blotches, wrinkles, uneven shading
base                    skin tone and broad modelling
```

Each band gets its own gain, and the three are summed back together. With both
gains at 1.0 and no synthetic texture the sum is *exactly* the front again, so
the node is a true identity when it is doing nothing, whatever the radii and
quality are set to.

The base blur runs on the already mid-blurred image rather than on the front,
so its sigma is `sqrt(base² - mid²)` — two gaussians in series add in
quadrature, which makes the *Base radius* control mean what it says while
saving a full-size blur.

Both blurs are optionally range-weighted (*Edge protect*), which stops eyebrows,
lips and background from bleeding across the skin the way a plain gaussian
would.

### The procedural texture

The texture is generated in pass 1, *before* the blur chain, and rides through
passes 2 and 3 in the alpha channel. The composite then subtracts the blurred
copy from the raw one. That gives a synthetic texture occupying exactly the same
frequency band as the natural texture it is replacing, with no DC offset to
shift skin brightness — which is what makes it drop in cleanly where the fine
band used to be.

It is built from a scattered cellular layer for the pores, a fractal noise layer
for the grain between them, and a fine noise layer roughly at the scale of peach
fuzz, all through a warped coordinate space so the cell structure never reads as
a grid.

## Controls

### Beauty page

**Frequency split** — *Base radius* sets where blemishes end and skin tone
begins; *Detail radius* sets where fine texture ends and blemishes begin, and
should be roughly the size of the pores you want treated as texture.
*Edge protect* at 0 is a plain gaussian; higher values keep more edges but can
harden the result. *Quality* is the blur sample stride — drop it while you work,
put it back to Best to render.

**Detail** — *Mid detail* and *Fine detail* are gains on their bands: 1.0 leaves
the band alone, 0 removes it, above 1 exaggerates it. *Strength* is a master mix
back over the front, on top of whatever the matte is doing.

**Skin texture** — *Texture amount* is the strength of the procedural texture.
*Texture mode* chooses Multiply, where the texture scales with local brightness
(the more photographic behaviour, and the better default on scene-linear
material), or Add, which lays it on at a constant level. *Texture tint* weights
the texture per channel — warm values put more structure in the red record, the
way real skin does. *Shading response* only applies in Add mode.

**Output** — *View* shows the individual bands while you set the radii; the band
views are offset by 0.5 so the negative half is visible. *Clamp negatives* stops
boosted detail pushing dark pixels below zero.

### Matte page

*Strength matte* picks which channel of the matte input drives the effect, and
inverts and gains it. *Tonal limits* fade the effect out of the shadows and
highlights based on the base band, so speculars stay intact.

### Texture page

*Tracking* is the texture space, the ST map green flip and the offset.
*Pattern* is pore size (cell spacing in pixels at the current resolution),
aspect, rotation and seed. *Pores* and *Grain* set the character of the two main
noise layers.

### Fine tune page

The micro layer (roughly peach fuzz scale), the domain warp that keeps the cell
structure from reading as a grid, and the contrast shaping.

## Typical use

**Softening natural texture.** Leave *Texture amount* at 0. Pull *Mid detail*
down to around 0.3 to take out blemishes and blotches, and *Fine detail* to
taste — 0.5 or so keeps the skin looking like skin, lower starts to go plastic.

**Replacing texture.** Pull *Fine detail* to 0 to remove the natural texture
entirely, then bring *Texture amount* up to around 0.5–0.7. Set *Pore size* by
eye against the plate, using the *Procedural texture* view to judge scale. If
the shot moves, connect an ST map and switch *Texture space* to **ST map** so
the texture sticks to the face instead of swimming under it.

**Both.** Softening the fine band only partly (say 0.4) and adding a little
synthetic texture on top often sits better than either extreme, because the
natural texture keeps the skin anchored while the synthetic layer evens out the
areas that got over-smoothed.

Radii are in pixels at the working resolution, so they are not resolution
independent — a setup built at HD will need the radii and pore size scaled if
you move it to 4K.
