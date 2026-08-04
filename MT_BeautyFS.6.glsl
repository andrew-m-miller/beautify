// MT_BeautyFS - pass 6 of 6
//
// Recombines the three bands and mixes the result back over the front through
// the strength matte.
//
//   fine = front - mid     pores, grain, fine skin texture
//   mid  = mid   - base    blemishes, blotches, wrinkles, uneven shading
//   base                   skin tone and broad modelling
//
// With both detail gains at 1.0 and no synthetic texture the sum is exactly the
// front again, so the node is a true identity when it is doing nothing,
// whatever the blur radii and quality are set to.

uniform sampler2D front;
uniform sampler2D matte;
uniform sampler2D adsk_results_pass1;   // rgb = front, a = procedural texture
uniform sampler2D adsk_results_pass3;   // rgb = mid blur, a = blurred texture
uniform sampler2D adsk_results_pass5;   // rgb = base blur

uniform float adsk_result_w, adsk_result_h;

uniform float midDetail, fineDetail, strength;
uniform float midChroma;
uniform float texAmount, texShading;
uniform int   texMode;
uniform vec3  texTint;

uniform int   matteChannel;
uniform bool  invertMatte;
uniform float matteGain, shadowLevel, highlightLevel;
uniform bool  useSkinKey;
uniform vec3  keyColour;
uniform float keyRange, keySoftness;
uniform float deshineAmount, deshineLevel, deshineSoftness;
uniform bool  clampNegative;
uniform int   viewMode;

// Brings the generator output into a useful range, so that a texture amount of
// 1.0 is a strong but still plausible amount of skin texture.
const float TEX_NORM = 0.25;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Soft knee compression of the base luminance, for taking the shine off an oily
// forehead or nose.
//
// The knee spans level*(1-softness) to level*(1+softness), carrying the slope
// from 1 below it to 1-amount above it, so the curve is continuous in value and
// in slope at both ends - a hard corner at the level would band across a
// forehead, where the falloff is slow and the quantisation visible.
// Below the knee the colour is returned untouched rather than scaled by 1.0, so
// nothing outside the compressed range is even rounded.
vec3 deshine(vec3 c, float l) {
	float t = max(deshineLevel, 0.0);
	float s = 1.0 - clamp(deshineAmount, 0.0, 1.0);
	// Floored so that softness or level at 0 gives a hard knee rather than a
	// divide by zero.
	float w = max(t * clamp(deshineSoftness, 0.0, 1.0), 1e-6);

	float lo = t - w;
	if (l <= lo) {
		return c;
	}

	float y;
	if (l >= t + w) {
		y = t + s * (l - t);
	} else {
		float d = l - lo;
		y = lo + d + (s - 1.0) * d * d / (4.0 * w);
	}

	// Scaling by the luminance ratio rather than offsetting keeps the ratios
	// between the channels, so the shine comes down without the colour of the
	// skin under it shifting.
	return c * (y / max(l, 1e-4));
}

void main() {
	vec2 uv = gl_FragCoord.xy / vec2(adsk_result_w, adsk_result_h);

	vec4 f = texture2D(front, uv);
	vec4 mid = texture2D(adsk_results_pass3, uv);
	vec3 base = texture2D(adsk_results_pass5, uv).rgb;

	vec3 fineBand = f.rgb - mid.rgb;
	// Both bands stay measured against the untouched base.  De-shine below
	// replaces only the base term of the recombination; folding it in here as
	// well would put it on both sides of the subtraction and cancel it out at
	// unity detail gains.
	vec3 midBand  = mid.rgb - base;

	// Splitting the band into its luma projection and the remainder lets the
	// colour of a blotch come out while its shading stays for Mid detail to
	// deal with.  The band is signed, which the projection is happy with.
	if (midChroma != 1.0) {
		float bandLuma = luma(midBand);
		midBand = vec3(bandLuma) + (midBand - vec3(bandLuma)) * midChroma;
	}

	// The synthetic texture is high-passed against its own blur, so it lands in
	// the same band as fineBand and carries no DC offset.
	// Pass 1 stores the texture biased into 0-1; the bias cancels in the
	// subtraction, the factor of 4 undoes the scale.
	float texRaw = texture2D(adsk_results_pass1, uv).a;
	float texHP  = (texRaw - mid.a) * 4.0;

	vec4 mt = texture2D(matte, uv);
	float m;
	if      (matteChannel == 1) m = mt.r;
	else if (matteChannel == 2) m = mt.g;
	else if (matteChannel == 3) m = mt.b;
	else if (matteChannel == 4) m = mt.a;
	else                        m = luma(mt.rgb);

	if (invertMatte) m = 1.0 - m;
	m = clamp(m * matteGain, 0.0, 1.0);

	// Skin key, also off the base for the same reason as the tonal limits below.
	// Dividing each colour by its own luma keys on chroma alone, so the same
	// skin stays keyed through shading falloff and exposure changes instead of
	// only at the level the colour was picked at.
	if (useSkinKey) {
		vec3 c = base      / max(luma(base),      0.0001);
		vec3 k = keyColour / max(luma(keyColour), 0.0001);
		float d = length(c - k);
		m *= 1.0 - smoothstep(keyRange, keyRange + max(keySoftness, 0.0001), d);
	}

	// Tonal limits work off the base, so grain and texture in the front cannot
	// make the falloff chatter.
	float l = luma(base);
	if (shadowLevel > 0.0) {
		m *= smoothstep(0.0, shadowLevel, l);
	}
	if (highlightLevel < 100.0) {
		m *= 1.0 - smoothstep(highlightLevel, highlightLevel * 1.5 + 0.001, l);
	}
	m *= clamp(strength, 0.0, 1.0);

	// The branch keeps the off path bit exact; the tonal limits and the skin key
	// above deliberately still read the original base, so de-shining does not
	// move where either of them bites.
	vec3 deshinedBase = base;
	if (deshineAmount > 0.0) {
		deshinedBase = deshine(base, l);
	}

	vec3 beauty = deshinedBase + midBand * midDetail + fineBand * fineDetail;

	vec3 tex = texHP * TEX_NORM * texAmount * texTint;
	if (texAmount > 0.0) {
		if (texMode == 1) {
			// Additive: scale by the base so texture fades out of the shadows
			// the way real skin texture does.
			float shade = mix(1.0, clamp(l * 2.0, 0.0, 4.0), clamp(texShading, 0.0, 1.0));
			beauty += tex * shade;
		} else {
			// Multiplicative: texture rides on the local brightness, which is
			// the more photographic behaviour on scene-linear material.  The
			// clamp stops a deep pore at high amounts flipping the sign.
			beauty *= max(1.0 + tex, vec3(0.0));
		}
	}

	vec3 result = mix(f.rgb, beauty, m);

	if      (viewMode == 1) result = deshinedBase;
	else if (viewMode == 2) result = midBand + 0.5;
	else if (viewMode == 3) result = fineBand + 0.5;
	else if (viewMode == 4) result = texHP * TEX_NORM * max(texAmount, 1.0) * texTint + 0.5;
	else if (viewMode == 5) result = vec3(m);
	else if (viewMode == 6) result = beauty;

	if (clampNegative && viewMode != 2 && viewMode != 3 && viewMode != 4) {
		result = max(result, vec3(0.0));
	}

	gl_FragColor = vec4(result, f.a);
}
