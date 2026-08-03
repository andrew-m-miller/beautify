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
uniform float texAmount, texShading;
uniform int   texMode;
uniform vec3  texTint;

uniform int   matteChannel;
uniform bool  invertMatte;
uniform float matteGain, shadowLevel, highlightLevel;
uniform bool  clampNegative;
uniform int   viewMode;

// Brings the generator output into a useful range, so that a texture amount of
// 1.0 is a strong but still plausible amount of skin texture.
const float TEX_NORM = 0.25;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	vec2 uv = gl_FragCoord.xy / vec2(adsk_result_w, adsk_result_h);

	vec4 f = texture2D(front, uv);
	vec4 mid = texture2D(adsk_results_pass3, uv);
	vec3 base = texture2D(adsk_results_pass5, uv).rgb;

	vec3 fineBand = f.rgb - mid.rgb;
	vec3 midBand  = mid.rgb - base;

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

	vec3 beauty = base + midBand * midDetail + fineBand * fineDetail;

	vec3 tex = texHP * TEX_NORM * texAmount * texTint;
	if (texAmount > 0.0) {
		if (texMode == 1) {
			// Additive: scale by the base so texture fades out of the shadows
			// the way real skin texture does.
			float shade = mix(1.0, clamp(l * 2.0, 0.0, 4.0), clamp(texShading, 0.0, 1.0));
			beauty += tex * shade;
		} else {
			// Multiplicative: texture rides on the local brightness, which is
			// the more photographic behaviour on scene-linear material.
			beauty *= 1.0 + tex;
		}
	}

	vec3 result = mix(f.rgb, beauty, m);

	if      (viewMode == 1) result = base;
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
