// MT_BeautyFS - pass 1 of 6
//
// Passes the front through in RGB and generates the procedural skin texture
// into alpha.  Generating it here, before the blur chain, means passes 2 and 3
// hand us a low-passed copy of the same signal: subtracting the two in the
// composite gives a synthetic texture that sits in exactly the same frequency
// band as the natural texture it is replacing, with no DC offset to shift skin
// brightness.

uniform sampler2D front;
uniform sampler2D stmap;

uniform float adsk_result_w, adsk_result_h;

uniform int   texSpace;      // 0 = screen space, 1 = ST map
uniform bool  stFlipV;
uniform vec2  texOffset;
uniform float texSeed;
uniform float texScale;      // size of one pore cell, in pixels
uniform float texAspect;
uniform float texRotate;

uniform float poreAmount, poreSize, poreIrregular, poreDepthVar;
uniform float fineAmount, fineFreq, fineRough, microAmount, microFreq;
uniform int   fineOctaves;
uniform float warpAmount, warpFreq, texContrast;

// Hash functions after Dave Hoskins - no trig, stable across GPU vendors.
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

float fbm(vec2 p, int oct, float rough) {
	float sum = 0.0;
	float amp = 1.0;
	float norm = 0.0;

	for (int i = 0; i < 8; i++) {
		if (i >= oct) break;
		sum  += vnoise(p) * amp;
		norm += amp;
		p    *= 2.03;
		amp  *= rough;
	}

	return sum / max(norm, 1e-6);
}

// x = distance to the nearest feature point, y = a random value per cell
vec2 cellular(vec2 p, float jitter) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);

	float best = 8.0;
	float id = 0.0;

	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = mix(vec2(0.5), hash22(ip + g), jitter);
			vec2 r = g + o - fp;
			float d = dot(r, r);
			if (d < best) {
				best = d;
				id = hash21(ip + g + 17.31);
			}
		}
	}

	return vec2(sqrt(best), id);
}

void main() {
	vec2 res = vec2(adsk_result_w, adsk_result_h);
	vec2 screen = gl_FragCoord.xy / res;
	vec4 f = texture2D(front, screen);

	// Texture space.  Both branches are normalised so that 1.0 spans the image
	// width, which keeps cells square and keeps the pore size control in pixels
	// whichever space is in use.
	vec2 uv;
	if (texSpace == 1) {
		vec2 st = texture2D(stmap, screen).rg;
		if (stFlipV) st.y = 1.0 - st.y;
		uv = vec2(st.x, st.y * (adsk_result_h / adsk_result_w));
	} else {
		uv = gl_FragCoord.xy / adsk_result_w;
	}

	uv += texOffset / adsk_result_w;

	vec2 p = uv * (adsk_result_w / max(texScale, 0.5));

	// Rotation and aspect pivot on the frame centre, so the pattern spins
	// and stretches in place instead of sweeping in from the corner.
	vec2 pivot = vec2(0.5, 0.5 * adsk_result_h / adsk_result_w)
	           * (adsk_result_w / max(texScale, 0.5));
	p -= pivot;

	float a = radians(texRotate);
	float cs = cos(a);
	float sn = sin(a);
	p = vec2(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
	p.x /= max(texAspect, 0.01);

	p += pivot;

	p += vec2(hash21(vec2(texSeed, 3.7)), hash21(vec2(texSeed, 11.3))) * 1024.0;

	// Warping the domain breaks up the cellular grid, which otherwise reads as
	// a regular pattern at low irregularity.
	vec2 w = vec2(vnoise(p * warpFreq), vnoise(p * warpFreq + 41.7));
	p += w * warpAmount;

	float jitter = clamp(poreIrregular, 0.0, 1.0);
	vec2 cell = cellular(p, jitter);

	// Pores read as dimples, so shape the distance field into a signal that
	// dips towards each feature point and sits flat between them.
	float pore = smoothstep(0.0, max(poreSize, 0.001), cell.x);
	pore = 1.0 - (1.0 - pore) * mix(1.0, cell.y, clamp(poreDepthVar, 0.0, 1.0));

	int oct = fineOctaves;
	if (oct < 1) oct = 1;
	if (oct > 8) oct = 8;

	float t = (pore - 1.0) * poreAmount;
	t += fbm(p * fineFreq, oct, clamp(fineRough, 0.0, 1.0)) * fineAmount;
	t += vnoise(p * microFreq + 7.13) * microAmount;

	// Contrast shaping about zero, so the mean does not drift with the control.
	float c = clamp(texContrast, 0.05, 8.0);
	t = clamp(t, -2.0, 2.0);
	t = sign(t) * pow(abs(t) * 0.5, c) * 2.0;

	// Stored biased into 0-1 so the signal survives whatever the intermediate
	// render target does with alpha.  The bias is common to the raw and blurred
	// copies, so it cancels when the composite subtracts them.
	gl_FragColor = vec4(f.rgb, t * 0.25 + 0.5);
}
