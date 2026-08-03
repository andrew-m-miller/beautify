# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single Autodesk Flame Matchbox shader, `MT_BeautyFS` — frequency separation
beauty work with a procedural skin texture generator. There is no build system,
no package manager and no test suite. The deliverable is the seven shader files
themselves, which get dropped into a Flame Matchbox directory and loaded from
the Matchbox browser.

`README.md` is the artist-facing documentation (what each control does, typical
workflows). This file is the implementation-facing counterpart.

## Verification

Nothing here runs outside Flame, so verification is: compile the GLSL, check the
XML and GLSL agree, and simulate the math in NumPy when changing the algorithm.

**Compile all passes** (needs `apt-get install -y glslang-tools`; `apt-get
update` first, the cached index 404s). Flame supplies no `#version` directive
and neither do the shader files, but glslang defaults to ESSL and demands
precision qualifiers, so prepend `#version 120` for the check only:

```bash
for n in 1 2 3 4 5 6; do
  { printf '#version 120\n'; cat MT_BeautyFS.$n.glsl; } > /tmp/p$n.frag
  glslangValidator -S frag /tmp/p$n.frag || echo "PASS $n FAILED"
done
```

**Check XML and GLSL uniforms match.** Every uniform a pass's GLSL declares must
appear in that pass's `<Shader>` block, and nothing may be declared in XML that
the GLSL lacks. This is the single most likely way to break the shader, and
Flame's error will not point at it:

```bash
python3 - <<'EOF'
import re, xml.etree.ElementTree as ET
auto = {'adsk_result_w','adsk_result_h','adsk_result_frameratio','adsk_time'}
for sh in ET.parse('MT_BeautyFS.xml').getroot().findall('Shader'):
    i = sh.get('Index')
    src = re.sub(r'//.*', '', open(f'MT_BeautyFS.{i}.glsl').read())
    g = {p.strip() for m in re.finditer(r'\buniform\s+\w+\s+([^;]+);', src)
         for p in m.group(1).split(',')}
    x = {u.get('Name') for u in sh.findall('Uniform')}
    if (g - x) - auto: print(f'pass {i}: in GLSL not XML:', sorted((g - x) - auto))
    if x - g:          print(f'pass {i}: in XML not GLSL:', sorted(x - g))
EOF
```

**Simulate before trusting algorithm changes.** Porting a pass to NumPy and
running it on a synthetic plate catches design errors that compile fine. The
checks worth re-running after any change to the band math: reconstruction is a
bit-exact identity at `midDetail=1, fineDetail=1, texAmount=0`; the texture
high-pass has a mean of ~0 both globally and over face-sized blocks; output is
finite and tone is preserved. These simulations live in the session scratchpad,
not the repo — rewrite them as needed.

## Pass topology

Six passes, `MT_BeautyFS.1.glsl` … `.6.glsl`, wired by `MT_BeautyFS.xml`.

```
1  rgb = front, a = procedural texture (biased into 0-1)   Float32
2  horizontal blur, sigma = midRadius                      Float32
3  vertical   blur, sigma = midRadius        -> mid band   Float32
4  horizontal blur, sigma = sqrt(base²-mid²)               Float32
5  vertical   blur, sigma = sqrt(base²-mid²) -> base band   Float32
6  composite: front, matte, pass1, pass3, pass5            Output
```

Passes 4 and 5 run on the already mid-blurred image, not the front. Gaussians in
series add in quadrature, hence the `sqrt(base² - mid²)` sigma — this keeps the
*Base radius* control honest while saving a full-size blur. If either radius
changes meaning, that formula has to change with it.

The composite forms three bands and sums them with per-band gains:

```
fine = front - mid      mid = mid - base      base
```

## Invariants

Break any of these and the shader will still compile and still look plausible,
which is what makes them worth stating.

- **Identity.** With `midDetail = fineDetail = 1` and `texAmount = 0`, the sum of
  the bands is exactly the front, whatever the radii, quality or edge protect.
  This holds by algebra, not by tuning; preserve it.
- **Texture alpha encoding.** Pass 1 stores `t * 0.25 + 0.5`; pass 6 recovers it
  with `(raw - blurred) * 4.0`. The bias cancels in the subtraction. The two
  constants are a pair — change one, change the other.
