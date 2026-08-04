// MT_BeautyFS - pass 5 of 6
//
// Vertical half of the base blur.  The result is the low-frequency image: skin
// tone and broad shading with blemishes, blotches and texture removed.

uniform sampler2D adsk_results_pass4;
uniform float adsk_result_w, adsk_result_h;

uniform float baseRadius, midRadius, edgeProtect;
uniform int   quality;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	vec2 res = vec2(adsk_result_w, adsk_result_h);
	vec2 xy = gl_FragCoord.xy;
	vec4 centre = texture2D(adsk_results_pass4, xy / res);

	float sigma = sqrt(max(baseRadius * baseRadius - midRadius * midRadius, 0.0));
	if (sigma < 0.35) {
		gl_FragColor = centre;
		return;
	}

	int q = quality;
	if (q < 0) q = 0;
	if (q > 3) q = 3;

	float stride  = float(q + 1);
	float support = min(ceil(sigma * 3.0), 600.0);

	// Keep at least one tap pair - a stride wider than the support would
	// skip the loop and silently turn Draft and Fast into an identity.
	if (stride > support) stride = support;
	float denom   = 2.0 * sigma * sigma;

	bool bilateral = edgeProtect > 0.001;
	float k = 0.0;
	if (bilateral) {
		float sr = mix(2.0, 0.02, clamp(edgeProtect, 0.0, 1.0));
		k = 1.0 / (2.0 * sr * sr);
	}
	float ref = max(luma(centre.rgb), 0.02);

	vec3  accRGB = centre.rgb;
	float wRGB   = 1.0;

	for (float i = stride; i <= support; i += stride) {
		float g = exp(-(i * i) / denom);
		vec2 off = vec2(0.0, i);

		vec3 s0 = texture2D(adsk_results_pass4, (xy + off) / res).rgb;
		vec3 s1 = texture2D(adsk_results_pass4, (xy - off) / res).rgb;

		float r0 = 1.0;
		float r1 = 1.0;
		if (bilateral) {
			float d0 = length(s0 - centre.rgb) / ref;
			float d1 = length(s1 - centre.rgb) / ref;
			r0 = exp(-d0 * d0 * k);
			r1 = exp(-d1 * d1 * k);
		}

		accRGB += g * (s0 * r0 + s1 * r1);
		wRGB   += g * (r0 + r1);
	}

	gl_FragColor = vec4(accRGB / max(wRGB, 1e-6), centre.a);
}
