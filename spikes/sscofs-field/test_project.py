# test_project.py — run: uv run --with pytest,numpy pytest -q test_project.py
import numpy as np
from make_samples import project_signed_kn

def test_pure_flood_is_positive():
    # flow toward 100° at 2 m/s, flood axis 100° → +2*1.94384 kn
    u = 2 * np.sin(np.radians(100)); v = 2 * np.cos(np.radians(100))
    assert abs(project_signed_kn(np.array([u]), np.array([v]), 100.0)[0] - 3.88768) < 1e-4

def test_pure_ebb_is_negative():
    u = 1.5 * np.sin(np.radians(280)); v = 1.5 * np.cos(np.radians(280))
    assert project_signed_kn(np.array([u]), np.array([v]), 100.0)[0] < -2.9

def test_cross_axis_is_zero():
    u = 3 * np.sin(np.radians(190)); v = 3 * np.cos(np.radians(190))
    assert abs(project_signed_kn(np.array([u]), np.array([v]), 100.0)[0]) < 1e-9
