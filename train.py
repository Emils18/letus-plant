from ultralytics import YOLO
import torch


def main():

    device = "0" if torch.cuda.is_available() else "cpu"

    print(
        f"Using device: "
        f"{torch.cuda.get_device_name(0) if device == '0' else 'CPU'}"
    )

    # Use YOLOv8s pretrained model
    model = YOLO("yolov8s.pt")

    model.train(

        # Final corrected 4-class dataset
        data="C:/Capstone/GreenGuard_AI_Model/dataset/data.yaml",

        # Maximum training epochs
        epochs=100,

        # Higher resolution for better disease detail
        imgsz=640,

        # Safer for GTX 1660 Super
        batch=4,

        device=device,

        workers=4,

        # Stop if model stops improving
        patience=20,

        # Keep pretrained YOLO knowledge
        pretrained=True,

        # Generate graphs/results
        plots=True,

        # Fixed random seed
        seed=42,

        # Disable mosaic near final epochs
        close_mosaic=10,

        # Save in a clear folder
        project="C:/Capstone/GreenGuard_AI_Model/runs/detect",

        name="greenguard_final",

        exist_ok=True,
    )


if __name__ == '__main__':
    main()