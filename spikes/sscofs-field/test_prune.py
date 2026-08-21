# test_prune.py — run: uv run --with pytest,numpy pytest -q test_prune.py
#
# (a) synthetic recovery: build a 60 d hourly series from 3 known constituents
# (M2/K1/M4, known amp/phase) + noise, assert fit_elements recovers amplitude
# within 0.02 kn and R^2 > 0.95 against the full 23-name basis (the other 20
# constituents have no signal, only noise, and should fit near zero).
# (b) quantization math: bundle_bytes(kept_counts) == sum(8 + 5*2*k).
# (c) energy floor is per-axis, kept if either axis clears (§10): one
# constituent clearing only its u-axis floor is kept; one clearing neither
# axis's floor is dropped. floor = max(2% of that axis's max, 0.005 kn).
import numpy as np

from prune_proof import basis_speeds, bundle_bytes, energy_floor_keep, fit_elements


def test_bundle_bytes_known_inputs():
    kept = [3, 0, 10, 1, 23]
    assert bundle_bytes(kept) == sum(8 + 5 * 2 * k for k in kept)


def test_energy_floor_keeps_if_either_axis_clears():
    # one synthetic element, 3 constituents. floor_u = max(0.02*1.0, 0.005)
    # = 0.02; floor_v = max(0.02*0.003, 0.005) = 0.005 (floors pin the
    # worked example in the brief).
    amp_u = np.array([[1.0], [0.03], [0.004]])  # c0/c1 clear floor_u, c2 doesn't
    amp_v = np.array([[0.001], [0.003], [0.002]])  # none clear floor_v
    floor_u = max(0.02 * amp_u.max(), 0.005)
    floor_v = max(0.02 * amp_v.max(), 0.005)
    assert floor_u == 0.02
    assert floor_v == 0.005
    keep = energy_floor_keep(amp_u, amp_v)
    # c0/c1 kept via u-axis alone (v-axis doesn't clear); c2 clears neither -> dropped.
    assert keep[:, 0].tolist() == [True, True, False]


def test_fit_elements_recovers_synthetic_constituents():
    speeds = basis_speeds()
    names = list(speeds.keys())
    speed_list = [speeds[n] for n in names]

    n_hours = 60 * 24
    t = np.arange(n_hours, dtype=np.float64) * 3600.0  # epoch seconds, hourly
    t_hours = t / 3600.0

    truth = {"M2": (1.0, 0.7), "K1": (0.4, -1.2), "M4": (0.1, 2.0)}  # amp kn, phase rad
    signal = np.zeros_like(t_hours)
    for name, (amp, phase) in truth.items():
        theta = np.radians(speeds[name]) * t_hours
        signal += amp * np.cos(theta - phase)

    rng = np.random.default_rng(0)
    noisy = signal + rng.normal(0.0, 0.05, size=t_hours.shape)
    U = noisy[:, None]  # one synthetic element

    const, r2 = fit_elements(t, U, speed_list)
    assert r2[0] > 0.95, f"R^2 too low: {r2[0]}"

    for name, (amp, phase) in truth.items():
        i = names.index(name)
        a_cos, a_sin = const[1 + 2 * i, 0], const[2 + 2 * i, 0]
        recovered = float(np.hypot(a_cos, a_sin))
        assert abs(recovered - amp) < 0.02, f"{name}: recovered {recovered} vs truth {amp}"
