from pathlib import Path
from ultralytics import YOLO

ROOT = Path(r"C:\Capstone\GreenGuard_AI_Model")
DATA = ROOT / "dataset" / "data.yaml"

CHECKPOINTS = [
    ("train-6", ROOT / "runs/detect/train-6/weights/best.pt"),
    ("train-7", ROOT / "runs/detect/train-7/weights/best.pt"),
    ("greenguard_final", ROOT / "runs/detect/greenguard_final/weights/best.pt"),
    ("greenguard_full", ROOT / "runs/detect/greenguard_full/weights/best.pt"),
]

for name, checkpoint in CHECKPOINTS:
    print(f"\n{'=' * 60}\nValidating: {name}\n{checkpoint}\n{'=' * 60}")

    if not checkpoint.exists():
        print("SKIPPED: checkpoint not found")
        continue

    try:
        model = YOLO(str(checkpoint))
        metrics = model.val(
            data=str(DATA),
            imgsz=320,
            batch=4,
            plots=True,
            project=str(ROOT / "runs/detect"),
            name=f"validation_{name}",
            exist_ok=True,
        )

        print(f"Precision:  {metrics.box.mp:.4f}")
        print(f"Recall:     {metrics.box.mr:.4f}")
        print(f"mAP50:      {metrics.box.map50:.4f}")
        print(f"mAP50-95:   {metrics.box.map:.4f}")
        print(f"Per-class mAP50-95: {metrics.box.maps}")

    except Exception as error:
        print(f"FAILED: {error}")

print("\nValidation finished.")