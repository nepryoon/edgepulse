from __future__ import annotations
import os
import typer
from .config import settings
from .db import fetch_df, execute
from .features import make_window_features
from .train import train_isolation_forest, save_model
from .score import score_windows

app = typer.Typer(help="EdgePulse ML jobs (features/train/score)")

@app.command()
def features(tenant: str, metric: str, since_hours: int = 24):
    """
    Compute window features for a metric over the last N hours.
    """
    df = fetch_df(
        """
        SELECT ts, value
          FROM datapoints
         WHERE tenant_id = %s
           AND metric_id = %s
           AND ts >= NOW() - (%s || ' hours')::interval
         ORDER BY ts ASC
        """,
        (tenant, metric, since_hours),
    )
    feats = make_window_features(df, settings.feature_window_sec)
    typer.echo(feats.tail(10).to_string(index=False))

@app.command()
def train(tenant: str, metric: str, lookback_days: int = 30):
    """
    Train (or refresh) an Isolation Forest model for a metric.
    """
    df = fetch_df(
        """
        SELECT ts, value
          FROM datapoints
         WHERE tenant_id = %s
           AND metric_id = %s
           AND ts >= NOW() - (%s || ' days')::interval
         ORDER BY ts ASC
        """,
        (tenant, metric, lookback_days),
    )
    feats = make_window_features(df, settings.feature_window_sec)
    if feats.empty:
        raise typer.Exit(code=2)

    model = train_isolation_forest(feats)
    model_path = os.path.join(settings.model_dir, tenant, f"{metric}.pkl")
    save_model(model, model_path)

    # Optional: record model metadata in DB
    execute(
        """
        INSERT INTO models (tenant_id, metric_id, model_type, artefact_path)
        VALUES (%s, %s, %s, %s)
        ON CONFLICT (tenant_id, metric_id, model_type)
        DO UPDATE SET artefact_path = EXCLUDED.artefact_path, updated_at = NOW()
        """,
        (tenant, metric, "isolation_forest_v1", model_path),
    )

    typer.echo(f"Model saved: {model_path}")

@app.command()
def score(tenant: str, metric: str, since_hours: int = 24):
    """
    Score windows and persist anomaly_scores.
    """
    # Locate model
    m = fetch_df(
        """
        SELECT artefact_path
          FROM models
         WHERE tenant_id = %s
           AND metric_id = %s
           AND model_type = %s
         LIMIT 1
        """,
        (tenant, metric, "isolation_forest_v1"),
    )
    if m.empty:
        raise typer.Exit(code=2)

    model_path = str(m.iloc[0]["artefact_path"])

    df = fetch_df(
        """
        SELECT ts, value
          FROM datapoints
         WHERE tenant_id = %s
           AND metric_id = %s
           AND ts >= NOW() - (%s || ' hours')::interval
         ORDER BY ts ASC
        """,
        (tenant, metric, since_hours),
    )
    feats = make_window_features(df, settings.feature_window_sec)
    if feats.empty:
        typer.echo("No feature windows to score.")
        raise typer.Exit(code=0)

    scores = score_windows(model_path, feats)

    # Persist scores
    for _, r in scores.iterrows():
        execute(
            """
            INSERT INTO anomaly_scores (tenant_id, metric_id, window_end, anomaly_score)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (tenant_id, metric_id, window_end)
            DO UPDATE SET anomaly_score = EXCLUDED.anomaly_score, updated_at = NOW()
            """,
            (tenant, metric, r["window_end"].to_pydatetime(), float(r["anomaly_score"])),
        )

    typer.echo(f"Inserted/updated {len(scores)} anomaly score rows.")
