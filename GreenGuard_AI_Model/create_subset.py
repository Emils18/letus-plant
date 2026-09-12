from pathlib import Path
from datetime import datetime
import shutil


BASE_DIR = Path("C:/Capstone/GreenGuard_AI_Model")

RAW_DISEASE_DIR = BASE_DIR / "raw_dataset"
HEALTHY_DIR_1 = BASE_DIR / "healthy_dataset"
HEALTHY_DIR_2 = BASE_DIR / "healthy_dataset_2"

TARGET_DIR = BASE_DIR / "dataset"


FINAL_CLASSES = {
    0: "Healthy",
    1: "Downy_Mildew",
    2: "Powdery_Mildew",
    3: "Septoria_Blight",
}


# raw_dataset
# 0 = Bacterial              -> exclude
# 1 = Downy                  -> 1
# 2 = Lettuce Mosaic Virus   -> exclude
# 3 = Powdery                -> 2
# 4 = Septoria               -> 3

DISEASE_CLASS_MAP = {
    1: 1,
    3: 2,
    4: 3,
}

DISEASE_EXCLUDED_CLASSES = {
    0,
    2,
}


# healthy_dataset
# 0 = healthy -> Healthy

HEALTHY_1_CLASS_MAP = {
    0: 0,
}

HEALTHY_1_EXCLUDED_CLASSES = set()


# healthy_dataset_2
# 0 = H               -> Healthy
# 1 = Healthy Lettuce -> Healthy
# 2 = Viral           -> exclude
# 3 = healthy         -> Healthy

HEALTHY_2_CLASS_MAP = {
    0: 0,
    1: 0,
    3: 0,
}

HEALTHY_2_EXCLUDED_CLASSES = {
    2,
}


IMAGE_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".bmp",
    ".webp",
}


def backup_existing_dataset():
    if not TARGET_DIR.exists():
        return

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    backup_dir = BASE_DIR / f"dataset_backup_{timestamp}"

    print()
    print("Existing dataset found.")
    print("Backing up to:")
    print(backup_dir)

    TARGET_DIR.rename(backup_dir)


def read_label_file(label_path: Path):
    if not label_path.exists():
        return []

    lines = []

    with label_path.open("r", encoding="utf-8") as file:
        for raw_line in file:
            raw_line = raw_line.strip()

            if not raw_line:
                continue

            parts = raw_line.split()

            if len(parts) < 5:
                continue

            lines.append(parts)

    return lines


def clamp(value):
    return max(0.0, min(1.0, value))


def polygon_to_box(values):
    """
    Converts YOLO polygon:

    x1 y1 x2 y2 x3 y3 ...

    into YOLO detection box:

    x_center y_center width height
    """

    if len(values) < 6:
        return None

    if len(values) % 2 != 0:
        return None

    try:
        coords = [float(v) for v in values]
    except ValueError:
        return None

    xs = coords[0::2]
    ys = coords[1::2]

    x_min = clamp(min(xs))
    x_max = clamp(max(xs))
    y_min = clamp(min(ys))
    y_max = clamp(max(ys))

    width = x_max - x_min
    height = y_max - y_min

    if width <= 0 or height <= 0:
        return None

    x_center = (x_min + x_max) / 2.0
    y_center = (y_min + y_max) / 2.0

    return (
        clamp(x_center),
        clamp(y_center),
        clamp(width),
        clamp(height),
    )


def convert_annotation(parts, new_class_id):
    """
    Handles both:

    Detection:
    class x y w h

    Segmentation:
    class x1 y1 x2 y2 x3 y3 ...
    """

    values = parts[1:]

    # Normal YOLO detection box
    if len(values) == 4:
        try:
            x, y, w, h = [float(v) for v in values]
        except ValueError:
            return None

        x = clamp(x)
        y = clamp(y)
        w = clamp(w)
        h = clamp(h)

        if w <= 0 or h <= 0:
            return None

        return (
            f"{new_class_id} "
            f"{x:.6f} "
            f"{y:.6f} "
            f"{w:.6f} "
            f"{h:.6f}"
        )

    # Polygon / segmentation
    box = polygon_to_box(values)

    if box is None:
        return None

    x, y, w, h = box

    return (
        f"{new_class_id} "
        f"{x:.6f} "
        f"{y:.6f} "
        f"{w:.6f} "
        f"{h:.6f}"
    )


