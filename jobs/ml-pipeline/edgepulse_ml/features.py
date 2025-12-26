from __future__ import annotations
import pandas as pd
import numpy as np

def make_window_features(df: pd.DataFrame, window_sec: int) -> pd.DataFrame:
    """
    df columns expected: ts (datetime64), value (float)
    Produces one row per window_end with robust features.
    """
    if df.empty:
        return pd.DataFrame()

    d = df.copy()
    d["ts"] = pd.to_datetime(d["ts"], utc=True)
    d = d.sort_values("ts").set_index("ts")

    # Resample to 1-second (or keep as-is if dense) – keep it simple for MVP
    # For real usage, you may prefer forward-fill / interpolation rules per metric.
    s = d["value"].astype(float)

    w = f"{window_sec}s"
    g = s.resample(w)

    out = pd.DataFrame({
        "window_end": g.mean().index,
        "mean": g.mean().values,
        "std": g.std(ddof=0).values,
        "min": g.min().values,
        "max": g.max().values,
        "count": g.count().values,
    })

    # Robust stats
    med = g.median()
    out["median"] = med.values

    # MAD (median absolute deviation)
    def mad(x: pd.Series) -> float:
        if x.empty:
            return np.nan
        m = np.median(x.values)
        return float(np.median(np.abs(x.values - m)))

    out["mad"] = g.apply(mad).values

    out["range"] = out["max"] - out["min"]
    out = out.dropna(subset=["mean"])  # keep windows with data

    return out
