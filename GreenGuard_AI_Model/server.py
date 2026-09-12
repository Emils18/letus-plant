from pathlib import Path

import cv2
import numpy as np
from flask import Flask, jsonify, request
from ultralytics import YOLO

from image_enhancer import enhance_image


# ============================================================
# PATHS
# ============================================================

BASE_DIR = Path(__file__).resolve().parent

MODEL_PATH = (
    BASE_DIR
    / "runs"
    / "detect"
    / "train-6"
    / "weights"
    / "best.pt"
)


# ============================================================
# CONFIGURATION
# ============================================================

YOLO_IMAGE_SIZE = 320
YOLO_CONFIDENCE = 0.25

# Provisional lettuce confirmation.
#
# This is NOT a replacement for a future
# dedicated lettuce-vs-other-plant classifier.
# The trained lettuce model is the primary evidence.
#
# The old 0.55 + 6% vegetation gate was too strict for
# diseased leaves and could block valid Downy/Powdery/Septoria
# photos before the result reached Flutter.
LETTUCE_CONFIRM_CONFIDENCE = 0.25
STRONG_LETTUCE_CONFIDENCE = 0.40

EXPECTED_MODEL_CLASSES = {
    "Healthy",
    "Downy_Mildew",
    "Powdery_Mildew",
    "Septoria_Blight",
}


# ============================================================
# FLASK APP
# ============================================================

app = Flask(__name__)


# ============================================================
# LOAD YOLO MODEL
# ============================================================

if not MODEL_PATH.exists():
    raise FileNotFoundError(
        f"GreenGuard model was not found:\n"
        f"{MODEL_PATH}"
    )


print()
print("================================")
print("Loading GreenGuard AI model...")
print("================================")
print(f"Model: {MODEL_PATH}")
print()

model = YOLO(
    str(MODEL_PATH)
)

print("GreenGuard AI model loaded.")
print(f"Classes: {model.names}")

if isinstance(model.names, dict):
    loaded_classes = {
        str(value)
        for value in model.names.values()
    }
else:
    loaded_classes = {
        str(value)
        for value in model.names
    }

if loaded_classes != EXPECTED_MODEL_CLASSES:
    raise RuntimeError(
        "Wrong GreenGuard model classes loaded. "
        f"Expected {sorted(EXPECTED_MODEL_CLASSES)}, "
        f"got {sorted(loaded_classes)}"
    )

print(
    "Dataset/model classes verified: "
    "Healthy, Downy_Mildew, "
    "Powdery_Mildew, Septoria_Blight"
)
print()


# ============================================================
# PLANT / VEGETATION VALIDATION
# ============================================================

def check_plant_likelihood(
    image: np.ndarray,
):
    """
    Temporary vegetation validation.

    Determines whether enough of the image
    visually resembles plant material.

    This is the first subject-identification gate:

    Unknown / Non-Plant
        ↓
    Plant
        ↓
    Lettuce
    """

    hsv = cv2.cvtColor(
        image,
        cv2.COLOR_BGR2HSV,
    )

    # --------------------------------------------------------
    # GREEN VEGETATION
    # --------------------------------------------------------

    green_lower = np.array(
        [25, 35, 25],
        dtype=np.uint8,
    )

    green_upper = np.array(
        [100, 255, 255],
        dtype=np.uint8,
    )

    green_mask = cv2.inRange(
        hsv,
        green_lower,
        green_upper,
    )

    # --------------------------------------------------------
    # YELLOW / YELLOW-GREEN
    #
    # Important because diseased lettuce
    # may not remain strongly green.
    # --------------------------------------------------------

    yellow_lower = np.array(
        [15, 30, 40],
        dtype=np.uint8,
    )

    yellow_upper = np.array(
        [35, 255, 255],
        dtype=np.uint8,
    )

    yellow_mask = cv2.inRange(
        hsv,
        yellow_lower,
        yellow_upper,
    )

    vegetation_mask = cv2.bitwise_or(
        green_mask,
        yellow_mask,
    )

    vegetation_pixels = cv2.countNonZero(
        vegetation_mask
    )

    total_pixels = (
        image.shape[0]
        * image.shape[1]
    )

    if total_pixels <= 0:
        return {
            "plant_like": False,
            "vegetation_ratio": 0.0,
        }

    ratio = (
        vegetation_pixels
        / total_pixels
    )

    plant_like = (
        ratio >= 0.035
    )

    return {
        "plant_like":
            plant_like,

        "vegetation_ratio":
            round(
                ratio,
                4,
            ),

        "vegetation_percent":
            round(
                ratio * 100,
                2,
            ),
    }


# ============================================================
# YOLO
# ============================================================