- **The texture alpha is blurred with a plain gaussian, never the bilateral
  weights.** Passes 2 and 3 accumulate two separate normalisations in one loop
  for exactly this reason. Range-weighting the alpha would let image structure
  leak into the synthetic texture's high-pass.
- **Passes 4 and 5 pass alpha through untouched.** The composite reads the
  texture's blurred copy from pass *3*, not pass 5. Blurring it further in 4/5
  would be harmless but wasteful; reading it from 5 would be wrong.
- **Both `baseRadius` and `midRadius` are needed in passes 4 and 5** to compute
  the quadrature sigma.

## Why the texture is generated in pass 1

It would be simpler to generate the procedural texture in the composite. It is
generated in pass 1 and carried through the blur chain in the alpha channel so
that the composite can high-pass it against *its own blur*, at the same sigma
used to split the image. That does two things: it puts the synthetic texture in
exactly the frequency band vacated by the natural fine band, and it removes the
texture's DC offset exactly rather than by a hand-tuned constant. The raw
generator output has a mean around -0.19; after the high-pass it is ~0.0001.
Any refactor that moves generation into the composite reintroduces a brightness
shift that has to be fudged out.

## GLSL conventions

Target the GLSL 1.20 compatibility subset — Flame compiles these without a
`#version` directive, and most shipping Matchboxes rely on that:

- `texture2D` / `gl_FragColor` / `gl_FragCoord`, not `texture()` or out variables.
- No `clamp(int, int, int)` — that is GLSL 1.30+. Clamp ints with explicit
  `if` statements, as the passes already do for `quality` and `fineOctaves`.
- Dynamic `for` bounds are fine (`for (float i = stride; i <= support; ...)`);
  shipping Matchboxes use them.
- Files are tab-indented.
- Hash functions are the trig-free Dave Hoskins variety. Do not swap in
  `sin`-based hashes; they vary across GPU vendors.

## Matchbox format facts

Researched against the ~190-shader corpus at `github.com/lcrs/matchboxes`, which
is the reference to consult before guessing at format questions. Autodesk's own
docs pages 403 to WebFetch; clone the repo and grep it instead.

- Multi-pass files are named `Name.N.glsl` alongside `Name.xml`. Single-pass is
  `Name.glsl`. Some shaders use zero-padded `Name.01.glsl`.
- `adsk_result_w` / `adsk_result_h` are supplied automatically and must **not**
  be declared in the XML. `adsk_results_passN` refers to pass N's output and
  **must** be declared as a `sampler2D` uniform in each consuming pass.
- A uniform re-used by a later pass is re-declared there as
  `<Uniform Name="x" Type="float"><Duplicate></Duplicate></Uniform>`. Only the
  first declaration carries UI attributes.
- Uniforms *and* node inputs may be first declared in any pass, not just pass 1.
  Declaring an input in pass 1 that pass 1's GLSL does not use has no precedent
  in the corpus — declare inputs in the pass that samples them.
- Intermediate passes use `OutputBitDepth="Float32"`, the final pass uses
  `"Output"`.
- UI: `Page` / `Col` / `Row` attributes place controls; `<Page>` and `<Col>`
  elements at the end of the file name the tabs and columns. Popups are
  `Type="int" ValueType="Popup"` with `<PopupEntry Title="" Value="">` children.
  `vec2` / `vec3` take one `<SubUniform Default="">` per component; colours are
  `Type="vec3" ValueType="Colour"`. Conditional enabling is
  `UIConditionSource` / `UIConditionValue` / `UIConditionType="Disable"|"Hide"`.

## Performance

Cost is dominated by the four blur passes. Each is `2 * ceil(sigma * 3) / stride`
taps per pixel, where stride is `quality + 1` (the *Quality* popup: Best=1 …
Fast=4). Support is capped at 600, so a `baseRadius` above ~200 silently
truncates the kernel rather than getting slower. Edge protect adds a `length()`
and an `exp()` per tap and is branched off entirely when set to 0.

Radii and pore size are in pixels at the working resolution and are not
resolution independent — every `ResDependent` attribute is `"None"`. A setup
built at HD needs them scaled for 4K. If this becomes a problem, that attribute
is the lever, but changing it will invalidate existing saved setups.

## Git

Development happens on `claude/glsl-frequency-separation-shader-wkeeyu`; push
there with `git push -u origin <branch>`. Do not open a pull request unless
explicitly asked.
