// chs-bundle.js — @sailingnaturali/chs-constituents fit surface as an IIFE, run in
// JavaScriptCore by ChsFitService. Committed artifact; rebuild from a chs-constituents
// checkout (uses its node_modules):
//   npx esbuild entry.ts --bundle --format=iife --global-name=CHSConstituents --outfile=chs-bundle.js
// where entry.ts is:  export { fit, BASIS } from "<chs-constituents>/src/index.ts";
// (Same recipe the M0 spike validated — spikes/chs-fit/README.md.)
var CHSConstituents = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // ../../../../../private/tmp/claude-501/-Users-clarkbw-src-sailingnaturali/ba477e2b-af0b-422f-8eae-6145b12c8f1c/scratchpad/chs-entry.ts
  var chs_entry_exports = {};
  __export(chs_entry_exports, {
    BASIS: () => BASIS,
    fit: () => fit
  });

  // node_modules/@neaps/tide-predictor/dist/index.js
  var d2r = Math.PI / 180;
  var r2d = 180 / Math.PI;
  var sexagesimalToDecimal = (degrees, arcmins = 0, arcsecs = 0, mas = 0, muas = 0) => {
    return degrees + arcmins / 60 + arcsecs / 3600 + mas / (3600 * 1e3) + muas / (3600 * 1e6);
  };
  var coefficients = {
    terrestrialObliquity: [
      sexagesimalToDecimal(23, 26, 21.448),
      -sexagesimalToDecimal(0, 0, 4680.93),
      -sexagesimalToDecimal(0, 0, 1.55),
      sexagesimalToDecimal(0, 0, 1999.25),
      -sexagesimalToDecimal(0, 0, 51.38),
      -sexagesimalToDecimal(0, 0, 249.67),
      -sexagesimalToDecimal(0, 0, 39.05),
      sexagesimalToDecimal(0, 0, 7.12),
      sexagesimalToDecimal(0, 0, 27.87),
      sexagesimalToDecimal(0, 0, 5.79),
      sexagesimalToDecimal(0, 0, 2.45)
    ].map((number, index) => {
      return number * Math.pow(0.01, index);
    }),
    solarPerigee: [
      -77.06265000000002,
      1.7190199999968172,
      4591e-7,
      48e-8
    ],
    solarLongitude: [
      280.46645,
      36000.76983,
      3032e-7
    ],
    lunarInclination: [5.145],
    lunarLongitude: [
      218.3164591,
      481267.88134236,
      -13268e-7,
      1 / 538841 - 1 / 65194e3
    ],
    lunarNode: [
      125.044555,
      -1934.1361849,
      20762e-7,
      1 / 467410,
      -1 / 60616e3
    ],
    lunarPerigee: [
      83.353243,
      4069.0137111,
      -0.0103238,
      -1 / 80053,
      1 / 18999e3
    ]
  };
  var polynomial = (coefficients2, argument) => {
    const result = [];
    coefficients2.forEach((coefficient, index) => {
      result.push(coefficient * Math.pow(argument, index));
    });
    return result.reduce((a, b) => a + b);
  };
  var derivativePolynomial = (coefficients2, argument) => {
    const result = [];
    coefficients2.forEach((coefficient, index) => {
      result.push(coefficient * index * Math.pow(argument, index - 1));
    });
    return result.reduce((a, b) => a + b);
  };
  var T = (t) => {
    return (JD(t) - 2451545) / 36525;
  };
  var JD = (t) => {
    let Y = t.getUTCFullYear();
    let M = t.getUTCMonth() + 1;
    const D = t.getUTCDate() + t.getUTCHours() / 24 + t.getUTCMinutes() / 1440 + t.getUTCSeconds() / (1440 * 60) + t.getUTCMilliseconds() / (1440 * 60 * 1e3);
    if (M <= 2) {
      Y = Y - 1;
      M = M + 12;
    }
    const A = Math.floor(Y / 100);
    const B = 2 - A + Math.floor(A / 4);
    return Math.floor(365.25 * (Y + 4716)) + Math.floor(30.6001 * (M + 1)) + D + B - 1524.5;
  };
  var _I = (N, i, omega) => {
    N = d2r * N;
    i = d2r * i;
    omega = d2r * omega;
    const cosI = Math.cos(i) * Math.cos(omega) - Math.sin(i) * Math.sin(omega) * Math.cos(N);
    return r2d * Math.acos(cosI);
  };
  var _xi = (N, i, omega) => {
    N = d2r * N;
    i = d2r * i;
    omega = d2r * omega;
    let e1 = Math.cos(0.5 * (omega - i)) / Math.cos(0.5 * (omega + i)) * Math.tan(0.5 * N);
    let e2 = Math.sin(0.5 * (omega - i)) / Math.sin(0.5 * (omega + i)) * Math.tan(0.5 * N);
    e1 = Math.atan(e1);
    e2 = Math.atan(e2);
    e1 = e1 - 0.5 * N;
    e2 = e2 - 0.5 * N;
    return -(e1 + e2) * r2d;
  };
  var _nu = (N, i, omega) => {
    N = d2r * N;
    i = d2r * i;
    omega = d2r * omega;
    let e1 = Math.cos(0.5 * (omega - i)) / Math.cos(0.5 * (omega + i)) * Math.tan(0.5 * N);
    let e2 = Math.sin(0.5 * (omega - i)) / Math.sin(0.5 * (omega + i)) * Math.tan(0.5 * N);
    e1 = Math.atan(e1);
    e2 = Math.atan(e2);
    e1 = e1 - 0.5 * N;
    e2 = e2 - 0.5 * N;
    return (e1 - e2) * r2d;
  };
  var _nup = (N, i, omega) => {
    const I = d2r * _I(N, i, omega);
    const nu = d2r * _nu(N, i, omega);
    return r2d * Math.atan(Math.sin(2 * I) * Math.sin(nu) / (Math.sin(2 * I) * Math.cos(nu) + 0.3347));
  };
  var _nupp = (N, i, omega) => {
    const I = d2r * _I(N, i, omega);
    const nu = d2r * _nu(N, i, omega);
    const tan2nupp = Math.sin(I) ** 2 * Math.sin(2 * nu) / (Math.sin(I) ** 2 * Math.cos(2 * nu) + 0.0727);
    return r2d * 0.5 * Math.atan(tan2nupp);
  };
  var modulus = (a, b) => {
    return (a % b + b) % b;
  };
  var astro = (time) => {
    const result = {};
    const polynomials = {
      s: coefficients.lunarLongitude,
      h: coefficients.solarLongitude,
      p: coefficients.lunarPerigee,
      N: coefficients.lunarNode,
      pp: coefficients.solarPerigee,
      "90": [90],
      omega: coefficients.terrestrialObliquity,
      i: coefficients.lunarInclination
    };
    const dTdHour = 1 / (24 * 365.25 * 100);
    for (const name in polynomials) result[name] = {
      value: modulus(polynomial(polynomials[name], T(time)), 360),
      speed: derivativePolynomial(polynomials[name], T(time)) * dTdHour
    };
    const functions = {
      I: _I,
      xi: _xi,
      nu: _nu,
      nup: _nup,
      nupp: _nupp
    };
    Object.keys(functions).forEach((name) => {
      const functionCall = functions[name];
      result[name] = {
        value: modulus(functionCall(result.N.value, result.i.value, result.omega.value), 360),
        speed: null
      };
    });
    const hour = {
      value: (JD(time) - Math.floor(JD(time))) * 360,
      speed: 15
    };
    result["T+h-s"] = {
      value: hour.value + result.h.value - result.s.value,
      speed: hour.speed + result.h.speed - result.s.speed
    };
    result.P = {
      value: result.p.value - result.xi.value % 360,
      speed: null
    };
    return result;
  };
  var fundamentals$2 = {
    Mm: (a) => corrMm(d2r * a.N.value, d2r * a.p.value),
    Mf: (a) => corrMf(d2r * a.N.value),
    O1: (a) => corrO1(d2r * a.N.value),
    K1: (a) => corrK1(d2r * a.N.value),
    J1: (a) => corrJ1(d2r * a.N.value),
    M1B: (a) => corrM1B(d2r * a.N.value, d2r * a.p.value),
    M1C: (a) => corrM1(d2r * a.N.value, d2r * a.p.value),
    M1: (a) => corrM1(d2r * a.N.value, d2r * a.p.value),
    M1A: (a) => corrM1A(d2r * a.N.value, d2r * a.p.value),
    M2: (a) => corrM2(d2r * a.N.value),
    K2: (a) => corrK2(d2r * a.N.value),
    M3: (a) => corrM3(d2r * a.N.value),
    L2: (a) => corrL2(d2r * a.N.value, d2r * a.p.value),
    gamma2: (a) => corrGamma2(d2r * a.N.value, d2r * a.p.value),
    alpha2: (a) => corrAlpha2(d2r * a.p.value, d2r * a.pp.value),
    delta2: (a) => corrDelta2(d2r * a.N.value),
    xi2: (a) => corrXiEta2(d2r * a.N.value),
    eta2: (a) => corrXiEta2(d2r * a.N.value)
  };
  function corrMm(N, p) {
    return {
      f: 1 - 0.1311 * Math.cos(N) + 0.0538 * Math.cos(2 * p) + 0.0205 * Math.cos(2 * p - N),
      u: 0
    };
  }
  function corrMf(N) {
    return {
      f: 1.084 + 0.415 * Math.cos(N) + 0.039 * Math.cos(2 * N),
      u: -23.7 * Math.sin(N) + 2.7 * Math.sin(2 * N) - 0.4 * Math.sin(3 * N)
    };
  }
  function corrO1(N) {
    return {
      f: 1.0176 + 0.1871 * Math.cos(N) - 0.0147 * Math.cos(2 * N),
      u: 10.8 * Math.sin(N) - 1.34 * Math.sin(2 * N) + 0.19 * Math.sin(3 * N)
    };
  }
  function corrK1(N) {
    return {
      f: 1.006 + 0.115 * Math.cos(N) - 88e-4 * Math.cos(2 * N) + 6e-4 * Math.cos(3 * N),
      u: -8.86 * Math.sin(N) + 0.68 * Math.sin(2 * N) - 0.07 * Math.sin(3 * N)
    };
  }
  function corrJ1(N) {
    return {
      f: 1.1029 + 0.1676 * Math.cos(N) - 0.017 * Math.cos(2 * N) + 16e-4 * Math.cos(3 * N),
      u: -12.94 * Math.sin(N) + 1.34 * Math.sin(2 * N) - 0.19 * Math.sin(3 * N)
    };
  }
  function corrM2(N) {
    return {
      f: 1.0007 - 0.0373 * Math.cos(N) + 2e-4 * Math.cos(2 * N),
      u: -2.14 * Math.sin(N)
    };
  }
  function corrK2(N) {
    return {
      f: 1.0246 + 0.2863 * Math.cos(N) + 83e-4 * Math.cos(2 * N) - 15e-4 * Math.cos(3 * N),
      u: -17.74 * Math.sin(N) + 0.68 * Math.sin(2 * N) - 0.04 * Math.sin(3 * N)
    };
  }
  function corrM3(N) {
    const m2 = corrM2(N);
    return {
      f: Math.pow(Math.sqrt(m2.f), 3),
      u: -3.21 * Math.sin(N)
    };
  }
  function corrM1B(N, p) {
    return fromSinCos(2.783 * Math.sin(2 * p) + 0.558 * Math.sin(2 * p - N) + 0.184 * Math.sin(N), 1 + 2.783 * Math.cos(2 * p) + 0.558 * Math.cos(2 * p - N) + 0.184 * Math.cos(N));
  }
  function corrM1(N, p) {
    return fromSinCos(Math.sin(p) + 0.2 * Math.sin(p - N), 2 * (Math.cos(p) + 0.2 * Math.cos(p - N)));
  }
  function corrM1A(N, p) {
    return fromSinCos(-0.3593 * Math.sin(2 * p) - 0.2 * Math.sin(N) - 0.066 * Math.sin(2 * p - N), 1 + 0.3593 * Math.cos(2 * p) + 0.2 * Math.cos(N) + 0.066 * Math.cos(2 * p - N));
  }
  function corrGamma2(N, p) {
    return fromSinCos(0.147 * Math.sin(2 * (N - p)), 1 + 0.147 * Math.cos(2 * (N - p)));
  }
  function corrAlpha2(p, pp) {
    return fromSinCos(-0.0446 * Math.sin(p - pp), 1 - 0.0446 * Math.cos(p - pp));
  }
  function corrDelta2(N) {
    return fromSinCos(0.477 * Math.sin(N), 1 - 0.477 * Math.cos(N));
  }
  function corrXiEta2(N) {
    return fromSinCos(-0.439 * Math.sin(N), 1 + 0.439 * Math.cos(N));
  }
  function corrL2(N, p) {
    return fromSinCos(-0.2505 * Math.sin(2 * p) - 0.1102 * Math.sin(2 * p - N) - 0.0156 * Math.sin(2 * p - 2 * N) - 0.037 * Math.sin(N), 1 - 0.2505 * Math.cos(2 * p) - 0.1102 * Math.cos(2 * p - N) - 0.0156 * Math.cos(2 * p - 2 * N) - 0.037 * Math.cos(N));
  }
  function fromSinCos(fsinU, fcosU) {
    return {
      f: Math.sqrt(fsinU * fsinU + fcosU * fcosU),
      u: r2d * Math.atan2(fsinU, fcosU)
    };
  }
  var fundamentals$1 = {
    Mm: (a) => ({
      f: fMm(a),
      u: 0
    }),
    Mf: (a) => ({
      f: fMf(a),
      u: uMf(a)
    }),
    O1: (a) => ({
      f: fO1(a),
      u: uO1(a)
    }),
    K1: (a) => ({
      f: fK1(a),
      u: uK1(a)
    }),
    J1: (a) => ({
      f: fJ1(a),
      u: uJ1(a)
    }),
    OO1: (a) => ({
      f: fOO1(a),
      u: uOO1(a)
    }),
    M2: (a) => ({
      f: fM2(a),
      u: uM2(a)
    }),
    K2: (a) => ({
      f: fK2(a),
      u: uK2(a)
    }),
    L2: (a) => ({
      f: fL2(a),
      u: uL2(a)
    }),
    M1: (a) => ({
      f: fM1(a),
      u: uM1(a)
    }),
    M3: (a) => ({
      f: fModd(a, 3),
      u: uModd(a, 3)
    })
  };
  function fMm(a) {
    const omega = d2r * a.omega.value;
    const i = d2r * a.i.value;
    const I = d2r * a.I.value;
    const mean = (2 / 3 - Math.pow(Math.sin(omega), 2)) * (1 - 3 / 2 * Math.pow(Math.sin(i), 2));
    return (2 / 3 - Math.pow(Math.sin(I), 2)) / mean;
  }
  function fMf(a) {
    const omega = d2r * a.omega.value;
    const i = d2r * a.i.value;
    const I = d2r * a.I.value;
    const mean = Math.pow(Math.sin(omega), 2) * Math.pow(Math.cos(0.5 * i), 4);
    return Math.pow(Math.sin(I), 2) / mean;
  }
  function fO1(a) {
    const omega = d2r * a.omega.value;
    const i = d2r * a.i.value;
    const I = d2r * a.I.value;
    const mean = Math.sin(omega) * Math.pow(Math.cos(0.5 * omega), 2) * Math.pow(Math.cos(0.5 * i), 4);
    return Math.sin(I) * Math.pow(Math.cos(0.5 * I), 2) / mean;
  }
  function fJ1(a) {
    const omega = d2r * a.omega.value;
    const i = d2r * a.i.value;
    const I = d2r * a.I.value;
    const mean = Math.sin(2 * omega) * (1 - 3 / 2 * Math.pow(Math.sin(i), 2));
    return Math.sin(2 * I) / mean;
  }
  function fOO1(a) {
    const omega = d2r * a.omega.value;
    const i = d2r * a.i.value;
    const I = d2r * a.I.value;
    const mean = Math.sin(omega) * Math.pow(Math.sin(0.5 * omega), 2) * Math.pow(Math.cos(0.5 * i), 4);
    return Math.sin(I) * Math.pow(Math.sin(0.5 * I), 2) / mean;
  }
  function fM2(a) {
    const omega = d2r * a.omega.value;
    const i = d2r * a.i.value;
    const I = d2r * a.I.value;
    const mean = Math.pow(Math.cos(0.5 * omega), 4) * Math.pow(Math.cos(0.5 * i), 4);
    return Math.pow(Math.cos(0.5 * I), 4) / mean;
  }
  function fK1(a) {
    const omega = d2r * a.omega.value;
    const i = d2r * a.i.value;
    const I = d2r * a.I.value;
    const nu = d2r * a.nu.value;
    const mean = 0.5023 * (Math.sin(2 * omega) * (1 - 3 / 2 * Math.pow(Math.sin(i), 2))) + 0.1681;
    return Math.pow(0.2523 * Math.pow(Math.sin(2 * I), 2) + 0.1689 * Math.sin(2 * I) * Math.cos(nu) + 0.0283, 0.5) / mean;
  }
  function fL2(a) {
    const P = d2r * a.P.value;
    const I = d2r * a.I.value;
    const rAInv = Math.pow(1 - 12 * Math.pow(Math.tan(0.5 * I), 2) * Math.cos(2 * P) + 36 * Math.pow(Math.tan(0.5 * I), 4), 0.5);
    return fM2(a) * rAInv;
  }
  function fK2(a) {
    const omega = d2r * a.omega.value;
    const i = d2r * a.i.value;
    const I = d2r * a.I.value;
    const nu = d2r * a.nu.value;
    const mean = 0.5023 * (Math.sin(omega) ** 2 * (1 - 3 / 2 * Math.sin(i) ** 2)) + 0.0365;
    return Math.pow(0.2523 * Math.pow(Math.sin(I), 4) + 0.0367 * Math.pow(Math.sin(I), 2) * Math.cos(2 * nu) + 13e-4, 0.5) / mean;
  }
  function fM1(a) {
    const P = d2r * a.P.value;
    const I = d2r * a.I.value;
    const qAInv = Math.pow(0.25 + 1.5 * Math.cos(I) * Math.cos(2 * P) * Math.pow(Math.cos(0.5 * I), -0.5) + 2.25 * Math.pow(Math.cos(I), 2) * Math.pow(Math.cos(0.5 * I), -4), 0.5);
    return fO1(a) * qAInv;
  }
  function fModd(a, n) {
    return Math.pow(fM2(a), n / 2);
  }
  function uMf(a) {
    return -2 * a.xi.value;
  }
  function uO1(a) {
    return 2 * a.xi.value - a.nu.value;
  }
  function uJ1(a) {
    return -a.nu.value;
  }
  function uOO1(a) {
    return -2 * a.xi.value - a.nu.value;
  }
  function uM2(a) {
    return 2 * a.xi.value - 2 * a.nu.value;
  }
  function uK1(a) {
    return -a.nup.value;
  }
  function uL2(a) {
    const I = d2r * a.I.value;
    const P = d2r * a.P.value;
    const R = r2d * Math.atan(Math.sin(2 * P) / (1 / 6 * Math.pow(Math.tan(0.5 * I), -2) - Math.cos(2 * P)));
    return 2 * a.xi.value - 2 * a.nu.value - R;
  }
  function uK2(a) {
    return -2 * a.nupp.value;
  }
  function uM1(a) {
    const I = d2r * a.I.value;
    const P = d2r * a.P.value;
    const Q = r2d * Math.atan((5 * Math.cos(I) - 1) / (7 * Math.cos(I) + 1) * Math.tan(P));
    return a.xi.value - a.nu.value + Q;
  }
  function uModd(a, n) {
    return n / 2 * uM2(a);
  }
  var fundamentals = {
    iho: fundamentals$2,
    schureman: fundamentals$1
  };
  function resolveFundamentals(name) {
    if (!name) return fundamentals$2;
    const fundamental = fundamentals[name];
    if (!fundamental) throw new Error(`Unknown fundamentals: ${name}`);
    return fundamental;
  }
  var TOLERANCE_HOURS = 1 / 3600;
  function evalH(t, params) {
    let sum = 0;
    for (let i = 0; i < params.length; i++) {
      const { A, w, phi } = params[i];
      sum += A * Math.cos(w * t + phi);
    }
    return sum;
  }
  function evalHPrime(t, params) {
    let sum = 0;
    for (let i = 0; i < params.length; i++) {
      const { A, w, phi } = params[i];
      sum -= A * w * Math.sin(w * t + phi);
    }
    return sum;
  }
  function evalHDoublePrime(t, params) {
    let sum = 0;
    for (let i = 0; i < params.length; i++) {
      const { A, w, phi } = params[i];
      sum -= A * w * w * Math.cos(w * t + phi);
    }
    return sum;
  }
  function bisect(a, b, fa, params) {
    while (true) {
      const mid = (a + b) / 2;
      if (b - a < TOLERANCE_HOURS) return mid;
      const fMid = evalHPrime(mid, params);
      if (fMid === 0) return mid;
      if (fa > 0 ? fMid > 0 : fMid < 0) {
        a = mid;
        fa = fMid;
      } else b = mid;
    }
  }
  function findExtremes(fromHour, toHour, { startMs, isDoubleTide, prominenceThreshold, getParams }) {
    const results = [];
    let params = getParams(Math.max(0, fromHour));
    if (params.length === 0) return results;
    let maxSpeed = 0;
    for (const { w } of params) if (w > maxSpeed) maxSpeed = w;
    if (maxSpeed === 0) return results;
    const TIDAL_MIN_W = Math.PI / 15;
    const TIDAL_MAX_W = 2 * Math.PI;
    let dominantA = 0;
    let dominantW = 0;
    for (const { A, w } of params) if (w >= TIDAL_MIN_W && w <= TIDAL_MAX_W && A > dominantA) {
      dominantA = A;
      dominantW = w;
    }
    if (dominantW === 0) dominantW = maxSpeed;
    const minGapH = isDoubleTide ? 0 : Math.PI / (1.85 * dominantW);
    const bracket = Math.PI / (2 * maxSpeed);
    let tPrev = fromHour;
    let dPrev = evalHPrime(tPrev, params);
    for (let tNext = tPrev + bracket; tNext <= toHour + bracket; tNext += bracket) {
      const newParams = getParams(tPrev);
      if (newParams !== params) {
        params = newParams;
        dPrev = evalHPrime(tPrev, params);
      }
      const tBound = Math.min(tNext, toHour);
      const dNext = evalHPrime(tBound, params);
      if (dPrev !== 0 && dNext !== 0 && (dPrev > 0 ? dNext < 0 : dNext > 0)) {
        const tRoot = bisect(tPrev, tBound, dPrev, params);
        if (tRoot >= fromHour && tRoot <= toHour) {
          const isHigh = evalHDoublePrime(tRoot, params) < 0;
          results.push({
            time: new Date(startMs + tRoot * 60 * 60 * 1e3),
            level: evalH(tRoot, params),
            high: isHigh,
            low: !isHigh,
            label: isHigh ? "High" : "Low"
          });
        }
      }
      if (tBound >= toHour) break;
      tPrev = tBound;
      dPrev = dNext;
    }
    const n = results.length;
    if (n > 2) {
      let evalProm = function(i) {
        const p = prv[i], nx = nxt[i];
        if (p < 0 || nx >= n) return {
          prom: Infinity,
          offending: false
        };
        const left = Math.abs(results[i].level - results[p].level);
        const right = Math.abs(results[nx].level - results[i].level);
        const prom = Math.min(left, right);
        const prevGapH = (results[i].time.getTime() - results[p].time.getTime()) / 36e5;
        const nextGapH = (results[nx].time.getTime() - results[i].time.getTime()) / 36e5;
        const tooClose = minGapH > 0 && (prevGapH < minGapH && results[i].high === results[p].high || nextGapH < minGapH && results[i].high === results[nx].high);
        return {
          prom,
          offending: prom < prominenceThreshold || tooClose
        };
      }, findWorst = function() {
        let worstIdx = -1;
        let worstProm = Infinity;
        for (let i = nxt[0]; nxt[i] < n; i = nxt[i]) {
          const { prom, offending } = evalProm(i);
          if (offending && prom < worstProm) {
            worstProm = prom;
            worstIdx = i;
          }
        }
        return {
          idx: worstIdx,
          prom: worstProm
        };
      };
      const prv = new Int32Array(n);
      const nxt = new Int32Array(n);
      for (let i = 0; i < n; i++) {
        prv[i] = i - 1;
        nxt[i] = i + 1;
      }
      let worst = findWorst();
      while (worst.idx !== -1) {
        const p = prv[worst.idx], nx = nxt[worst.idx];
        nxt[p] = nx;
        prv[nx] = p;
        worst = findWorst();
      }
      const filtered = [];
      for (let i = 0; i < n; i = nxt[i]) filtered.push(results[i]);
      return filtered;
    }
    return results;
  }
  function getHeightOffset(isHigh, offsets) {
    return (isHigh ? offsets?.height?.high : offsets?.height?.low) ?? (offsets?.height?.type === "fixed" ? 0 : 1);
  }
  function addExtremesOffsets(extreme, offsets) {
    if (typeof offsets === "undefined" || !offsets) return extreme;
    const heightAdj = getHeightOffset(extreme.high, offsets);
    if (offsets.height?.type === "fixed") extreme.level += heightAdj;
    else extreme.level *= heightAdj;
    if (extreme.high && offsets.time?.high) extreme.time = new Date(extreme.time.getTime() + offsets.time.high * 60 * 1e3);
    if (extreme.low && offsets.time?.low) extreme.time = new Date(extreme.time.getTime() + offsets.time.low * 60 * 1e3);
    return extreme;
  }
  function getExtremeLabel(label, highLowLabels) {
    if (typeof highLowLabels !== "undefined" && typeof highLowLabels[label] !== "undefined") return highLowLabels[label];
    return {
      high: "High",
      low: "Low"
    }[label];
  }
  var CORRECTION_INTERVAL_HOURS = 24;
  function interpolate(fraction, a, b) {
    return a + fraction * (b - a);
  }
  function predictionFactory({ timeline, constituents: constituents2, constituentModels, start, fundamentals: fundamentals2 = fundamentals$2, prominenceThreshold = 0.01 }) {
    const baseAstro = astro(start);
    const startMs = start.getTime();
    const endHour = (timeline.items[timeline.items.length - 1].getTime() - startMs) / 36e5;
    const m2Amp = constituents2.find((c) => c.name === "M2")?.amplitude ?? 0;
    const m4Amp = constituents2.find((c) => c.name === "M4")?.amplitude ?? 0;
    const ms4Amp = constituents2.find((c) => c.name === "MS4")?.amplitude ?? 0;
    const isDoubleTide = m2Amp > 0 && (m4Amp + ms4Amp) / m2Amp > 0.25;
    function prepareParams(correctionTime) {
      const correctionAstro = astro(correctionTime);
      const params = [];
      for (const constituent of constituents2) {
        if (constituent.amplitude === 0) continue;
        const model = constituentModels[constituent.name];
        if (!model) continue;
        const V0 = d2r * model.value(baseAstro);
        const speed = d2r * model.speed;
        const correction = model.correction(correctionAstro, fundamentals2);
        params.push({
          A: constituent.amplitude * correction.f,
          w: speed,
          phi: V0 + d2r * correction.u - constituent.phase
        });
      }
      return params;
    }
    function correctedParams() {
      let params = prepareParams(new Date(startMs + Math.min(CORRECTION_INTERVAL_HOURS, endHour) / 2 * 36e5));
      let nextCorrectionAt = CORRECTION_INTERVAL_HOURS;
      return (hour) => {
        if (hour >= nextCorrectionAt) {
          const chunkEnd = Math.min(nextCorrectionAt + CORRECTION_INTERVAL_HOURS, endHour);
          params = prepareParams(new Date(startMs + (nextCorrectionAt + chunkEnd) / 2 * 36e5));
          nextCorrectionAt += CORRECTION_INTERVAL_HOURS;
        }
        return params;
      };
    }
    const extremesOptions = {
      startMs,
      isDoubleTide,
      prominenceThreshold
    };
    function getExtremesPrediction({ labels, offsets } = {}) {
      return findExtremes(0, endHour, {
        ...extremesOptions,
        getParams: correctedParams()
      }).map((extreme) => {
        if (labels) extreme.label = getExtremeLabel(extreme.high ? "high" : "low", labels);
        return addExtremesOffsets(extreme, offsets);
      });
    }
    const BUFFER_HOURS = 36;
    function getTimelinePrediction({ offsets } = {}) {
      if (!offsets) {
        const getParams2 = correctedParams();
        const results2 = [];
        for (let i = 0; i < timeline.items.length; i++) {
          const hour = timeline.hours[i];
          results2.push({
            time: timeline.items[i],
            hour,
            level: evalH(hour, getParams2(hour))
          });
        }
        return results2;
      }
      const refExtremes = findExtremes(-36, endHour + BUFFER_HOURS, {
        ...extremesOptions,
        getParams: correctedParams()
      });
      if (refExtremes.length < 2) throw new Error("At least two extremes are required for interpolation with offsets");
      const isFixed = offsets.height?.type === "fixed";
      const keyframes = refExtremes.map((extreme) => {
        const timeOffset = (extreme.high ? offsets.time?.high : offsets.time?.low) ?? 0;
        const heightAdj = getHeightOffset(extreme.high, offsets);
        return {
          subTime: extreme.time.getTime() + timeOffset * 60 * 1e3,
          refTime: extreme.time.getTime(),
          refLevel: extreme.level,
          subLevel: isFixed ? extreme.level + heightAdj : extreme.level * heightAdj
        };
      });
      const getParams = correctedParams();
      const results = [];
      let kfIdx = 0;
      for (let i = 0; i < timeline.items.length; i++) {
        const tMs = timeline.items[i].getTime();
        while (kfIdx < keyframes.length - 2 && keyframes[kfIdx + 1].subTime < tMs) kfIdx++;
        const kf0 = keyframes[kfIdx];
        const kf1 = keyframes[kfIdx + 1];
        const interval = kf1.subTime - kf0.subTime;
        const fraction = interval > 0 ? Math.max(0, Math.min(1, (tMs - kf0.subTime) / interval)) : 0;
        const mappedHour = (interpolate(fraction, kf0.refTime, kf1.refTime) - startMs) / 36e5;
        const refLevel = evalH(mappedHour, getParams(mappedHour));
        const refRange = kf1.refLevel - kf0.refLevel;
        const level = interpolate(refRange !== 0 ? (refLevel - kf0.refLevel) / refRange : fraction, kf0.subLevel, kf1.subLevel);
        results.push({
          time: timeline.items[i],
          hour: timeline.hours[i],
          level
        });
      }
      return results;
    }
    return Object.freeze({
      getExtremesPrediction,
      getTimelinePrediction
    });
  }
  var LETTER_MAP = {
    M: { species: 2 },
    S: { species: 2 },
    N: { species: 2 },
    O: { species: 1 },
    P: { species: 1 },
    Q: { species: 1 },
    J: { species: 1 },
    T: { species: 2 },
    R: { species: 2 },
    L: { species: 2 },
    nu: { species: 2 },
    lambda: { species: 2 }
  };
  var K1_INFO = { species: 1 };
  var K2_INFO = { species: 2 };
  function parseName(name) {
    const fail = (reason) => /* @__PURE__ */ new Error(`Unable to parse compound constituent "${name}": ${reason}`);
    let normalizedName = name;
    if ((name.startsWith("MA") || name.startsWith("MB")) && name.length > 2) normalizedName = "M" + name.substring(2);
    const m = normalizedName.match(/^(.+?)(\d+)$/);
    if (!m) throw fail("no trailing species digits");
    const body = m[1];
    const targetSpecies = parseInt(m[2], 10);
    if (targetSpecies === 0) throw fail("species is 0");
    const tokens = [];
    let i = 0;
    while (i < body.length) {
      let multiplier = 0;
      while (i < body.length && body[i] >= "0" && body[i] <= "9") {
        multiplier = multiplier * 10 + (body.charCodeAt(i) - 48);
        i++;
      }
      if (multiplier === 0) multiplier = 1;
      if (i >= body.length) throw fail("trailing digits with no letter");
      if (body[i] === "(") {
        i++;
        const groupLetters = [];
        while (i < body.length && body[i] !== ")") {
          const letter2 = readLetter(body, i);
          if (!letter2) throw fail(`unrecognized character at position ${i}`);
          groupLetters.push(letter2);
          i += letter2.length;
        }
        if (i >= body.length || body[i] !== ")") throw fail("unclosed parenthesized group");
        i++;
        if (groupLetters.length === 0) throw fail("empty parenthesized group");
        for (const letter2 of groupLetters) {
          if (!isKnownLetter(letter2)) throw fail(`unknown letter "${letter2}"`);
          tokens.push({
            letter: letter2,
            multiplier
          });
        }
        continue;
      }
      const letter = readLetter(body, i);
      if (!letter) throw fail(`unrecognized character at position ${i}`);
      if (!isKnownLetter(letter)) throw fail(`unknown letter "${letter}"`);
      i += letter.length;
      tokens.push({
        letter,
        multiplier
      });
    }
    return {
      tokens,
      targetSpecies
    };
  }
  function readLetter(body, i) {
    if (body.startsWith("nu", i) && (i + 2 >= body.length || !isLower(body[i + 2]))) return "nu";
    if (body.startsWith("lambda", i)) return "lambda";
    const ch = body[i];
    if (ch >= "A" && ch <= "Z") return ch;
    return null;
  }
  function isLower(ch) {
    return ch >= "a" && ch <= "z";
  }
  function isKnownLetter(letter) {
    if (letter === "A" || letter === "B") return false;
    return letter === "K" || letter in LETTER_MAP;
  }
  function resolveSigns(tokens, targetSpecies) {
    if (tokens.some((t) => t.letter === "K")) {
      const result = tryResolve(tokens, targetSpecies, K2_INFO);
      if (result) return result;
      return tryResolve(tokens, targetSpecies, K1_INFO);
    }
    return tryResolve(tokens, targetSpecies, K2_INFO);
  }
  function tryResolve(tokens, targetSpecies, kInfo) {
    const infos = tokens.map((t) => t.letter === "K" ? kInfo : LETTER_MAP[t.letter]);
    const keyOf = (j) => tokens[j].letter + infos[j].species;
    if (tokens.length === 1) {
      const letterSpecies = infos[0].species;
      if (letterSpecies > 0 && targetSpecies > letterSpecies) return [{
        constituentKey: keyOf(0),
        factor: targetSpecies / letterSpecies
      }];
      if (letterSpecies === targetSpecies) return [{
        constituentKey: keyOf(0),
        factor: 1
      }];
    }
    const signs = new Array(tokens.length).fill(1);
    let total = 0;
    for (let j = 0; j < tokens.length; j++) total += tokens[j].multiplier * infos[j].species;
    for (let j = tokens.length - 1; j >= 0; j--) {
      if (total === targetSpecies) break;
      signs[j] = -1;
      total -= 2 * tokens[j].multiplier * infos[j].species;
    }
    if (total !== targetSpecies) return null;
    return tokens.map((t, j) => ({
      constituentKey: keyOf(j),
      factor: signs[j] * t.multiplier
    }));
  }
  function decomposeCompound(name, species, constituents2) {
    let parsed;
    try {
      parsed = parseName(name);
    } catch {
      return null;
    }
    const targetSpecies = species > 0 ? species : parsed.targetSpecies;
    const resolved = resolveSigns(parsed.tokens, targetSpecies);
    if (!resolved) return null;
    const members = [];
    for (const { constituentKey, factor } of resolved) {
      const constituent = constituents2[constituentKey];
      if (!constituent) return null;
      members.push({
        constituent,
        factor
      });
    }
    return members.length > 0 ? members : null;
  }
  var constituents = {};
  function defineConstituent({ name, speed, xdo, aliases = [], members: memberRefs, nodalCorrection }) {
    const coefficients2 = xdo ? xdoToCoefficients(xdo) : null;
    let resolvedMembers = null;
    const constituent = {
      name,
      speed,
      aliases,
      coefficients: coefficients2,
      get members() {
        if (!resolvedMembers) if (memberRefs) resolvedMembers = memberRefs.map(([name2, factor]) => {
          return {
            constituent: constituents[name2],
            factor
          };
        });
        else resolvedMembers = resolveMembers(nodalCorrection, name, xdo?.[0] ?? 0) ?? [];
        return resolvedMembers;
      },
      value(astro2) {
        if (coefficients2) return computeV0(coefficients2, astro2);
        let v = 0;
        for (const { constituent: c, factor } of constituent.members) v += c.value(astro2) * factor;
        return v;
      },
      correction(astro2, fundamentals2 = fundamentals$2) {
        const fundamental = fundamentals2[name];
        if (fundamental) return fundamental(astro2);
        let f = 1;
        let u = 0;
        for (const { constituent: member, factor } of constituent.members) {
          const corr = member.correction(astro2, fundamentals2);
          u += factor * corr.u;
          f *= Math.pow(corr.f, Math.abs(factor));
        }
        return {
          u,
          f
        };
      }
    };
    [constituent.name, ...aliases].forEach((alias) => {
      constituents[alias] = constituent;
    });
    return constituent;
  }
  function xdoToCoefficients(xdo) {
    return [
      xdo[0],
      xdo[1] - 5,
      xdo[2] - 5,
      xdo[3] - 5,
      xdo[4] - 5,
      xdo[5] - 5,
      5 - xdo[6]
    ];
  }
  function computeV0(coefficients2, astro2) {
    const values = [
      astro2["T+h-s"].value,
      astro2.s.value,
      astro2.h.value,
      astro2.p.value,
      -astro2.N.value,
      astro2.pp.value,
      90
    ];
    let sum = 0;
    for (let i = 0; i < 7; i++) sum += coefficients2[i] * values[i];
    return sum;
  }
  function resolveMembers(code, name, species) {
    switch (code) {
      case "z":
      case "f":
        return null;
      case "y":
        return null;
      case "a":
        return [{
          constituent: constituents["Mm"],
          factor: 1
        }];
      case "m":
        return [{
          constituent: constituents["M2"],
          factor: 1
        }];
      case "o":
        return [{
          constituent: constituents["O1"],
          factor: 1
        }];
      case "k":
        return [{
          constituent: constituents["K1"],
          factor: 1
        }];
      case "j":
        return [{
          constituent: constituents["J1"],
          factor: 1
        }];
      case "b":
        return [{
          constituent: constituents["M2"],
          factor: -1
        }];
      case "c":
        return [{
          constituent: constituents["M2"],
          factor: -2
        }];
      case "g":
        return [{
          constituent: constituents["M2"],
          factor: species / 2
        }];
      case "p":
        return decomposeCompound("2MN2", species, constituents);
      case "d":
        return decomposeCompound("KQ1", species, constituents);
      case "q":
        return decomposeCompound("NKM2", species, constituents);
      case "x":
        return decomposeCompound(name, species, constituents);
    }
  }
  for (const entry of [
    {
      "name": "Zo",
      "speed": 0,
      "xdo": [
        0,
        5,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "z",
      "aliases": ["Z0"]
    },
    {
      "name": "Sa",
      "speed": 0.0410686,
      "xdo": [
        0,
        5,
        6,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "z",
      "aliases": ["SA"]
    },
    {
      "name": "Ssa",
      "speed": 0.0821373,
      "xdo": [
        0,
        5,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "z",
      "aliases": ["SSA"]
    },
    {
      "name": "Sta",
      "speed": 0.1232039,
      "xdo": [
        0,
        5,
        8,
        5,
        5,
        4,
        4
      ],
      "nodalCorrection": "x",
      "aliases": [],
      "members": [["K2", 1], ["T2", -1]]
    },
    {
      "name": "MSm",
      "speed": 0.4715211,
      "xdo": [
        0,
        6,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": [],
      "members": [["M2", 1], ["nu2", -1]]
    },
    {
      "name": "Mnum",
      "speed": 0.4715211,
      "xdo": [
        0,
        6,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["M\u03BDm"],
      "members": [["M2", 1], ["nu2", -1]]
    },
    {
      "name": "Mm",
      "speed": 0.5443747,
      "xdo": [
        0,
        6,
        5,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "y",
      "aliases": ["MM"]
    },
    {
      "name": "MSf",
      "speed": 1.0158958,
      "xdo": [
        0,
        7,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "b",
      "aliases": ["MSF"]
    },
    {
      "name": "MSo",
      "speed": 1.0158958,
      "xdo": [
        0,
        7,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "b",
      "aliases": ["MSO"]
    },
    {
      "name": "SM",
      "speed": 1.0158958,
      "xdo": [
        0,
        7,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": [],
      "members": [["S2", 1], ["M2", -1]]
    },
    {
      "name": "Mf",
      "speed": 1.098033,
      "xdo": [
        0,
        7,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "y",
      "aliases": ["MF"]
    },
    {
      "name": "KOo",
      "speed": 1.098033,
      "xdo": [
        0,
        7,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": [],
      "members": [["K1", 1], ["O1", -1]]
    },
    {
      "name": "MKo",
      "speed": 1.098033,
      "xdo": [
        0,
        7,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": [],
      "members": [["K2", 1], ["M2", -1]]
    },
    {
      "name": "Snu2",
      "speed": 1.4874168,
      "xdo": [
        0,
        8,
        1,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["S\u03BD2"]
    },
    {
      "name": "SN",
      "speed": 1.5602705,
      "xdo": [
        0,
        8,
        3,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": [],
      "members": [["S2", 1], ["N2", -1]]
    },
    {
      "name": "MStm",
      "speed": 1.5695541,
      "xdo": [
        0,
        8,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["MSTM"],
      "members": [
        ["Mf", 1],
        ["M2", 1],
        ["nu2", -1]
      ]
    },
    {
      "name": "Mfm",
      "speed": 1.6424078,
      "xdo": [
        0,
        8,
        5,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "a",
      "aliases": ["MFM", "MTM"]
    },
    {
      "name": "2SM",
      "speed": 2.0317915,
      "xdo": [
        0,
        9,
        1,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "c",
      "aliases": []
    },
    {
      "name": "MSqm",
      "speed": 2.1139287,
      "xdo": [
        0,
        9,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "b",
      "aliases": ["MSQM"]
    },
    {
      "name": "Mqm",
      "speed": 2.1867829,
      "xdo": [
        0,
        9,
        5,
        3,
        5,
        5,
        5
      ],
      "nodalCorrection": "m",
      "aliases": ["MQM"]
    },
    {
      "name": "2SMN",
      "speed": 2.5761662,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": [],
      "members": [
        ["S2", 2],
        ["M2", -1],
        ["N2", -1]
      ]
    },
    {
      "name": "NJ1",
      "speed": 12.854286,
      "xdo": [
        1,
        2,
        5,
        7,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2Q1",
      "speed": 12.8542862,
      "xdo": [
        1,
        2,
        5,
        7,
        5,
        5,
        4
      ],
      "nodalCorrection": "o",
      "aliases": []
    },
    {
      "name": "nuJ1",
      "speed": 12.9271398,
      "xdo": [
        1,
        2,
        7,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "o",
      "aliases": ["\u03BDJ1"]
    },
    {
      "name": "sigma1",
      "speed": 12.9271398,
      "xdo": [
        1,
        2,
        7,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "o",
      "aliases": [
        "\u03C31",
        "SGM",
        "SIGMA1"
      ]
    },
    {
      "name": "NK1",
      "speed": 13.39866,
      "xdo": [
        1,
        3,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "Q1",
      "speed": 13.3986609,
      "xdo": [
        1,
        3,
        5,
        6,
        5,
        5,
        4
      ],
      "nodalCorrection": "o",
      "aliases": []
    },
    {
      "name": "rho1",
      "speed": 13.4715145,
      "xdo": [
        1,
        3,
        7,
        4,
        5,
        5,
        4
      ],
      "nodalCorrection": "o",
      "aliases": [
        "\u03C11",
        "RHO",
        "RHO1"
      ]
    },
    {
      "name": "nuK1",
      "speed": 13.4715146,
      "xdo": [
        1,
        3,
        7,
        4,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": ["\u03BDK1"]
    },
    {
      "name": "O1",
      "speed": 13.9430356,
      "xdo": [
        1,
        4,
        5,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "y",
      "aliases": []
    },
    {
      "name": "MK1",
      "speed": 13.9430356,
      "xdo": [
        1,
        4,
        5,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MS1",
      "speed": 13.9841042,
      "xdo": [
        1,
        4,
        6,
        5,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MP1",
      "speed": 14.0251729,
      "xdo": [
        1,
        4,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "m",
      "aliases": []
    },
    {
      "name": "tau1",
      "speed": 14.0251729,
      "xdo": [
        1,
        4,
        7,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "k",
      "aliases": ["\u03C41", "TAU1"]
    },
    {
      "name": "M1B",
      "speed": 14.4874103,
      "xdo": [
        1,
        5,
        5,
        4,
        5,
        5,
        6
      ],
      "nodalCorrection": "y",
      "aliases": []
    },
    {
      "name": "M1C",
      "speed": 14.492052,
      "xdo": [
        1,
        5,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "y",
      "aliases": []
    },
    {
      "name": "M1",
      "speed": 14.4966939,
      "xdo": [
        1,
        5,
        5,
        6,
        5,
        5,
        6
      ],
      "nodalCorrection": "y",
      "aliases": []
    },
    {
      "name": "NO1",
      "speed": 14.4966939,
      "xdo": [
        1,
        5,
        5,
        6,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "M1A",
      "speed": 14.496694,
      "xdo": [
        1,
        5,
        5,
        6,
        5,
        5,
        6
      ],
      "nodalCorrection": "y",
      "aliases": []
    },
    {
      "name": "LP1",
      "speed": 14.5695476,
      "xdo": [
        1,
        5,
        7,
        4,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "chi1",
      "speed": 14.5695476,
      "xdo": [
        1,
        5,
        7,
        4,
        5,
        5,
        6
      ],
      "nodalCorrection": "j",
      "aliases": ["\u03C71", "CHI1"]
    },
    {
      "name": "pi1",
      "speed": 14.9178647,
      "xdo": [
        1,
        6,
        2,
        5,
        5,
        6,
        4
      ],
      "nodalCorrection": "z",
      "aliases": ["\u03C01", "PI1"]
    },
    {
      "name": "TK1",
      "speed": 14.9178647,
      "xdo": [
        1,
        6,
        2,
        5,
        5,
        6,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "SK1",
      "speed": 14.958931,
      "xdo": [
        1,
        6,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "P1",
      "speed": 14.9589314,
      "xdo": [
        1,
        6,
        3,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "z",
      "aliases": []
    },
    {
      "name": "S1",
      "speed": 15,
      "xdo": [
        1,
        6,
        4,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "z",
      "aliases": []
    },
    {
      "name": "SP1",
      "speed": 15.0410686,
      "xdo": [
        1,
        6,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "K1",
      "speed": 15.0410686,
      "xdo": [
        1,
        6,
        5,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "y",
      "aliases": []
    },
    {
      "name": "MO1",
      "speed": 15.0410686,
      "xdo": [
        1,
        6,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "RP1",
      "speed": 15.0821353,
      "xdo": [
        1,
        6,
        6,
        5,
        5,
        4,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "psi1",
      "speed": 15.0821353,
      "xdo": [
        1,
        6,
        6,
        5,
        5,
        4,
        6
      ],
      "nodalCorrection": "z",
      "aliases": ["\u03C81", "PSI1"]
    },
    {
      "name": "KP1",
      "speed": 15.1232059,
      "xdo": [
        1,
        6,
        7,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "phi1",
      "speed": 15.123206,
      "xdo": [
        1,
        6,
        7,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "j",
      "aliases": ["\u03C61", "PHI1"]
    },
    {
      "name": "lambdaO1",
      "speed": 15.5125897,
      "xdo": [
        1,
        7,
        3,
        6,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": ["\u03BBO1"]
    },
    {
      "name": "theta1",
      "speed": 15.5125897,
      "xdo": [
        1,
        7,
        3,
        6,
        5,
        5,
        6
      ],
      "nodalCorrection": "j",
      "aliases": ["\u03B81", "THETA1"]
    },
    {
      "name": "J1",
      "speed": 15.5854433,
      "xdo": [
        1,
        7,
        5,
        4,
        5,
        5,
        6
      ],
      "nodalCorrection": "y",
      "aliases": []
    },
    {
      "name": "MQ1",
      "speed": 15.5854434,
      "xdo": [
        1,
        7,
        5,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2PO1",
      "speed": 15.9748271,
      "xdo": [
        1,
        8,
        1,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "SO1",
      "speed": 16.0569644,
      "xdo": [
        1,
        8,
        3,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "OO1",
      "speed": 16.1391017,
      "xdo": [
        1,
        8,
        5,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "d",
      "aliases": []
    },
    {
      "name": "ups1",
      "speed": 16.6834764,
      "xdo": [
        1,
        9,
        5,
        4,
        5,
        5,
        6
      ],
      "nodalCorrection": "d",
      "aliases": ["\u03C51", "UPS1"]
    },
    {
      "name": "KQ1",
      "speed": 16.6834764,
      "xdo": [
        1,
        9,
        5,
        4,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MN2S2",
      "speed": 26.407938,
      "xdo": [
        2,
        0,
        9,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3M(SK)2",
      "speed": 26.8701754,
      "xdo": [
        2,
        1,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MKS2",
      "speed": 26.8701754,
      "xdo": [
        2,
        1,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2NS2",
      "speed": 26.8794591,
      "xdo": [
        2,
        1,
        7,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MS2",
      "speed": 26.9523127,
      "xdo": [
        2,
        1,
        9,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["MLN2S2"]
    },
    {
      "name": "3M2S2",
      "speed": 26.952313,
      "xdo": [
        2,
        1,
        9,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2NK2S2",
      "speed": 26.9615964,
      "xdo": [
        2,
        1,
        9,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "OQ2",
      "speed": 27.3416965,
      "xdo": [
        2,
        2,
        5,
        6,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": ["OO2"]
    },
    {
      "name": "MNK2",
      "speed": 27.3416965,
      "xdo": [
        2,
        2,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MNS2",
      "speed": 27.4238338,
      "xdo": [
        2,
        2,
        7,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "eps2",
      "speed": 27.4238338,
      "xdo": [
        2,
        2,
        7,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "m",
      "aliases": ["\u03B52", "EP2"]
    },
    {
      "name": "MnuS2",
      "speed": 27.4966874,
      "xdo": [
        2,
        2,
        9,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["M\u03BDS2"]
    },
    {
      "name": "2ML2S2",
      "speed": 27.4966874,
      "xdo": [
        2,
        2,
        9,
        4,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MNK2S2",
      "speed": 27.505971,
      "xdo": [
        2,
        2,
        9,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MS2K2",
      "speed": 27.8039339,
      "xdo": [
        2,
        3,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MK2",
      "speed": 27.8860712,
      "xdo": [
        2,
        3,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "O2",
      "speed": 27.8860712,
      "xdo": [
        2,
        3,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "NLK2",
      "speed": 27.8860712,
      "xdo": [
        2,
        3,
        5,
        5,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2N2",
      "speed": 27.8953548,
      "xdo": [
        2,
        3,
        5,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "m",
      "aliases": []
    },
    {
      "name": "mu2",
      "speed": 27.9682085,
      "xdo": [
        2,
        3,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "m",
      "aliases": ["\u03BC2", "MU2"]
    },
    {
      "name": "2MS2",
      "speed": 27.9682085,
      "xdo": [
        2,
        3,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "SNK2",
      "speed": 28.3575923,
      "xdo": [
        2,
        4,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "NA2",
      "speed": 28.3986629,
      "xdo": [
        2,
        4,
        4,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "f",
      "aliases": []
    },
    {
      "name": "N2",
      "speed": 28.4397295,
      "xdo": [
        2,
        4,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "m",
      "aliases": []
    },
    {
      "name": "KQ2",
      "speed": 28.4397295,
      "xdo": [
        2,
        4,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "NB2",
      "speed": 28.4807962,
      "xdo": [
        2,
        4,
        6,
        6,
        5,
        4,
        5
      ],
      "nodalCorrection": "f",
      "aliases": []
    },
    {
      "name": "NA2*",
      "speed": 28.480798,
      "xdo": [
        2,
        4,
        6,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "f",
      "aliases": []
    },
    {
      "name": "nu2",
      "speed": 28.5125832,
      "xdo": [
        2,
        4,
        7,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "m",
      "aliases": ["\u03BD2", "NU2"]
    },
    {
      "name": "MKL2S2",
      "speed": 28.5947204,
      "xdo": [
        2,
        4,
        9,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2KN2S2",
      "speed": 28.6040041,
      "xdo": [
        2,
        4,
        9,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MSK2",
      "speed": 28.901967,
      "xdo": [
        2,
        5,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "OP2",
      "speed": 28.901967,
      "xdo": [
        2,
        5,
        3,
        5,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "gamma2",
      "speed": 28.9112506,
      "xdo": [
        2,
        5,
        3,
        7,
        5,
        5,
        7
      ],
      "nodalCorrection": "y",
      "aliases": ["\u03B32", "GAMMA2"]
    },
    {
      "name": "MPS2",
      "speed": 28.9430356,
      "xdo": [
        2,
        5,
        4,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "M(SK)2",
      "speed": 28.9430356,
      "xdo": [
        2,
        5,
        4,
        5,
        5,
        6,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MA2",
      "speed": 28.943036,
      "xdo": [
        2,
        5,
        4,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "f",
      "aliases": []
    },
    {
      "name": "alpha2",
      "speed": 28.9430376,
      "xdo": [
        2,
        5,
        4,
        5,
        5,
        6,
        7
      ],
      "nodalCorrection": "y",
      "aliases": ["\u03B12", "ALPHA2"]
    },
    {
      "name": "M2",
      "speed": 28.9841042,
      "xdo": [
        2,
        5,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "y",
      "aliases": []
    },
    {
      "name": "KO2",
      "speed": 28.9841042,
      "xdo": [
        2,
        5,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MSP2",
      "speed": 29.0251729,
      "xdo": [
        2,
        5,
        6,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MB2",
      "speed": 29.025173,
      "xdo": [
        2,
        5,
        6,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "f",
      "aliases": []
    },
    {
      "name": "MA2*",
      "speed": 29.025173,
      "xdo": [
        2,
        5,
        6,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "f",
      "aliases": []
    },
    {
      "name": "M(KS)2",
      "speed": 29.0251788,
      "xdo": [
        2,
        5,
        6,
        5,
        5,
        4,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MKS2",
      "speed": 29.0662415,
      "xdo": [
        2,
        5,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["3N2"]
    },
    {
      "name": "delta2",
      "speed": 29.066242,
      "xdo": [
        2,
        5,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "y",
      "aliases": ["\u03B42", "DELTA2"]
    },
    {
      "name": "M2(KS)2",
      "speed": 29.148378,
      "xdo": [
        2,
        5,
        9,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["M2KS2"]
    },
    {
      "name": "2KM2S2",
      "speed": 29.1483788,
      "xdo": [
        2,
        5,
        9,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SN(MK)2",
      "speed": 29.373488,
      "xdo": [
        2,
        6,
        1,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["2SNMK2"]
    },
    {
      "name": "lambda2",
      "speed": 29.4556253,
      "xdo": [
        2,
        6,
        3,
        6,
        5,
        5,
        7
      ],
      "nodalCorrection": "m",
      "aliases": [
        "\u03BB2",
        "LAM2",
        "LAMBDA2"
      ]
    },
    {
      "name": "L2",
      "speed": 29.5284789,
      "xdo": [
        2,
        6,
        5,
        4,
        5,
        5,
        7
      ],
      "nodalCorrection": "y",
      "aliases": []
    },
    {
      "name": "2MN2",
      "speed": 29.528479,
      "xdo": [
        2,
        6,
        5,
        4,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "L2A",
      "speed": 29.528479,
      "xdo": [
        2,
        6,
        5,
        4,
        5,
        5,
        7
      ],
      "nodalCorrection": "p",
      "aliases": []
    },
    {
      "name": "3L2",
      "speed": 29.5331208,
      "xdo": [
        2,
        6,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "NKM2",
      "speed": 29.5377626,
      "xdo": [
        2,
        6,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "L2B",
      "speed": 29.537763,
      "xdo": [
        2,
        6,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "q",
      "aliases": []
    },
    {
      "name": "2SK2",
      "speed": 29.9178627,
      "xdo": [
        2,
        7,
        1,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "T2",
      "speed": 29.9589333,
      "xdo": [
        2,
        7,
        2,
        5,
        5,
        6,
        5
      ],
      "nodalCorrection": "z",
      "aliases": []
    },
    {
      "name": "S2",
      "speed": 30,
      "xdo": [
        2,
        7,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "z",
      "aliases": []
    },
    {
      "name": "KP2",
      "speed": 30,
      "xdo": [
        2,
        7,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "R2",
      "speed": 30.0410667,
      "xdo": [
        2,
        7,
        4,
        5,
        5,
        4,
        7
      ],
      "nodalCorrection": "z",
      "aliases": []
    },
    {
      "name": "K2",
      "speed": 30.0821373,
      "xdo": [
        2,
        7,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "y",
      "aliases": []
    },
    {
      "name": "MSnu2",
      "speed": 30.4715211,
      "xdo": [
        2,
        8,
        1,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["MS\u03BD2"]
    },
    {
      "name": "MSN2",
      "speed": 30.5443747,
      "xdo": [
        2,
        8,
        3,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "xi2",
      "speed": 30.5536583,
      "xdo": [
        2,
        8,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "y",
      "aliases": ["\u03BE2", "XI2"]
    },
    {
      "name": "eta2",
      "speed": 30.626512,
      "xdo": [
        2,
        8,
        5,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "y",
      "aliases": ["\u03B72", "ETA2"]
    },
    {
      "name": "KJ2",
      "speed": 30.626512,
      "xdo": [
        2,
        8,
        5,
        4,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2KM(SN)2",
      "speed": 30.7086493,
      "xdo": [
        2,
        8,
        7,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["2KMSN2"]
    },
    {
      "name": "2SM2",
      "speed": 31.0158958,
      "xdo": [
        2,
        9,
        1,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MS2N2",
      "speed": 31.0887494,
      "xdo": [
        2,
        9,
        3,
        3,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "SKM2",
      "speed": 31.098033,
      "xdo": [
        2,
        9,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2Snu2",
      "speed": 31.4874168,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": ["2S\u03BD2"]
    },
    {
      "name": "3(SM)N2",
      "speed": 31.4874168,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SN2",
      "speed": 31.5602705,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "SKN2",
      "speed": 31.6424078,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3S2M2",
      "speed": 32.0317915,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SK2M2",
      "speed": 32.1139288,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MQ3",
      "speed": 42.3827651,
      "xdo": [
        3,
        3,
        5,
        6,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "NO3",
      "speed": 42.3827651,
      "xdo": [
        3,
        3,
        5,
        6,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MO3",
      "speed": 42.9271398,
      "xdo": [
        3,
        4,
        5,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MK3",
      "speed": 42.9271398,
      "xdo": [
        3,
        4,
        5,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2NKM3",
      "speed": 42.9364235,
      "xdo": [
        3,
        4,
        5,
        7,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MS3",
      "speed": 42.9682085,
      "xdo": [
        3,
        4,
        6,
        5,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MP3",
      "speed": 43.0092771,
      "xdo": [
        3,
        4,
        7,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "M3",
      "speed": 43.4761564,
      "xdo": [
        3,
        5,
        5,
        5,
        5,
        5,
        7
      ],
      "nodalCorrection": "g",
      "aliases": []
    },
    {
      "name": "NK3",
      "speed": 43.4807982,
      "xdo": [
        3,
        5,
        5,
        6,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "SO3",
      "speed": 43.9430356,
      "xdo": [
        3,
        6,
        3,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MP3",
      "speed": 43.9430356,
      "xdo": [
        3,
        6,
        3,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MS3",
      "speed": 43.9841042,
      "xdo": [
        3,
        6,
        4,
        5,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MK3",
      "speed": 44.0251729,
      "xdo": [
        3,
        6,
        5,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "NSO3",
      "speed": 44.4966939,
      "xdo": [
        3,
        7,
        3,
        6,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MQ3",
      "speed": 44.5695476,
      "xdo": [
        3,
        7,
        5,
        4,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "T3",
      "speed": 44.9589333,
      "xdo": [
        3,
        8,
        1,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "SP3",
      "speed": 44.9589314,
      "xdo": [
        3,
        8,
        1,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "S3",
      "speed": 45,
      "xdo": [
        3,
        8,
        2,
        5,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "SK3",
      "speed": 45.0410686,
      "xdo": [
        3,
        8,
        3,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": ["R3"]
    },
    {
      "name": "K3",
      "speed": 45.1232059,
      "xdo": [
        3,
        8,
        5,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SO3",
      "speed": 46.0569644,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MS4",
      "speed": 55.936417,
      "xdo": [
        4,
        1,
        9,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4M2S4",
      "speed": 55.936417,
      "xdo": [
        4,
        1,
        9,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MNK4",
      "speed": 56.3258007,
      "xdo": [
        4,
        2,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3NM4",
      "speed": 56.3350844,
      "xdo": [
        4,
        2,
        5,
        8,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MNS4",
      "speed": 56.407938,
      "xdo": [
        4,
        2,
        7,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MnuS4",
      "speed": 56.4807917,
      "xdo": [
        4,
        2,
        9,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["2M\u03BDS4"]
    },
    {
      "name": "3MK4",
      "speed": 56.8701754,
      "xdo": [
        4,
        3,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MNLK4",
      "speed": 56.8701754,
      "xdo": [
        4,
        3,
        5,
        5,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2N4",
      "speed": 56.879459,
      "xdo": [
        4,
        3,
        5,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "N4",
      "speed": 56.8794591,
      "xdo": [
        4,
        3,
        5,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MS4",
      "speed": 56.9523127,
      "xdo": [
        4,
        3,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2NKS4",
      "speed": 56.9615964,
      "xdo": [
        4,
        3,
        7,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MSNK4",
      "speed": 57.3416965,
      "xdo": [
        4,
        4,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MN4",
      "speed": 57.4238338,
      "xdo": [
        4,
        4,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "Mnu4",
      "speed": 57.4966874,
      "xdo": [
        4,
        4,
        7,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["M\u03BD4"]
    },
    {
      "name": "2MLS4",
      "speed": 57.4966874,
      "xdo": [
        4,
        4,
        7,
        4,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MNKS4",
      "speed": 57.5059711,
      "xdo": [
        4,
        4,
        7,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MSK4",
      "speed": 57.8860712,
      "xdo": [
        4,
        5,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MA4",
      "speed": 57.92714,
      "xdo": [
        4,
        5,
        4,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "M4",
      "speed": 57.9682085,
      "xdo": [
        4,
        5,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MRS4",
      "speed": 58.0092752,
      "xdo": [
        4,
        5,
        6,
        5,
        5,
        4,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MKS4",
      "speed": 58.0503458,
      "xdo": [
        4,
        5,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "SN4",
      "speed": 58.4397295,
      "xdo": [
        4,
        6,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MN4",
      "speed": 58.5125832,
      "xdo": [
        4,
        6,
        5,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "ML4",
      "speed": 58.5125832,
      "xdo": [
        4,
        6,
        5,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "KN4",
      "speed": 58.5218668,
      "xdo": [
        4,
        6,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "NK4",
      "speed": 58.521867,
      "xdo": [
        4,
        6,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SMK4",
      "speed": 58.901967,
      "xdo": [
        4,
        7,
        1,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "M2SK4",
      "speed": 58.901967,
      "xdo": [
        4,
        7,
        1,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MT4",
      "speed": 58.9430376,
      "xdo": [
        4,
        7,
        2,
        5,
        5,
        6,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MS4",
      "speed": 58.9841042,
      "xdo": [
        4,
        7,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MR4",
      "speed": 59.0251709,
      "xdo": [
        4,
        7,
        4,
        5,
        5,
        4,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MK4",
      "speed": 59.0662415,
      "xdo": [
        4,
        7,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SNM4",
      "speed": 59.4556253,
      "xdo": [
        4,
        8,
        1,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "SL4",
      "speed": 59.528479,
      "xdo": [
        4,
        8,
        3,
        4,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MSN4",
      "speed": 59.5284794,
      "xdo": [
        4,
        8,
        3,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MKN4",
      "speed": 59.6106162,
      "xdo": [
        4,
        8,
        5,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "ST4",
      "speed": 59.9589333,
      "xdo": [
        4,
        9,
        0,
        5,
        5,
        6,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "S4",
      "speed": 60,
      "xdo": [
        4,
        9,
        1,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "SK4",
      "speed": 60.0821373,
      "xdo": [
        4,
        9,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "K4",
      "speed": 60.1642746,
      "xdo": [
        4,
        9,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3SM4",
      "speed": 61.0158958,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SKM4",
      "speed": 61.098033,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MNO5",
      "speed": 71.3668694,
      "xdo": [
        5,
        3,
        5,
        6,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2NKMS5",
      "speed": 71.453648,
      "xdo": [
        5,
        3,
        7,
        7,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MO5",
      "speed": 71.911244,
      "xdo": [
        5,
        4,
        5,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MK5",
      "speed": 71.9112441,
      "xdo": [
        5,
        4,
        5,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2NK5",
      "speed": 71.9205277,
      "xdo": [
        5,
        4,
        5,
        7,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MS5",
      "speed": 71.9523127,
      "xdo": [
        5,
        4,
        6,
        5,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MP5",
      "speed": 71.9933814,
      "xdo": [
        5,
        4,
        7,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "NSO5",
      "speed": 72.3827651,
      "xdo": [
        5,
        5,
        3,
        6,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "M5",
      "speed": 72.460261,
      "xdo": [
        5,
        5,
        5,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "g",
      "aliases": []
    },
    {
      "name": "MNK5",
      "speed": 72.4649024,
      "xdo": [
        5,
        5,
        5,
        6,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MB5",
      "speed": 72.501329,
      "xdo": [
        5,
        5,
        6,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MSO5",
      "speed": 72.9271398,
      "xdo": [
        5,
        6,
        3,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MP5",
      "speed": 72.92714,
      "xdo": [
        5,
        6,
        3,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MS5",
      "speed": 72.9682085,
      "xdo": [
        5,
        6,
        4,
        5,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MO5",
      "speed": 73.009277,
      "xdo": [
        5,
        6,
        5,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MK5",
      "speed": 73.009277,
      "xdo": [
        5,
        6,
        5,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "NSK5",
      "speed": 73.471515,
      "xdo": [
        5,
        7,
        3,
        4,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MQ5",
      "speed": 73.5536518,
      "xdo": [
        5,
        7,
        5,
        4,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MSP5",
      "speed": 73.9430356,
      "xdo": [
        5,
        8,
        1,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MSK5",
      "speed": 74.0251729,
      "xdo": [
        5,
        8,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3KM5",
      "speed": 74.1073102,
      "xdo": [
        5,
        8,
        5,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SP5",
      "speed": 74.9589314,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SK5",
      "speed": 75.0410686,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "(SK)K5",
      "speed": 75.1232059,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2(MN)K6",
      "speed": 84.7655303,
      "xdo": [
        6,
        1,
        5,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5MKS6",
      "speed": 84.8383839,
      "xdo": [
        6,
        1,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2(MN)S6",
      "speed": 84.8476676,
      "xdo": [
        6,
        1,
        7,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5M2S6",
      "speed": 84.9205212,
      "xdo": [
        6,
        1,
        9,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MNK6",
      "speed": 85.309905,
      "xdo": [
        6,
        2,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "N6",
      "speed": 85.3191886,
      "xdo": [
        6,
        2,
        5,
        8,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MNS6",
      "speed": 85.3920423,
      "xdo": [
        6,
        2,
        7,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["2NMLS6"]
    },
    {
      "name": "3NKS6",
      "speed": 85.4013259,
      "xdo": [
        6,
        2,
        7,
        8,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MnuS6",
      "speed": 85.4648959,
      "xdo": [
        6,
        2,
        9,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["3M\u03BDS6"]
    },
    {
      "name": "4MK6",
      "speed": 85.8542797,
      "xdo": [
        6,
        3,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "M2N6",
      "speed": 85.863563,
      "xdo": [
        6,
        3,
        5,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2NM6",
      "speed": 85.8635633,
      "xdo": [
        6,
        3,
        5,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MS6",
      "speed": 85.936417,
      "xdo": [
        6,
        3,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["2MLNS6"]
    },
    {
      "name": "2NMKS6",
      "speed": 85.9457006,
      "xdo": [
        6,
        3,
        7,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MSNK6",
      "speed": 86.3258007,
      "xdo": [
        6,
        4,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MN6",
      "speed": 86.407938,
      "xdo": [
        6,
        4,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2Mnu6",
      "speed": 86.4807917,
      "xdo": [
        6,
        4,
        7,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["2M\u03BD6", "3MLS6"]
    },
    {
      "name": "2MNO6",
      "speed": 86.480792,
      "xdo": [
        6,
        4,
        7,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MNKS6",
      "speed": 86.4900753,
      "xdo": [
        6,
        4,
        7,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MSK6",
      "speed": 86.8701754,
      "xdo": [
        6,
        5,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MA6",
      "speed": 86.911244,
      "xdo": [
        6,
        5,
        4,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "M6",
      "speed": 86.9523127,
      "xdo": [
        6,
        5,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MKS6",
      "speed": 87.03445,
      "xdo": [
        6,
        5,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MTN6",
      "speed": 87.3827671,
      "xdo": [
        6,
        6,
        2,
        6,
        5,
        6,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MSN6",
      "speed": 87.4238338,
      "xdo": [
        6,
        6,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2ML6",
      "speed": 87.496687,
      "xdo": [
        6,
        6,
        5,
        4,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MN6",
      "speed": 87.4966874,
      "xdo": [
        6,
        6,
        5,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MKN6",
      "speed": 87.505971,
      "xdo": [
        6,
        6,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MNK6",
      "speed": 87.5059711,
      "xdo": [
        6,
        6,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MKnu6",
      "speed": 87.5788247,
      "xdo": [
        6,
        6,
        7,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["MK\u03BD6"]
    },
    {
      "name": "2(MS)K6",
      "speed": 87.8860712,
      "xdo": [
        6,
        7,
        1,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MT6",
      "speed": 87.9271418,
      "xdo": [
        6,
        7,
        2,
        5,
        5,
        6,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MS6",
      "speed": 87.9682085,
      "xdo": [
        6,
        7,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MK6",
      "speed": 88.0503458,
      "xdo": [
        6,
        7,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SN6",
      "speed": 88.4397295,
      "xdo": [
        6,
        8,
        1,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MTN6",
      "speed": 88.4715165,
      "xdo": [
        6,
        8,
        2,
        4,
        5,
        6,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MSL6",
      "speed": 88.512583,
      "xdo": [
        6,
        8,
        3,
        4,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MSN6",
      "speed": 88.5125832,
      "xdo": [
        6,
        8,
        3,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "NSK6",
      "speed": 88.5218668,
      "xdo": [
        6,
        8,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "SNK6",
      "speed": 88.521867,
      "xdo": [
        6,
        8,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MKN6",
      "speed": 88.59472,
      "xdo": [
        6,
        8,
        5,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MKL6",
      "speed": 88.5947205,
      "xdo": [
        6,
        8,
        5,
        4,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MST6",
      "speed": 88.9430376,
      "xdo": [
        6,
        9,
        0,
        5,
        5,
        6,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SM6",
      "speed": 88.9841042,
      "xdo": [
        6,
        9,
        1,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MSK6",
      "speed": 89.0662415,
      "xdo": [
        6,
        9,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "SKM6",
      "speed": 89.066242,
      "xdo": [
        6,
        9,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2KM6",
      "speed": 89.1483788,
      "xdo": [
        6,
        9,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MSTN6",
      "speed": 89.4874123,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2(MS)N6",
      "speed": 89.528479,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MSKN6",
      "speed": 89.6106162,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "S6",
      "speed": 90,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MNO7",
      "speed": 100.3509736,
      "xdo": [
        7,
        3,
        5,
        6,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MQ7",
      "speed": 100.3509736,
      "xdo": [
        7,
        3,
        5,
        6,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MK7",
      "speed": 100.8953483,
      "xdo": [
        7,
        4,
        5,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2NMK7",
      "speed": 100.904632,
      "xdo": [
        7,
        4,
        5,
        7,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MNSO7",
      "speed": 101.3668694,
      "xdo": [
        7,
        5,
        3,
        6,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "M7",
      "speed": 101.4443667,
      "xdo": [
        7,
        5,
        5,
        5,
        5,
        5,
        7
      ],
      "nodalCorrection": "g",
      "aliases": []
    },
    {
      "name": "2MNK7",
      "speed": 101.4490067,
      "xdo": [
        7,
        5,
        5,
        6,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MNKO7",
      "speed": 101.4490067,
      "xdo": [
        7,
        5,
        5,
        6,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MSO7",
      "speed": 101.9112441,
      "xdo": [
        7,
        6,
        3,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MK7",
      "speed": 101.9933814,
      "xdo": [
        7,
        6,
        5,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MSKO7",
      "speed": 103.0092771,
      "xdo": [
        7,
        8,
        3,
        5,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3M2NS8",
      "speed": 113.8317718,
      "xdo": [
        8,
        1,
        7,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MNS8",
      "speed": 114.3761465,
      "xdo": [
        8,
        2,
        7,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5MK8",
      "speed": 114.8383839,
      "xdo": [
        8,
        3,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2(MN)8",
      "speed": 114.8476676,
      "xdo": [
        8,
        3,
        5,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["2MN8"]
    },
    {
      "name": "5MS8",
      "speed": 114.9205212,
      "xdo": [
        8,
        3,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2(MN)KS8",
      "speed": 114.9298048,
      "xdo": [
        8,
        3,
        7,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MSNK8",
      "speed": 115.309905,
      "xdo": [
        8,
        4,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MN8",
      "speed": 115.3920423,
      "xdo": [
        8,
        4,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3Mnu8",
      "speed": 115.4648959,
      "xdo": [
        8,
        4,
        7,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["3M\u03BD8", "4MLS8"]
    },
    {
      "name": "3MNKS8",
      "speed": 115.4741795,
      "xdo": [
        8,
        4,
        7,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MSK8",
      "speed": 115.8542797,
      "xdo": [
        8,
        5,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MA8",
      "speed": 115.895348,
      "xdo": [
        8,
        5,
        4,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "M8",
      "speed": 115.936417,
      "xdo": [
        8,
        5,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MKS8",
      "speed": 116.0185542,
      "xdo": [
        8,
        5,
        7,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MSN8",
      "speed": 116.407938,
      "xdo": [
        8,
        6,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3ML8",
      "speed": 116.4807917,
      "xdo": [
        8,
        6,
        5,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MNK8",
      "speed": 116.4900753,
      "xdo": [
        8,
        6,
        5,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3M2SK8",
      "speed": 116.8701754,
      "xdo": [
        8,
        7,
        1,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2(NS)8",
      "speed": 116.8794591,
      "xdo": [
        8,
        7,
        1,
        7,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MT8",
      "speed": 116.911246,
      "xdo": [
        8,
        7,
        2,
        5,
        5,
        6,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MS8",
      "speed": 116.9523127,
      "xdo": [
        8,
        7,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MK8",
      "speed": 117.03445,
      "xdo": [
        8,
        7,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SNM8",
      "speed": 117.4238338,
      "xdo": [
        8,
        8,
        1,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SMN8",
      "speed": 117.423834,
      "xdo": [
        8,
        8,
        1,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MSL8",
      "speed": 117.4966874,
      "xdo": [
        8,
        8,
        3,
        4,
        5,
        5,
        7
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MSNK8",
      "speed": 117.5059711,
      "xdo": [
        8,
        8,
        3,
        6,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MSN8",
      "speed": 117.578825,
      "xdo": [
        8,
        8,
        5,
        4,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MST8",
      "speed": 117.9271418,
      "xdo": [
        8,
        9,
        0,
        5,
        5,
        6,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2(MS)8",
      "speed": 117.9682085,
      "xdo": [
        8,
        9,
        1,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": ["2MS8"]
    },
    {
      "name": "2MSK8",
      "speed": 118.0503458,
      "xdo": [
        8,
        9,
        3,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2(MK)8",
      "speed": 118.132483,
      "xdo": [
        8,
        9,
        5,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3SN8",
      "speed": 118.4397295,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SML8",
      "speed": 118.5125832,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SKN8",
      "speed": 118.5218668,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MSKL8",
      "speed": 118.5947205,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3SM8",
      "speed": 118.9841042,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SMK8",
      "speed": 119.0662415,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "S8",
      "speed": 120,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MNO9",
      "speed": 129.3350779,
      "xdo": [
        9,
        3,
        5,
        6,
        5,
        5,
        4
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2M2NK9",
      "speed": 129.8887362,
      "xdo": [
        9,
        4,
        5,
        7,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2(MN)K9",
      "speed": 129.888738,
      "xdo": [
        9,
        4,
        5,
        7,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MA9",
      "speed": 130.3874,
      "xdo": [
        9,
        5,
        4,
        5,
        5,
        5,
        5
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MNK9",
      "speed": 130.4331109,
      "xdo": [
        9,
        5,
        5,
        6,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MK9",
      "speed": 130.9774856,
      "xdo": [
        9,
        6,
        5,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MSK9",
      "speed": 131.9933814,
      "xdo": [
        9,
        8,
        3,
        5,
        5,
        5,
        6
      ],
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5MNS10",
      "speed": 143.3602507,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3M2N10",
      "speed": 143.8317718,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "6MS10",
      "speed": 143.9046254,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3M2NKS10",
      "speed": 143.9139091,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MSNK10",
      "speed": 144.2940092,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MN10",
      "speed": 144.3761465,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4Mnu10",
      "speed": 144.4490002,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": ["4M\u03BD10"]
    },
    {
      "name": "5MSK10",
      "speed": 144.8383839,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "M10",
      "speed": 144.9205212,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5MKS10",
      "speed": 145.0026585,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MSN10",
      "speed": 145.3920423,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": ["3MNS10"]
    },
    {
      "name": "6MN10",
      "speed": 145.4648959,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4ML10",
      "speed": 145.4648959,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MNK10",
      "speed": 145.4741795,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2(SN)M10",
      "speed": 145.8635633,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MS10",
      "speed": 145.936417,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MK10",
      "speed": 146.0185542,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2(MS)N10",
      "speed": 146.407938,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MSL10",
      "speed": 146.4807915,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2MNSK10",
      "speed": 146.4900753,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5MSN10",
      "speed": 146.5629217,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3M2S10",
      "speed": 146.9523127,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3MSK10",
      "speed": 147.03445,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3SMN10",
      "speed": 147.4238338,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2SMKN10",
      "speed": 147.5059711,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4M2SN10",
      "speed": 147.578825,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3S2M10",
      "speed": 147.9682085,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2(MS)K10",
      "speed": 148.0503458,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MSK11",
      "speed": 160.9774856,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5M2NS12",
      "speed": 171.7999803,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3(MN)12",
      "speed": 172.2715013,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "6MNS12",
      "speed": 172.344355,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4M2N12",
      "speed": 172.815876,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "7MS12",
      "speed": 172.8887297,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4M2NKS12",
      "speed": 172.8980133,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5MSNK12",
      "speed": 173.2781135,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5MN12",
      "speed": 173.3602507,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3N2MS12",
      "speed": 173.362457,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5Mnu12",
      "speed": 173.4331044,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": ["5M\u03BD12"]
    },
    {
      "name": "6MSK12",
      "speed": 173.8224882,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "MA12",
      "speed": 173.863557,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "M12",
      "speed": 173.9046254,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MSN12",
      "speed": 174.3761465,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": ["4MNS12"]
    },
    {
      "name": "4ML12",
      "speed": 174.449,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MNK12",
      "speed": 174.4582839,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "2(MSN)12",
      "speed": 174.8476676,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5MT12",
      "speed": 174.8794545,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5MS12",
      "speed": 174.9205212,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5MK12",
      "speed": 175.0026585,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3M2SN12",
      "speed": 175.3920423,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "6MSN12",
      "speed": 175.4648959,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": ["4MSL12"]
    },
    {
      "name": "3MNKS12",
      "speed": 175.4741785,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5MSN12",
      "speed": 175.547033,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MST12",
      "speed": 175.8953503,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4M2S12",
      "speed": 175.936417,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "4MSK12",
      "speed": 176.0185542,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3(MS)12",
      "speed": 176.9523127,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "3M2SK12",
      "speed": 177.03445,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5MSN14",
      "speed": 203.3602507,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "5MNK14",
      "speed": 203.442388,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    },
    {
      "name": "6MS14",
      "speed": 203.9046254,
      "xdo": null,
      "nodalCorrection": "x",
      "aliases": []
    }
  ]) defineConstituent(entry);
  var constituents_default = constituents;
  var getDate = (time) => {
    if (time instanceof Date) return time;
    if (typeof time === "number") return /* @__PURE__ */ new Date(time * 1e3);
    throw new Error("Invalid date format, should be a Date object, or timestamp");
  };
  var getTimeline = (start, end, seconds = 600) => {
    const items = [];
    const endTime = Math.ceil(end.getTime() / 1e3 / seconds) * seconds;
    const startTime = Math.floor(start.getTime() / 1e3 / seconds) * seconds;
    let lastTime = startTime;
    const hours = [];
    while (lastTime <= endTime) {
      items.push(/* @__PURE__ */ new Date(lastTime * 1e3));
      hours.push((lastTime - startTime) / 3600);
      lastTime += seconds;
    }
    return {
      items,
      hours
    };
  };
  var harmonicsFactory = ({ harmonicConstituents, constituentModels = constituents_default, offset, fundamentals: fundamentals2 = fundamentals$2, prominenceThreshold }) => {
    if (!Array.isArray(harmonicConstituents)) throw new Error("Harmonic constituents are not an array");
    const constituents2 = [];
    harmonicConstituents.forEach((constituent) => {
      if (typeof constituent.name === "undefined") throw new Error("Harmonic constituents must have a name property");
      if (constituentModels[constituent.name] !== void 0) constituents2.push({
        ...constituent,
        phase: d2r * constituent.phase
      });
    });
    if (offset !== false) constituents2.push({
      name: "Z0",
      phase: 0,
      amplitude: offset
    });
    let start = /* @__PURE__ */ new Date();
    let end = /* @__PURE__ */ new Date();
    const harmonics = {};
    harmonics.setTimeSpan = (startTime, endTime) => {
      start = getDate(startTime);
      end = getDate(endTime);
      if (start.getTime() >= end.getTime()) throw new Error("Start time must be before end time");
      return harmonics;
    };
    harmonics.prediction = (options) => {
      const opts = typeof options !== "undefined" ? options : { timeFidelity: 600 };
      const timeline = getTimeline(start, end, opts.timeFidelity);
      return predictionFactory({
        timeline,
        constituents: constituents2,
        constituentModels,
        start: timeline.items[0] ?? start,
        fundamentals: fundamentals2,
        prominenceThreshold: opts.prominenceThreshold ?? prominenceThreshold
      });
    };
    return Object.freeze(harmonics);
  };
  function createTidePredictor(constituents2, options = {}) {
    const { nodeCorrections, ...harmonicsOpts } = options;
    const harmonicsOptions = {
      harmonicConstituents: constituents2,
      fundamentals: resolveFundamentals(nodeCorrections),
      offset: false,
      ...harmonicsOpts
    };
    return {
      getTimelinePrediction: ({ start, end, timeFidelity, offsets }) => {
        return harmonicsFactory(harmonicsOptions).setTimeSpan(start, end).prediction({ timeFidelity }).getTimelinePrediction({ offsets });
      },
      getExtremesPrediction: ({ start, end, labels, offsets }) => {
        return harmonicsFactory(harmonicsOptions).setTimeSpan(start, end).prediction().getExtremesPrediction({
          labels,
          offsets
        });
      },
      getWaterLevelAtTime: ({ time, offsets }) => {
        const endDate = new Date(time.getTime() + 600 * 1e3);
        return harmonicsFactory(harmonicsOptions).setTimeSpan(time, endDate).prediction().getTimelinePrediction({ offsets })[0];
      }
    };
  }
  createTidePredictor.constituents = constituents_default;

  // src/fit.ts
  var d2r2 = Math.PI / 180;
  var CORRECTION_INTERVAL_HOURS2 = 24;
  function unseparablePairs(models, spanHours) {
    const pairs = [];
    for (let i = 0; i < models.length; i++) {
      for (let j = i + 1; j < models.length; j++) {
        const delta = Math.abs(models[i].speed - models[j].speed);
        const requiredHours = delta === 0 ? Infinity : 360 / delta;
        if (requiredHours > spanHours) {
          pairs.push({
            constituents: [models[i].name, models[j].name],
            requiredDays: Math.ceil(requiredHours / 24)
          });
        }
      }
    }
    return pairs.sort((a, b) => b.requiredDays - a.requiredDays);
  }
  function fit(samples, options) {
    const {
      constituents: names,
      trend = false,
      correctionIntervalHours = CORRECTION_INTERVAL_HOURS2
    } = options;
    if (samples.length < 2) {
      throw new Error("fit needs at least two samples");
    }
    const unknown = names.find((name) => !constituents_default[name]);
    if (unknown) {
      throw new Error(`Unknown constituent: ${unknown}`);
    }
    const baseTime = samples[0].time;
    const baseMs = baseTime.getTime();
    const baseAstro = astro(baseTime);
    const models = names.map((name) => {
      const model = constituents_default[name];
      return {
        name,
        speed: model.speed,
        w: d2r2 * model.speed,
        v0: d2r2 * model.value(baseAstro),
        model
      };
    });
    const hours = samples.map((s) => (s.time.getTime() - baseMs) / 36e5);
    const unseparable = unseparablePairs(models, hours[hours.length - 1] - hours[0]);
    const corrections = /* @__PURE__ */ new Map();
    const correctionsAt = (hour) => {
      const chunk = Math.floor(hour / correctionIntervalHours);
      let cached = corrections.get(chunk);
      if (!cached) {
        const midpoint = new Date(baseMs + (chunk + 0.5) * correctionIntervalHours * 36e5);
        const chunkAstro = astro(midpoint);
        cached = models.map(({ model }) => {
          const correction = model.correction(chunkAstro);
          return { f: correction.f, u: d2r2 * correction.u };
        });
        corrections.set(chunk, cached);
      }
      return cached;
    };
    const trendColumns = trend ? 1 : 0;
    const width = 1 + trendColumns + 2 * models.length;
    const row = new Float64Array(width);
    const buildRow = (index) => {
      const hour = hours[index];
      const correction = correctionsAt(hour);
      row[0] = 1;
      if (trend) row[1] = hour;
      for (let j = 0; j < models.length; j++) {
        const { w, v0 } = models[j];
        const { f, u } = correction[j];
        const theta = w * hour + v0 + u;
        const at = 1 + trendColumns + 2 * j;
        row[at] = f * Math.cos(theta);
        row[at + 1] = f * Math.sin(theta);
      }
      return row;
    };
    const xtx = new Float64Array(width * width);
    const xty = new Float64Array(width);
    for (let i = 0; i < samples.length; i++) {
      const r = buildRow(i);
      const y = samples[i].value;
      for (let a = 0; a < width; a++) {
        if (r[a] === 0) continue;
        xty[a] += r[a] * y;
        for (let b = a; b < width; b++) {
          xtx[a * width + b] += r[a] * r[b];
        }
      }
    }
    for (let a = 0; a < width; a++) {
      for (let b = 0; b < a; b++) {
        xtx[a * width + b] = xtx[b * width + a];
      }
    }
    const solution = choleskySolve(xtx, xty, width);
    const fitted = models.map(({ name }, j) => {
      const at = 1 + trendColumns + 2 * j;
      const a = solution[at];
      const b = solution[at + 1];
      const phase = (Math.atan2(b, a) / d2r2 + 360) % 360;
      return { name, amplitude: Math.hypot(a, b), phase };
    });
    let squared = 0;
    for (let i = 0; i < samples.length; i++) {
      const r = buildRow(i);
      let modelled = 0;
      for (let a = 0; a < width; a++) modelled += r[a] * solution[a];
      const residual = samples[i].value - modelled;
      squared += residual * residual;
    }
    return {
      constituents: fitted,
      offset: solution[0],
      ...trend ? { trend: solution[1] } : {},
      rms: Math.sqrt(squared / samples.length),
      unseparable
    };
  }
  function choleskySolve(a, b, n) {
    const l = new Float64Array(n * n);
    for (let i = 0; i < n; i++) {
      for (let j = 0; j <= i; j++) {
        let sum = a[i * n + j];
        for (let k = 0; k < j; k++) sum -= l[i * n + k] * l[j * n + k];
        if (i === j) {
          if (sum <= 0) {
            throw new Error(
              "Normal matrix is not positive definite \u2014 the series is likely too short to separate the requested constituents"
            );
          }
          l[i * n + i] = Math.sqrt(sum);
        } else {
          l[i * n + j] = sum / l[j * n + j];
        }
      }
    }
    const y = new Float64Array(n);
    for (let i = 0; i < n; i++) {
      let sum = b[i];
      for (let k = 0; k < i; k++) sum -= l[i * n + k] * y[k];
      y[i] = sum / l[i * n + i];
    }
    const x = new Float64Array(n);
    for (let i = n - 1; i >= 0; i--) {
      let sum = y[i];
      for (let k = i + 1; k < n; k++) sum -= l[k * n + i] * x[k];
      x[i] = sum / l[i * n + i];
    }
    return x;
  }

  // src/pipeline.ts
  var BASIS = [
    "M2",
    "S2",
    "N2",
    "K2",
    "K1",
    "O1",
    "P1",
    "Q1",
    "M4",
    "MS4",
    "MN4",
    "2N2",
    "MU2",
    "NU2",
    "L2",
    "T2",
    "J1",
    "MM",
    "MSF",
    "MF",
    "M6",
    "S4",
    "M3"
  ];
  return __toCommonJS(chs_entry_exports);
})();
/*! Bundled license information:

@neaps/tide-predictor/dist/index.js:
  (* v8 ignore if -- @preserve *)
*/
