// MT_BeautyFS - pass 2 of 6
//
// Horizontal half of the detail-radius blur.  RGB is blurred with optional
// range weighting so that eyebrows, lips and background edges do not bleed
// across the skin.  Alpha carries the procedural texture and is always blurred
// with a plain gaussian, so that its high-pass in the composite stays uniform
// and does not pick up structure from the image.

uniform sampler2D adsk_results_pass1;
uniform float adsk_result_w, adsk_result_h;

uniform float midRadius, edgeProtect;
uniform int   quality;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	vec2 res = vec2(adsk_result_w, adsk_result_h);
	vec2 xy = gl_FragCoord.xy;
	vec4 centre = texture2D(adsk_results_pass1, xy / res);

	float sigma = midRadius;
	if (sigma < 0.35) {
		gl_FragColor = centre;
		return;
	}

	int q = quality;
	if (q < 0) q = 0;
	if (q > 3) q = 3;

	float stride  = float(q + 1);
	float support = min(ceil(sigma * 3.0), 600.0);
	float denom   = 2.0 * sigma * sigma;

	bool bilateral = edgeProtect > 0.001;
	float k = 0.0;
	if (bilateral) {
		float sr = mix(2.0, 0.02, clamp(edgeProtect, 0.0, 1.0));
		k = 1.0 / (2.0 * sr * sr);
	}
	float ref = max(luma(centre.rgb), 0.02);

	vec3  accRGB = centre.rgb;
	float accA   = centre.a;
	float wRGB   = 1.0;
	float wA     = 1.0;

	for (float i = stride; i <= support; i += stride) {
		float g = exp(-(i * i) / denom);
		vec2 off = vec2(i, 0.0);

		vec4 s0 = texture2D(adsk_results_pass1, (xy + off) / res);
		vec4 s1 = texture2D(adsk_results_pass1, (xy - off) / res);

		float r0 = 1.0;
		float r1 = 1.0;
		if (bilateral) {
			float d0 = length(s0.rgb - centre.rgb) / ref;
			float d1 = length(s1.rgb - centre.rgb) / ref;
			r0 = exp(-d0 * d0 * k);
			r1 = exp(-d1 * d1 * k);
		}

		accRGB += g * (s0.rgb * r0 + s1.rgb * r1);
		wRGB   += g * (r0 + r1);
		accA   += g * (s0.a + s1.a);
		wA     += g * 2.0;
	}

	gl_FragColor = vec4(accRGB / max(wRGB, 1e-6), accA / max(wA, 1e-6));
}
