# African Protected Area Visitor Estimator

My mission is to build practical, locally grounded tools that help African communities benefit from the places they protect.
Many African protected areas have inconsistent or missing visitor records, so managers struggle to plan staffing, budgets and fees.
This project predicts a protected area's annual visitor numbers from its country, size, location, governance, conservation category and age.
Park managers and conservation planners use it to get a baseline estimate where no counts exist.

## Dataset

The data is the Database of African Protected Area Visitation (PAVIS v1.0): Buschke, F., Capitani, C., Schägner, P., Nsengiyumva, C., Okelo, H., Cissé, O., & Snyman, S. (2025). A dataset of pre-pandemic African protected area visitation. *Scientific Data*, 12, 764. https://doi.org/10.1038/s41597-025-04998-7 (v1.0 archive: https://zenodo.org/records/14357871). It contains 4,216 visitor-count records from 341 protected areas in 34 African countries.

I used `clean_pavis.csv`, a cleaned 13-column copy published by Christian Adeoye Adebambo in https://github.com/christianadebambo/africa-PA-forecasting (MIT licence, copyright 2025 Christian Adeoye Adebambo) for his separate forecasting project; this project only reuses that file. After my own cleaning (see the notebook), 3,618 rows remain. The target is annual visitors (modelled as log(1 + visitors)), and the 8 input features are country, IUCN category, governance type, reported area (km²), year, latitude, longitude and the year the park got its current status.

## Public API (Swagger UI)

https://linear-regression-model-kxzq.onrender.com/docs

The free Render plan sleeps after 15 minutes without traffic, so the first request can take up to a minute.

## Video demo

YOUR_YOUTUBE_LINK

## Run the mobile app

1. Install Flutter and set up an Android emulator (or connect an Android phone with USB debugging on). Check with `flutter doctor`.
2. Clone the repository:
   ```
   git clone https://github.com/erin-leyian/linear_regression_model.git
   cd linear_regression_model/summative/FlutterApp
   ```
3. Download the dependencies:
   ```
   flutter pub get
   ```
4. Start the emulator (or plug in the phone) and confirm Flutter sees it:
   ```
   flutter devices
   ```
5. Run the app:
   ```
   flutter run
   ```
6. Fill in all 8 fields (for example Algeria / II / Federal or national ministry or agency / 265.87 / 2019 / 36.401 / 2.853 / 1983) and tap **Predict**. The prediction, or an error message for a missing, wrong-type or out-of-range value, appears in the box under the button. The first request may take up to a minute while the API wakes up.