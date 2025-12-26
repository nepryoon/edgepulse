from __future__ import annotations
import pandas as pd
from .train import load_model

def score_windows(model_path: str, features: pd.DataFrame) -> pd.DataFrame:
    model = load_model(model_path)
    X = features[["mean", "std", "median", "mad", "range", "count"]].fillna(0.0).values

    # IsolationForest: decision_function higher => more normal; we invert for "anomaly_score"
    normality = model.decision_function(X)
    anomaly_score = (-normality).astype(float)

    out = features[["window_end"]].copy()
    out["anomaly_score"] = anomaly_score
    return out