def run_yolo(
    image: np.ndarray,
):
    results = model.predict(
        source=image,
        imgsz=YOLO_IMAGE_SIZE,
        conf=YOLO_CONFIDENCE,
        verbose=False,
    )

    if not results:
        return []

    result = results[0]

    detections = []

    if result.boxes is None:
        return detections

    for box in result.boxes:
        class_id = int(
            box.cls[0].item()
        )

        confidence = float(
            box.conf[0].item()
        )

        coordinates = (
            box.xyxy[0]
            .cpu()
            .tolist()
        )

        if isinstance(
            model.names,
            dict,
        ):
            class_name = (
                model.names.get(
                    class_id,
                    str(class_id),
                )
            )
        else:
            class_name = (
                model.names[
                    class_id
                ]
            )

        display_name = (
            str(class_name)
            .replace(
                "_",
                " ",
            )
        )

        detections.append(
            {
                "class_id":
                    class_id,

                "class_name":
                    str(
                        class_name
                    ),

                "display_name":
                    display_name,

                "confidence":
                    round(
                        confidence,
                        4,
                    ),

                "confidence_percent":
                    round(
                        confidence * 100,
                        2,
                    ),

                "bbox": {
                    "x1":
                        round(
                            float(
                                coordinates[0]
                            ),
                            2,
                        ),

                    "y1":
                        round(
                            float(
                                coordinates[1]
                            ),
                            2,
                        ),

                    "x2":
                        round(
                            float(
                                coordinates[2]
                            ),
                            2,
                        ),

                    "y2":
                        round(
                            float(
                                coordinates[3]
                            ),
                            2,
                        ),
                },
            }
        )

    detections.sort(
        key=lambda item:
        item["confidence"],
        reverse=True,
    )

    return detections


# ============================================================
# SUBJECT IDENTIFICATION
# ============================================================

def identify_subject(
    plant_check,
    detections,
):
    """
    GreenGuard subject hierarchy:

    Unknown / Non-Plant
        ↓
    Plant
        ↓
    Lettuce
        ↓
    Healthy / Disease

    IMPORTANT:

    The four-class YOLO model was trained on the GreenGuard
    lettuce dataset, so a confident detection from that model
    is valid lettuce evidence.

    Vegetation color is only supporting evidence. It must not
    block diseased leaves that are pale, yellow, brown, or have
    large lesion areas.
    """

    plant_like = bool(
        plant_check.get(
            "plant_like",
            False,
        )
    )

    vegetation_ratio = float(
        plant_check.get(
            "vegetation_ratio",
            0.0,
        )
    )

    # --------------------------------------------------------
    # YOLO FOUND A GREEN GUARD CLASS
    # --------------------------------------------------------

    if detections:
        best = detections[0]

        class_name = str(
            best.get(
                "class_name",
                "",
            )
        )

        detection_confidence = float(
            best.get(
                "confidence",
                0.0,
            )
        )

        valid_green_guard_class = (
            class_name
            in EXPECTED_MODEL_CLASSES
        )

        # Strong YOLO evidence can confirm lettuce even when
        # disease symptoms reduce the green vegetation ratio.
        strong_model_evidence = (
            valid_green_guard_class
            and
            detection_confidence
            >= STRONG_LETTUCE_CONFIDENCE
        )

        # For normal plant-looking images, the lower YOLO
        # confidence threshold is enough to continue diagnosis.
        supported_model_evidence = (
            valid_green_guard_class
            and
            plant_like
            and
            detection_confidence
            >= LETTUCE_CONFIRM_CONFIDENCE
        )

        if (
            strong_model_evidence
            or supported_model_evidence
        ):
            return {
                "type":
                    "lettuce",

                "label":
                    "Lettuce",

                "is_plant":
                    True,

                "is_lettuce":
                    True,

                "confidence":
                    round(
                        detection_confidence,
                        4,
                    ),

                "confidence_percent":
                    round(
                        detection_confidence
                        * 100,
                        2,
                    ),

                "evidence":
                    (
                        "strong_yolo"
                        if strong_model_evidence
                        else
                        "vegetation_plus_yolo"
                    ),
            }

    # --------------------------------------------------------
    # PLANT, BUT LETTUCE MODEL NOT CONFIDENT ENOUGH
    # --------------------------------------------------------

    if plant_like:
        best_confidence = (
            float(
                detections[0].get(
                    "confidence",
                    0.0,
                )
            )
            if detections
            else vegetation_ratio
        )

        return {
            "type":
                "plant",

            "label":
                "Plant",

            "is_plant":
                True,

            "is_lettuce":
                False,

            "confidence":
                round(
                    best_confidence,
                    4,
                ),

            "confidence_percent":
                round(
                    best_confidence
                    * 100,
                    2,
                ),

            "evidence":
                "vegetation_only",
        }

    # --------------------------------------------------------
    # UNKNOWN / NON-PLANT
    # --------------------------------------------------------

    return {
        "type":
            "unknown",

        "label":
            "Unknown / Non-Plant",

        "is_plant":
            False,

        "is_lettuce":
            False,

        "confidence":
            0.0,

        "confidence_percent":
            0.0,

        "evidence":
            "no_reliable_plant_or_lettuce_evidence",
    }


