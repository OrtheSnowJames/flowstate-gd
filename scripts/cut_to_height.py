import os
import argparse
from PIL import Image

def crop_image_to_square(input_path, anchor="tl", output_path=None):
    if not os.path.exists(input_path):
        print(f"Error: The input file '{input_path}' could not be found.")
        return

    try:
        with Image.open(input_path) as img:
            width, height = img.size
            print(f"Original Dimensions: {width}px wide x {height}px high")

            # Determine the square dimension based on the shortest side
            square_dim = min(width, height)

            # Calculate coordinates based on the selected anchor corner
            if anchor == "tl":      # Top-Left
                left = 0
                top = 0
            elif anchor == "tr":    # Top-Right
                left = width - square_dim
                top = 0
            elif anchor == "bl":    # Bottom-Left
                left = 0
                top = height - square_dim
            elif anchor == "br":    # Bottom-Right
                left = width - square_dim
                top = height - square_dim
            elif anchor == "center": # Center fallback
                left = (width - square_dim) // 2
                top = (height - square_dim) // 2
            else:
                print(f"Invalid anchor '{anchor}'. Defaulting to top-left (tl).")
                left = 0
                top = 0

            right = left + square_dim
            bottom = top + square_dim

            cropped_img = img.crop((left, top, right, bottom))

            if not output_path:
                base_dir, file_name = os.path.split(input_path)
                name, extension = os.path.splitext(file_name)
                output_path = os.path.join(base_dir, f"{name}_{anchor}_square{extension}")

            cropped_img.save(output_path)
            print(f"Success! Square image saved to: {output_path}")
            print(f"New Dimensions: {square_dim}px x {square_dim}px")

    except Exception as error:
        print(f"An unexpected error occurred while cropping the image: {error}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Crop an image into a square anchored from a chosen corner or the center."
    )
    parser.add_argument(
        "image_path",
        type=str,
        help="Path to the input image file."
    )
    parser.add_argument(
        "-a", "--anchor",
        type=str,
        choices=["tl", "tr", "bl", "br", "center"],
        default="tl",
        help="Anchor position for the crop: tl (top-left), tr (top-right), bl (bottom-left), br (bottom-right), center. Default is tl."
    )
    parser.add_argument(
        "-o", "--output",
        type=str,
        default=None,
        help="Optional custom output path/filename."
    )

    args = parser.parse_args()
    crop_image_to_square(args.image_path, args.anchor, args.output)
