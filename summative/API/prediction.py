import io
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator

# ---- Load the saved model (preprocessing + SGDRegressor) once, at startup ----
MODEL_PATH = Path(__file__).parent / "best_model.pkl"
pipeline = joblib.load(MODEL_PATH)

FEATURES = ["country", "iucn_cat", "governance", "rep_area_km2",
            "year", "lat", "lon", "status_year"]
CAT_COLS = ["country", "iucn_cat", "governance"]

# The allowed category values are read from the fitted encoder, so they always
# match what the model was trained on (no hand-typed lists to go out of date).
_encoder = pipeline.named_steps["preprocess"].named_transformers_["cat"]
ALLOWED = {col: set(cats) for col, cats in zip(CAT_COLS, _encoder.categories_)}

RETRAIN_EPOCHS = 5  # passes over the uploaded rows during /retrain

app = FastAPI(
    title="African Protected Area Visitor Estimator",
    description="Estimates annual visitors for an African protected area.",
)

# ---- CORS ----
# Allowed: only the origins listed below (my deployed Render URL and the local
# addresses where I run the Flutter web debug build), only GET and POST, and only
# the Content-Type and Accept headers. Restricted: every other website, every
# other HTTP method and header, and credentials (cookies / auth headers).
# Why: the API has no login, so it needs no credentials, and listing exact
# origins instead of "*" stops random websites from calling it from a browser.
# (The Flutter mobile app is not a browser, so CORS does not apply to it.)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://linear-regression-model-kxzq.onrender.com", 
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://localhost:3000",
    ],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "Accept"],
)


class PredictionInput(BaseModel):
    country: str = Field(..., description="Country, e.g. Kenya")
    iucn_cat: str = Field(..., description="IUCN category, e.g. II, IV, Not Reported")
    governance: str = Field(..., description="Governance type, e.g. Federal or national ministry or agency")
    rep_area_km2: float = Field(..., ge=0.1, le=60000, description="Reported area in km2")
    year: int = Field(..., ge=1950, le=2030, description="Year of the estimate")
    lat: float = Field(..., ge=-35, le=38, description="Latitude (Africa)")
    lon: float = Field(..., ge=-18, le=52, description="Longitude (Africa)")
    status_year: int = Field(..., ge=1800, le=2026, description="Year the park got its current status")

    @field_validator("country", "iucn_cat", "governance")
    @classmethod
    def must_be_known_category(cls, value, info):
        if value not in ALLOWED[info.field_name]:
            raise ValueError(f"must be one of: {sorted(ALLOWED[info.field_name])}")
        return value


@app.get("/")
def home():
    return {"message": "Visitor estimator is running. See /docs for the Swagger UI."}


@app.post("/predict")
def predict(data: PredictionInput):
    row = pd.DataFrame([data.model_dump()])[FEATURES]
    log_prediction = float(pipeline.predict(row)[0])
    visitors = max(float(np.expm1(log_prediction)), 0.0)  # back from the log scale
    return {
        "predicted_annual_visitors": round(visitors),
        "log1p_prediction": round(log_prediction, 4),
    }


@app.post("/retrain")
async def retrain(file: UploadFile = File(...)):
    global pipeline

    if not (file.filename or "").lower().endswith(".csv"):
        raise HTTPException(status_code=400, detail="Please upload a .csv file.")
    try:
        df = pd.read_csv(io.BytesIO(await file.read()))
    except Exception:
        raise HTTPException(status_code=400, detail="Could not read the CSV file.")

    needed = FEATURES + ["visitors"]
    missing = [c for c in needed if c not in df.columns]
    if missing:
        raise HTTPException(status_code=400, detail=f"Missing columns: {missing}")

    # Apply the same cleaning rules as the notebook
    rows_uploaded = len(df)
    df = df[needed].copy()
    df["country"] = df["country"].astype(str).str.replace("\x92", "'", regex=False)
    for col in ["rep_area_km2", "year", "lat", "lon", "status_year", "visitors"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    df = df.dropna()
    df = df[(df["visitors"] > 0) & (df["rep_area_km2"] > 0)
            & (df["status_year"] >= 1800) & (df["lat"] <= 38)]
    for col, allowed in ALLOWED.items():  # categories the model has never seen are skipped
        df = df[df[col].isin(allowed)]

    if df.empty:
        raise HTTPException(status_code=400, detail="No usable rows after cleaning.")

    # Continue training the saved model on the new rows
    X_new = pipeline.named_steps["preprocess"].transform(df[FEATURES])
    y_new = np.log1p(df["visitors"].to_numpy())
    model = pipeline.named_steps["model"]

    mse_before = float(np.mean((model.predict(X_new) - y_new) ** 2))
    for _ in range(RETRAIN_EPOCHS):
        model.partial_fit(X_new, y_new)
    mse_after = float(np.mean((model.predict(X_new) - y_new) ** 2))

    joblib.dump(pipeline, MODEL_PATH)  # /predict uses the updated model straight away

    return {
        "message": "Model updated with the new data.",
        "rows_uploaded": rows_uploaded,
        "rows_used_after_cleaning": len(df),
        "mse_on_new_rows_before": round(mse_before, 3),
        "mse_on_new_rows_after": round(mse_after, 3),
    }