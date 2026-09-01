# Purdue OpenCourt

```
SwiftUI iOS app  <->  FastAPI <-> PostgreSQL
```

## Run the API

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Open http://127.0.0.1:8000 — you should see `{"message":"Hello, World"}`.

## Run the iOS app

1. Install Xcode from the Mac App Store
2. Open `ios/OpenCourt/OpenCourt.xcodeproj`.
3. Pick an iPhone simulator and press Run.