# ============================================================
# LOCAL PC TEST PAGE
# ============================================================

@app.route(
    "/test",
    methods=["GET"],
)
def test_page():
    """
    Simple local browser test.

    Open:
        http://127.0.0.1:5000/test

    Choose a lettuce image from the PC and submit it.
    The same /scan pipeline used by Flutter will run:
    enhancer -> subject identification -> trained YOLO model.
    """

    return """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <title>GreenGuard AI Test</title>
        <style>
          body {
            font-family: Arial, sans-serif;
            max-width: 720px;
            margin: 48px auto;
            padding: 24px;
            background: #f6fbf7;
            color: #1e2a1f;
          }
          .card {
            background: white;
            padding: 28px;
            border-radius: 22px;
            border: 1px solid #cfe4d1;
          }
          h1 {
            margin-top: 0;
          }
          input {
            margin: 18px 0;
          }
          button {
            background: #2f6b3b;
            color: white;
            border: 0;
            border-radius: 14px;
            padding: 12px 20px;
            font-weight: bold;
            cursor: pointer;
          }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>GreenGuard AI Local Test</h1>
          <p>
            Upload a lettuce image. This uses the same trained
            GreenGuard model and the same /scan pipeline as the
            Flutter app.
          </p>

          <form
            action="/scan"
            method="post"
            enctype="multipart/form-data"
          >
            <input
              type="file"
              name="image"
              accept="image/*"
              required
            >
            <br>
            <button type="submit">
              Run GreenGuard AI
            </button>
          </form>
        </div>
      </body>
    </html>
    """


# ============================================================
# ROOT
# ============================================================

@app.route(
    "/",
    methods=["GET"],
)
def root():
    return jsonify(
        {
            "service":
                "GreenGuard AI Server",

            "online":
                True,

            "model":
                MODEL_PATH.name,

            "classes":
                model.names,

            "model_classes_verified":
                True,

            "dataset_classes": [
                "Healthy",
                "Downy_Mildew",
                "Powdery_Mildew",
                "Septoria_Blight",
            ],

            "pipeline": [
                "image_enhancer",
                "subject_identification",
                "lettuce_diagnosis",
            ],

            "subject_types": [
                "Unknown / Non-Plant",
                "Plant",
                "Lettuce",
            ],

            "lettuce_results": [
                "Healthy",
                "Downy Mildew",
                "Powdery Mildew",
                "Septoria Blight",
            ],
        }
    )


# ============================================================
# HEALTH
# ============================================================

@app.route(
    "/health",
    methods=["GET"],
)
def health():
    return jsonify(
        {
            "online":
                True,

            "model_loaded":
                True,

            "image_enhancer":
                True,

            "subject_identification":
                True,

            "model_classes_verified":
                True,

            "model_path":
                str(
                    MODEL_PATH
                ),
        }
    )


# ============================================================
# SCAN
# ============================================================

