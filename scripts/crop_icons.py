from PIL import Image, ImageDraw
import os
import glob

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET_DIR = os.path.join(REPO_ROOT, "apps/macos/Odin/Sources/Odin/Assets.xcassets/AppIcon.appiconset")

print(f"Scanning for icon images in: {ICONSET_DIR}")
icon_files = glob.glob(os.path.join(ICONSET_DIR, "*.png"))

for filepath in icon_files:
    filename = os.path.basename(filepath)
    try:
        with Image.open(filepath) as img:
            W, H = img.size
            rgba_img = img.convert("RGBA")
            
            # 1. Get the original alpha mask (the squircle shape)
            alpha_mask = rgba_img.getchannel('A')
            
            # 2. Extract the exact background color of the squircle interior
            # Find the first pixel along the diagonal that is fully opaque
            pixels = rgba_img.load()
            bg_color = (17, 17, 17, 255) # Default dark charcoal fallback
            for i in range(min(W, H) // 4):
                p = pixels[i, i]
                if p[3] == 255:
                    bg_color = p
                    break
            
            # 3. Find bounding box of the white text (R > 200, G > 200, B > 200)
            text_mask = Image.new("L", (W, H), 0)
            text_mask_pixels = text_mask.load()
            
            for y in range(H):
                for x in range(W):
                    r, g, b, a = pixels[x, y]
                    if r > 200 and g > 200 and b > 200 and a > 50:
                        text_mask_pixels[x, y] = 255
            
            bbox = text_mask.getbbox()
            
            if bbox:
                # 4. Crop the text area
                left, upper, right, lower = bbox
                cropped_text = rgba_img.crop((left, upper, right, lower))
                
                # 5. Calculate scaling factor to make text fill 80% of the canvas
                text_w = right - left
                text_h = lower - upper
                
                target_w = int(W * 0.8)
                target_h = int(H * 0.8)
                
                scale = min(target_w / text_w, target_h / text_h)
                
                new_w = int(text_w * scale)
                new_h = int(text_h * scale)
                
                # Resize the cropped text
                resized_text = cropped_text.resize((new_w, new_h), Image.Resampling.LANCZOS)
                
                # 6. Create background filled with the matched background color & original squircle mask
                new_bg = Image.new("RGBA", (W, H), bg_color)
                new_bg.putalpha(alpha_mask)
                
                # 7. Paste the scaled text centered
                paste_x = (W - new_w) // 2
                paste_y = (H - new_h) // 2
                new_bg.alpha_composite(resized_text, (paste_x, paste_y))
                
                new_bg.save(filepath, "PNG")
                print(f"  Enlarged text in {filename} to {new_w}x{new_h} using background {bg_color}")
            else:
                print(f"  Skipped {filename} (no white text found)")
    except Exception as e:
        print(f"  Error processing {filename}: {e}")

print("Icon padding removal and text expansion complete!")