def remap_annotations(
    annotations,
    class_map,
    excluded_classes,
):
    # If an explicitly unwanted disease exists,
    # skip the whole image.
    for parts in annotations:
        try:
            old_class_id = int(float(parts[0]))
        except ValueError:
            continue

        if old_class_id in excluded_classes:
            return [], True, 0

    converted_lines = []
    polygon_conversions = 0

    for parts in annotations:
        try:
            old_class_id = int(float(parts[0]))
        except ValueError:
            continue

        if old_class_id not in class_map:
            continue

        new_class_id = class_map[old_class_id]

        # More than 5 total tokens means polygon.
        if len(parts) > 5:
            polygon_conversions += 1

        converted = convert_annotation(
            parts,
            new_class_id,
        )

        if converted is not None:
            converted_lines.append(converted)

    return (
        converted_lines,
        False,
        polygon_conversions,
    )


def process_split(
    source_root,
    source_split,
    target_split,
    class_map,
    excluded_classes,
    filename_prefix,
):
    source_images = source_root / source_split / "images"
    source_labels = source_root / source_split / "labels"

    target_images = TARGET_DIR / target_split / "images"
    target_labels = TARGET_DIR / target_split / "labels"

    target_images.mkdir(parents=True, exist_ok=True)
    target_labels.mkdir(parents=True, exist_ok=True)

    class_images = {
        0: 0,
        1: 0,
        2: 0,
        3: 0,
    }

    annotations_count = {
        0: 0,
        1: 0,
        2: 0,
        3: 0,
    }

    copied_images = 0
    skipped_excluded = 0
    skipped_empty = 0
    polygon_conversions = 0

    if not source_images.exists():
        raise FileNotFoundError(
            f"Missing images folder:\n{source_images}"
        )

    for image_path in sorted(source_images.iterdir()):

        if not image_path.is_file():
            continue

        if image_path.suffix.lower() not in IMAGE_EXTENSIONS:
            continue

        label_path = source_labels / f"{image_path.stem}.txt"

        annotations = read_label_file(label_path)

        if not annotations:
            skipped_empty += 1
            continue

        (
            converted_lines,
            should_skip,
            converted_polygons,
        ) = remap_annotations(
            annotations,
            class_map,
            excluded_classes,
        )

        polygon_conversions += converted_polygons

        if should_skip:
            skipped_excluded += 1
            continue

        if not converted_lines:
            skipped_empty += 1
            continue

        new_stem = f"{filename_prefix}_{image_path.stem}"

        new_image_path = (
            target_images /
            f"{new_stem}{image_path.suffix.lower()}"
        )

        new_label_path = (
            target_labels /
            f"{new_stem}.txt"
        )

        shutil.copy2(
            image_path,
            new_image_path,
        )

        with new_label_path.open(
            "w",
            encoding="utf-8",
        ) as file:
            file.write("\n".join(converted_lines))
            file.write("\n")

        copied_images += 1

        classes_in_image = set()

        for line in converted_lines:
            class_id = int(line.split()[0])

            annotations_count[class_id] += 1
            classes_in_image.add(class_id)

        for class_id in classes_in_image:
            class_images[class_id] += 1

    return {
        "images": copied_images,
        "excluded": skipped_excluded,
        "empty": skipped_empty,
        "polygon_conversions": polygon_conversions,
        "class_images": class_images,
        "annotations": annotations_count,
    }


def merge_results(*results):
    merged = {
        "images": 0,
        "excluded": 0,
        "empty": 0,
        "polygon_conversions": 0,

        "class_images": {
            0: 0,
            1: 0,
            2: 0,
            3: 0,
        },

        "annotations": {
            0: 0,
            1: 0,
            2: 0,
            3: 0,
        },
    }

    for result in results:

        merged["images"] += result["images"]
        merged["excluded"] += result["excluded"]
        merged["empty"] += result["empty"]

        merged["polygon_conversions"] += (
            result["polygon_conversions"]
        )

        for class_id in FINAL_CLASSES:

            merged["class_images"][class_id] += (
                result["class_images"][class_id]
            )

            merged["annotations"][class_id] += (
                result["annotations"][class_id]
            )

    return merged


def create_data_yaml():
    yaml_content = """path: C:/Capstone/GreenGuard_AI_Model/dataset

train: train/images
val: val/images
test: test/images

nc: 4

names:
  0: Healthy
  1: Downy_Mildew
  2: Powdery_Mildew
  3: Septoria_Blight
"""

    (TARGET_DIR / "data.yaml").write_text(
        yaml_content,
        encoding="utf-8",
    )