@app.route(
    "/scan",
    methods=["POST"],
)
def scan():

    # ========================================================
    # CHECK IMAGE UPLOAD
    # ========================================================

    if "image" not in request.files:
        return jsonify(
            {
                "success":
                    False,

                "error":
                    "image_missing",

                "message":
                    "No image was provided.",
            }
        ), 400

    uploaded_file = (
        request.files[
            "image"
        ]
    )

    image_bytes = (
        uploaded_file.read()
    )

    if not image_bytes:
        return jsonify(
            {
                "success":
                    False,

                "error":
                    "empty_image",

                "message":
                    "The uploaded image is empty.",
            }
        ), 400

    # ========================================================
    # DECODE JPEG
    # ========================================================

    np_buffer = np.frombuffer(
        image_bytes,
        dtype=np.uint8,
    )

    image = cv2.imdecode(
        np_buffer,
        cv2.IMREAD_COLOR,
    )

    if image is None:
        return jsonify(
            {
                "success":
                    False,

                "error":
                    "invalid_image",

                "message":
                    "The uploaded file could not be decoded as an image.",
            }
        ), 400

    # ========================================================
    # IMAGE ENHANCER SYSTEM
    # ========================================================

    try:
        (
            processing_image,
            enhancement,
        ) = enhance_image(
            image
        )

    except Exception as error:
        return jsonify(
            {
                "success":
                    False,

                "error":
                    "enhancement_failed",

                "message":
                    str(error),
            }
        ), 500

    # ========================================================
    # RETAKE: IMAGE QUALITY TOO POOR
    # ========================================================

    if enhancement[
        "retake_required"
    ]:
        reason = enhancement[
            "reason"
        ]

        if (
            reason
            == "image_too_dark"
        ):
            message = (
                "The photo is too dark. "
                "Increase lighting or use "
                "the ESP32-CAM flash, then retake."
            )

        elif (
            reason
            == "image_too_blurry"
        ):
            message = (
                "The photo is too blurry. "
                "Keep the camera steady "
                "and retake the photo."
            )

        else:
            message = (
                "The image quality is not sufficient. "
                "Please retake the photo."
            )

        return jsonify(
            {
                "success":
                    False,

                "diagnosis_available":
                    False,

                "retake_required":
                    True,

                "error":
                    reason,

                "message":
                    message,

                "enhancement":
                    enhancement,
            }
        ), 422

    # ========================================================
    # PLANT VALIDATION
    # ========================================================

    plant_check = (
        check_plant_likelihood(
            processing_image
        )
    )

    # ========================================================
    # YOLO
    #
    # Don't waste inference if vegetation
    # was not detected at all.
    # ========================================================

    # Always run the trained GreenGuard YOLO model.
    #
    # Diseased lettuce may contain little green/yellow area,
    # so HSV vegetation must not prevent YOLO inference.
    detections = (
        run_yolo(
            processing_image
        )
    )

    # ========================================================
    # UNKNOWN / PLANT / LETTUCE
    # ========================================================

    subject = identify_subject(
        plant_check,
        detections,
    )

    # ========================================================
    # UNKNOWN / NON-PLANT
    # ========================================================

    if subject[
        "type"
    ] == "unknown":

        return jsonify(
            {
                "success":
                    True,

                "diagnosis_available":
                    False,

                "retake_required":
                    False,

                "retake_recommended":
                    True,

                "message":
                    "GreenGuard could not identify a visible plant in the image.",

                "subject":
                    subject,

                "enhancement":
                    enhancement,

                "plant_validation":
                    plant_check,

                "detections":
                    [],
            }
        ), 200

    # ========================================================
    # PLANT BUT NOT CONFIRMED LETTUCE
    # ========================================================

    if subject[
        "type"
    ] == "plant":

        return jsonify(
            {
                "success":
                    True,

                "diagnosis_available":
                    False,

                "retake_required":
                    False,

                "retake_recommended":
                    True,

                "message":
                    "A plant was detected, but GreenGuard could not confidently confirm that it is lettuce.",

                "subject":
                    subject,

                "enhancement":
                    enhancement,

                "plant_validation":
                    plant_check,

                "detections":
                    detections,
            }
        ), 200

    # ========================================================
    # LETTUCE CONFIRMED
    # ========================================================

    best_detection = (
        detections[0]
    )

    class_name = str(
        best_detection[
            "class_name"
        ]
    )

    normalized_class = (
        class_name
        .strip()
        .lower()
        .replace(
            " ",
            "_",
        )
    )

    is_healthy = (
        normalized_class
        == "healthy"
    )

    display_name = (
        class_name
        .replace(
            "_",
            " ",
        )
    )

    # ========================================================
    # SUCCESS
    # ========================================================

    return jsonify(
        {
            "success":
                True,

            "diagnosis_available":
                True,

            "retake_required":
                False,

            "retake_recommended":
                False,

            "message":
                "GreenGuard lettuce scan completed.",

            # ------------------------------------------------
            # SUBJECT
            # ------------------------------------------------

            "subject":
                subject,

            # ------------------------------------------------
            # IMAGE ENHANCER REPORT
            # ------------------------------------------------

            "enhancement":
                enhancement,

            # ------------------------------------------------
            # PLANT VALIDATION
            # ------------------------------------------------

            "plant_validation":
                plant_check,

            # ------------------------------------------------
            # FINAL LETTUCE RESULT
            # ------------------------------------------------

            "result": {
                "class_name":
                    class_name,

                "display_name":
                    display_name,

                "confidence":
                    best_detection[
                        "confidence"
                    ],

                "confidence_percent":
                    best_detection[
                        "confidence_percent"
                    ],

                "healthy":
                    is_healthy,

                "status":
                    (
                        "healthy"
                        if is_healthy
                        else "disease_detected"
                    ),
            },

            # ------------------------------------------------
            # ALL YOLO DETECTIONS
            # ------------------------------------------------

            "detections":
                detections,
        }
    ), 200


# ============================================================
# START SERVER
# ============================================================

if __name__ == "__main__":

    print()
    print("================================")
    print("GreenGuard AI Server")
    print("================================")
    print(f"Model: {MODEL_PATH}")
    print(
        "Image Enhancer: READY"
    )
    print(
        "Subject Identification: READY"
    )
    print(
        "Server: http://0.0.0.0:5000"
    )
    print()

    app.run(
        host="0.0.0.0",
        port=5000,
        debug=False,
        threaded=True,
    )