from __future__ import annotations

from typing import Any

import cv2
import numpy as np


# ============================================================
# GREENGUARD IMAGE ENHANCER
# ============================================================

LOW_LIGHT_THRESHOLD = 95.0
LOW_CONTRAST_THRESHOLD = 28.0
SOFT_IMAGE_THRESHOLD = 80.0


# ============================================================
# IMAGE ANALYSIS
# ============================================================

def analyze_image(
    image: np.ndarray,
) -> dict[str, Any]:
    if image is None or image.size == 0:
        raise ValueError(
            "Image is empty."
        )

    gray = cv2.cvtColor(
        image,
        cv2.COLOR_BGR2GRAY,
    )

    brightness = float(
        np.mean(gray)
    )

    contrast = float(
        np.std(gray)
    )

    blur_score = float(
        cv2.Laplacian(
            gray,
            cv2.CV_64F,
        ).var()
    )

    hsv = cv2.cvtColor(
        image,
        cv2.COLOR_BGR2HSV,
    )

    saturation = float(
        np.mean(
            hsv[:, :, 1]
        )
    )

    low_light = (
        brightness
        < LOW_LIGHT_THRESHOLD
    )

    low_contrast = (
        contrast
        < LOW_CONTRAST_THRESHOLD
    )

    slightly_soft = (
        blur_score
        < SOFT_IMAGE_THRESHOLD
    )

    # Diagnostic flags only.
    # They no longer trigger rejection.
    too_dark = (
        brightness
        < 10.0
    )

    too_blurry = (
        blur_score
        < 5.0
    )

    return {
        "brightness": round(
            brightness,
            2,
        ),

        "contrast": round(
            contrast,
            2,
        ),

        "blur_score": round(
            blur_score,
            2,
        ),

        "saturation": round(
            saturation,
            2,
        ),

        "too_dark":
            too_dark,

        "low_light":
            low_light,

        "low_contrast":
            low_contrast,

        "too_blurry":
            too_blurry,

        "slightly_soft":
            slightly_soft,
    }


# ============================================================
# ADAPTIVE GAMMA BRIGHTNESS
# ============================================================

def _apply_gamma(
    image: np.ndarray,
    gamma: float,
) -> np.ndarray:
    gamma = max(
        gamma,
        0.05,
    )

    table = np.array(
        [
            ((i / 255.0) ** gamma)
            * 255.0
            for i in range(256)
        ],
        dtype=np.uint8,
    )

    return cv2.LUT(
        image,
        table,
    )


def _apply_adaptive_brightness(
    image: np.ndarray,
) -> np.ndarray:
    gray = cv2.cvtColor(
        image,
        cv2.COLOR_BGR2GRAY,
    )

    brightness = float(
        np.mean(gray)
    )

    if brightness < 15.0:
        gamma = 0.35
    elif brightness < 25.0:
        gamma = 0.45
    elif brightness < 40.0:
        gamma = 0.56
    elif brightness < 55.0:
        gamma = 0.67
    elif brightness < 70.0:
        gamma = 0.78
    elif brightness < 85.0:
        gamma = 0.87
    else:
        gamma = 0.94

    return _apply_gamma(
        image,
        gamma,
    )


# ============================================================
# CLAHE
# ============================================================

def _apply_clahe(
    image: np.ndarray,
) -> np.ndarray:
    lab = cv2.cvtColor(
        image,
        cv2.COLOR_BGR2LAB,
    )

    l_channel, a_channel, b_channel = (
        cv2.split(lab)
    )

    clahe = cv2.createCLAHE(
        clipLimit=1.8,
        tileGridSize=(8, 8),
    )

    enhanced_l = clahe.apply(
        l_channel
    )

    enhanced_lab = cv2.merge(
        (
            enhanced_l,
            a_channel,
            b_channel,
        )
    )

    return cv2.cvtColor(
        enhanced_lab,
        cv2.COLOR_LAB2BGR,
    )


# ============================================================
# MILD DENOISING
# ============================================================

def _apply_mild_denoise(
    image: np.ndarray,
) -> np.ndarray:
    return cv2.bilateralFilter(
        image,
        d=5,
        sigmaColor=22,
        sigmaSpace=22,
    )


# ============================================================
# MILD SHARPENING
# ============================================================

def _apply_mild_sharpen(
    image: np.ndarray,
) -> np.ndarray:
    blurred = cv2.GaussianBlur(
        image,
        (0, 0),
        1.0,
    )

    return cv2.addWeighted(
        image,
        1.12,
        blurred,
        -0.12,
        0,
    )


# ============================================================
# MAIN ENHANCER PIPELINE
# ============================================================

def enhance_image(
    image: np.ndarray,
) -> tuple[
    np.ndarray,
    dict[str, Any],
]:
    before = analyze_image(
        image
    )

    processing_image = (
        image.copy()
    )

    operations: list[str] = []

    # Dark photo:
    # improve it instead of rejecting it.
    if before["low_light"]:
        processing_image = (
            _apply_mild_denoise(
                processing_image
            )
        )

        operations.append(
            "mild_denoise"
        )

        processing_image = (
            _apply_adaptive_brightness(
                processing_image
            )
        )

        operations.append(
            "adaptive_brightness"
        )

    # Low contrast:
    # improve clarity.
    if (
        before["low_contrast"]
        or before["low_light"]
    ):
        processing_image = (
            _apply_clahe(
                processing_image
            )
        )

        operations.append(
            "clahe"
        )

    # Soft / blurry:
    # sharpen mildly instead of rejecting it.
    if (
        before["slightly_soft"]
        or before["too_blurry"]
    ):
        processing_image = (
            _apply_mild_sharpen(
                processing_image
            )
        )

        operations.append(
            "mild_sharpen"
        )

    after = analyze_image(
        processing_image
    )

    # Any valid decoded image is accepted.
    return (
        processing_image,
        {
            "enhanced":
                bool(
                    operations
                ),

            "retake_required":
                False,

            "reason":
                None,

            "operations":
                operations,

            "before":
                before,

            "after":
                after,
        },
    )
