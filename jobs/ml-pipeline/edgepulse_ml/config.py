from pydantic import BaseModel
import os

class Settings(BaseModel):
    database_url: str = os.environ.get("DATABASE_URL", "")
    feature_window_sec: int = int(os.environ.get("FEATURE_WINDOW_SEC", "300"))
    score_interval_sec: int = int(os.environ.get("SCORE_INTERVAL_SEC", "600"))
    model_dir: str = os.environ.get("MODEL_DIR", "/tmp/models")  # local in-container

settings = Settings()