def verify_label_format():
    """
    Every final label line MUST have exactly:
    class x y w h
    """

    print()
    print("=" * 70)
    print("VERIFYING LABEL FORMAT")
    print("=" * 70)

    invalid_lines = 0

    for split in ["train", "val", "test"]:

        labels_dir = TARGET_DIR / split / "labels"

        split_invalid = 0

        for label_path in labels_dir.glob("*.txt"):

            with label_path.open(
                "r",
                encoding="utf-8",
            ) as file:

                for line in file:

                    parts = line.strip().split()

                    if not parts:
                        continue

                    if len(parts) != 5:
                        split_invalid += 1
                        invalid_lines += 1

        print(
            f"{split.upper()}: "
            f"Invalid label lines = {split_invalid}"
        )

    if invalid_lines == 0:
        print()
        print("LABEL FORMAT: CLEAN")
        print("All labels are YOLO detection boxes.")
    else:
        print()
        print("WARNING:")
        print(f"{invalid_lines} invalid label lines found.")

    return invalid_lines


def verify_dataset():
    print()
    print("=" * 70)
    print("VERIFYING DATASET")
    print("=" * 70)

    for split in ["train", "val", "test"]:

        images_dir = TARGET_DIR / split / "images"
        labels_dir = TARGET_DIR / split / "labels"

        image_count = len([
            path
            for path in images_dir.iterdir()
            if (
                path.is_file()
                and path.suffix.lower() in IMAGE_EXTENSIONS
            )
        ])

        label_count = len(
            list(labels_dir.glob("*.txt"))
        )

        print()
        print(split.upper())
        print(f"Images: {image_count}")
        print(f"Labels: {label_count}")

        if image_count == label_count:
            print("Status: OK")
        else:
            print("Status: ERROR")


def main():
    print()
    print("=" * 70)
    print("GREENGUARD CLEAN DETECTION DATASET BUILDER")
    print("=" * 70)

    for directory in [
        RAW_DISEASE_DIR,
        HEALTHY_DIR_1,
        HEALTHY_DIR_2,
    ]:
        if not directory.exists():
            raise FileNotFoundError(
                f"Missing dataset folder:\n{directory}"
            )

    backup_existing_dataset()

    TARGET_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    splits = [
        ("train", "train"),
        ("valid", "val"),
        ("test", "test"),
    ]

    final_results = {}

    for source_split, target_split in splits:

        print()
        print("=" * 70)
        print(f"BUILDING {target_split.upper()}")
        print("=" * 70)

        healthy1 = process_split(
            HEALTHY_DIR_1,
            source_split,
            target_split,
            HEALTHY_1_CLASS_MAP,
            HEALTHY_1_EXCLUDED_CLASSES,
            "healthy1",
        )

        healthy2 = process_split(
            HEALTHY_DIR_2,
            source_split,
            target_split,
            HEALTHY_2_CLASS_MAP,
            HEALTHY_2_EXCLUDED_CLASSES,
            "healthy2",
        )

        disease = process_split(
            RAW_DISEASE_DIR,
            source_split,
            target_split,
            DISEASE_CLASS_MAP,
            DISEASE_EXCLUDED_CLASSES,
            "disease",
        )

        combined = merge_results(
            healthy1,
            healthy2,
            disease,
        )

        final_results[target_split] = combined

        print()
        print(f"TOTAL IMAGES: {combined['images']}")
        print(
            "POLYGONS CONVERTED TO BOXES: "
            f"{combined['polygon_conversions']}"
        )

        for class_id, class_name in FINAL_CLASSES.items():

            print(
                f"{class_id} {class_name}: "
                f"{combined['class_images'][class_id]} images | "
                f"{combined['annotations'][class_id]} annotations"
            )

    create_data_yaml()

    verify_dataset()

    invalid = verify_label_format()

    print()
    print("=" * 70)
    print("FINAL RESULT")
    print("=" * 70)

    for split in ["train", "val", "test"]:

        result = final_results[split]

        print()
        print(split.upper())

        for class_id, class_name in FINAL_CLASSES.items():

            print(
                f"{class_name}: "
                f"{result['class_images'][class_id]} images | "
                f"{result['annotations'][class_id]} annotations"
            )

    print()

    if invalid == 0:
        print("READY FOR TRAINING.")
    else:
        print("DO NOT TRAIN YET.")


if __name__ == "__main__":
    main()