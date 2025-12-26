from __future__ import annotations
import os
import pickle
from sklearn.ensemble import IsolationForest
import pandas as pd

def train_isolation_forest(features: pd.DataFrame) -> IsolationForest:
    X = features[["mean", "std", "median", "mad", "range", "count"]].fillna(0.0).values
    model = IsolationForest(
        n_estimators=200,
        contamination="auto",
        random_state=42,
        n_jobs=-1,
    )
    model.fit(X)
    return model

def save_model(model, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        pickle.dump(model, f)

def load_model(path: str):
    with open(path, "rb") as f:
        return pickle.load(f)
