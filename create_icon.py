#!/usr/bin/env python3
"""Create Investment Governance icon with $$ and checkmark"""

from PIL import Image, ImageDraw, ImageFont
import subprocess
from pathlib import Path
import shutil

def create_icon_image(size, text_main="$$", text_sub="✓", color_top=(34, 139, 34), color_bottom=(0, 100, 0)):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    margin = int(size * 0.08)
    rect_size = size - 2 * margin
    corner_radius = int(size * 0.18)
    
    for y in range(margin, margin + rect_size):
        ratio = (y - margin) / rect_size
        r = int(color_top[0] + (color_bottom[0] - color_top[0]) * ratio)
        g = int(color_top[1] + (color_bottom[1] - color_top[1]) * ratio)
        b = int(color_top[2] + (color_bottom[2] - color_top[2]) * ratio)
        draw.line([(margin, y), (margin + rect_size, y)], fill=(r, g, b, 255))
    
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(
        [margin, margin, margin + rect_size, margin + rect_size],
        radius=corner_radius,
        fill=255
    )
    
    result = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    result.paste(img, mask=mask)
    
    if size >= 64:
        draw = ImageDraw.Draw(result)
        
        main_font_size = int(size * 0.28)
        
        try:
            font_main = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", main_font_size)
        except:
            font_main = ImageFont.load_default()
        
        bbox_main = draw.textbbox((0, 0), text_main, font=font_main)
        main_width = bbox_main[2] - bbox_main[0]
        main_height = bbox_main[3] - bbox_main[1]
        
        box_size = int(size * 0.22)
        spacing = int(size * 0.06)
        total_width = box_size + spacing + main_width
        
        start_x = (size - total_width) // 2
        y_center = size // 2
        
        box_x = start_x
        box_y = y_center - box_size // 2
        draw.rounded_rectangle(
            [box_x, box_y, box_x + box_size, box_y + box_size],
            radius=int(size * 0.03),
            outline=(255, 255, 255, 255),
            width=max(2, int(size * 0.02))
        )
        
        check_margin = int(box_size * 0.2)
        x1 = box_x + check_margin
        y1 = box_y + box_size * 0.5
        x2 = box_x + box_size * 0.4
        y2 = box_y + box_size - check_margin
        x3 = box_x + box_size - check_margin
        y3 = box_y + check_margin
        line_width = max(2, int(size * 0.025))
        draw.line([(x1, y1), (x2, y2)], fill=(255, 255, 255, 255), width=line_width)
        draw.line([(x2, y2), (x3, y3)], fill=(255, 255, 255, 255), width=line_width)
        
        main_x = start_x + box_size + spacing
        main_y = y_center - main_height // 2 - int(size * 0.02)
        draw.text((main_x, main_y), text_main, fill=(255, 255, 255, 255), font=font_main)
    
    return result

def main():
    project_dir = Path("/Users/tlegrand/Documents/projects/Planned-Investment-Governance")
    resources_dir = project_dir / "Resources"
    iconset_dir = resources_dir / "AppIcon.iconset"
    
    resources_dir.mkdir(parents=True, exist_ok=True)
    if iconset_dir.exists():
        shutil.rmtree(iconset_dir)
    iconset_dir.mkdir(parents=True, exist_ok=True)
    
    sizes = {
        16: ["icon_16x16.png"],
        32: ["icon_16x16@2x.png", "icon_32x32.png"],
        64: ["icon_32x32@2x.png"],
        128: ["icon_128x128.png"],
        256: ["icon_128x128@2x.png", "icon_256x256.png"],
        512: ["icon_256x256@2x.png", "icon_512x512.png"],
        1024: ["icon_512x512@2x.png"]
    }
    
    for size, filenames in sizes.items():
        print(f"Creating {size}x{size} icon...")
        img = create_icon_image(size, "$$", "✓")
        for filename in filenames:
            img.save(iconset_dir / filename, "PNG")
    
    icns_path = resources_dir / "AppIcon.icns"
    print(f"Creating {icns_path}...")
    result = subprocess.run(
        ["iconutil", "-c", "icns", "-o", str(icns_path), str(iconset_dir)],
        capture_output=True, text=True
    )
    
    if result.returncode == 0:
        print(f"Successfully created: {icns_path}")
        shutil.rmtree(iconset_dir)
    else:
        print(f"Error: {result.stderr}")

if __name__ == "__main__":
    main()
