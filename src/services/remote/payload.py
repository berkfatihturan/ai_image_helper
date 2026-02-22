import platform
import sys
import json
import random
import os

def extract_windows_ui():
    try:
        import uiautomation as auto
    except ImportError:
        print("Hata: 'uiautomation' kurulu degil.")
        sys.exit(1)

    root_window = auto.GetRootControl()
    if not root_window or not root_window.Exists(0, 0):
        return None, None

    top_level_windows = root_window.GetChildren()
    current_z_index = 0
    total_elements_found = 0
    windows_dict_all = {}
    
    for window in top_level_windows:
        parent_name = window.Name if window.Name else "Bilinmeyen Pencere"
        try:
             if window.IsOffscreen:
                 continue
             if window.ControlTypeName == "WindowControl":
                 if window.CurrentWindowVisualState() == 2:
                     continue
             w_rect = window.BoundingRectangle
             w_left, w_top, w_right, w_bottom = w_rect.left, w_rect.top, w_rect.right, w_rect.bottom
             if w_right <= w_left or w_bottom <= w_top:
                 continue
        except Exception:
             pass 
             
        color = (random.randint(50, 250), random.randint(50, 250), random.randint(50, 250))
        try:
            p_border = (w_rect.left, w_rect.top, w_rect.right, w_rect.bottom)
        except NameError:
            p_border = (0, 0, 0, 0)
            
        if parent_name not in windows_dict_all:
            windows_dict_all[parent_name] = {
                "color": color,
                "rect": p_border,
                "z_index": current_z_index,
                "elemanlar": []
            }
            
        queue = [window]
        while queue:
            control = queue.pop(0)
            if total_elements_found > 4000: 
                break
            try:
                children = control.GetChildren()
                if children:
                    queue.extend(children)
            except Exception:
                pass
                
            try:
                control_type = control.ControlTypeName
                name = control.Name
                rect = control.BoundingRectangle
                width = rect.right - rect.left
                height = rect.bottom - rect.top
                if width <= 0 or height <= 0:
                    continue
            except Exception:
                continue

            is_meaningful_type = control_type in [
                "ButtonControl", "EditControl", "HyperlinkControl", "MenuItemControl", "TextControl", 
                "CheckBoxControl", "ComboBoxControl", "ListItemControl", "TabItemControl", "DocumentControl",
                "ImageControl", "PaneControl", "TreeItemControl", "DataItemControl", "CustomControl", 
                "GroupControl", "SplitButtonControl", "SplitPaneControl", "SplitterControl", 
                "StatusBarControl", "TabControl", "TableControl", "TextBlockControl", "TitleBarControl", "WindowControl"
            ]

            if (name and name.strip()) or is_meaningful_type:
                center_x = rect.left + (width // 2)
                center_y = rect.top + (height // 2)
                element_data = {
                    "tip": control_type.replace("Control", ""),
                    "isim": name.strip() if name else "",
                    "koordinat": {"x": rect.left, "y": rect.top, "genislik": width, "yukseklik": height},
                    "merkez_koordinat": {"x": center_x, "y": center_y}
                }
                windows_dict_all[parent_name]["elemanlar"].append(element_data)
                total_elements_found += 1
            
        current_z_index += 1
        if total_elements_found > 4000:
            break

    grouped_ui_all = []
    for pencere_adi, data in windows_dict_all.items():
        grouped_ui_all.append({
            "pencere": pencere_adi, "z_index": data["z_index"], "renk": data["color"],
            "kutu": data["rect"], "elmanlar": data["elemanlar"]
        })

    flat_elements_all = []
    for group in grouped_ui_all:
        z = group["z_index"]
        p_name = group["pencere"]
        c = group["renk"]
        p_kutu = group["kutu"]
        for el in group["elmanlar"]:
            ex, ey = el["koordinat"]["x"], el["koordinat"]["y"]
            ew, eh = el["koordinat"]["genislik"], el["koordinat"]["yukseklik"]
            flat_elements_all.append({
                "z_index": z, "pencere": p_name, "renk": c, "p_kutu": p_kutu,
                "el_data": el, "rect": [ex, ey, ex + ew, ey + eh],
                "center": [el["merkez_koordinat"]["x"], el["merkez_koordinat"]["y"]]
            })
            
    visible_logic_dict = {}
    for current_item in flat_elements_all:
        c_z = current_item["z_index"]
        cx, cy = current_item["center"]
        is_occluded = False
        for top_item in flat_elements_all:
            if top_item["z_index"] < c_z:
                tx1, ty1, tx2, ty2 = top_item["rect"]
                if tx1 <= cx <= tx2 and ty1 <= cy <= ty2:
                    is_occluded = True
                    break
                    
        if not is_occluded:
            p_name = current_item["pencere"]
            if p_name not in visible_logic_dict:
                visible_logic_dict[p_name] = {
                    "color": current_item["renk"], "rect": current_item["p_kutu"],
                    "z_index": current_item["z_index"], "elemanlar": []
                }
            visible_logic_dict[p_name]["elemanlar"].append(current_item["el_data"])

    grouped_ui_visible = []
    for pencere_adi, data in visible_logic_dict.items():
        grouped_ui_visible.append({
            "pencere": pencere_adi, "z_index": data["z_index"], "renk": data["color"],
            "kutu": data["rect"], "elmanlar": data["elemanlar"]
        })

    return grouped_ui_all, grouped_ui_visible

def draw_ui_map(grouped_ui, output_path):
    try:
        from PIL import Image, ImageDraw, ImageFont, ImageGrab
    except ImportError:
        return
    try:
         img = ImageGrab.grab()
    except Exception:
         import ctypes
         user32 = ctypes.windll.user32
         w, h = user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)
         img = Image.new('RGB', (w, h), color=(30, 30, 30))

    draw = ImageDraw.Draw(img, "RGBA")
    try:
        font = ImageFont.truetype("arial.ttf", 12)
        title_font = ImageFont.truetype("arialbd.ttf", 20)
    except:
        font = ImageFont.load_default()
        title_font = ImageFont.load_default()

    for group in grouped_ui:
        p_name = group["pencere"]
        p_color = tuple(group["renk"]) if isinstance(group["renk"], list) else group["renk"]
        p_rect = group["kutu"]
        
        overlay_color = p_color + (40,)
        border_color = p_color + (255,)
        draw.rectangle([p_rect[0], p_rect[1], p_rect[2], p_rect[3]], fill=overlay_color, outline=border_color, width=3)
        draw.text((p_rect[0] + 5, p_rect[1] + 5), p_name, fill=(255, 255, 255), font=title_font)
        
        for el in group["elmanlar"]:
            ex, ey = el["koordinat"]["x"], el["koordinat"]["y"]
            ew, eh = el["koordinat"]["genislik"], el["koordinat"]["yukseklik"]
            shape_color = p_color + (200,)
            center_x, center_y = ex + ew // 2, ey + eh // 2
            ek = 4 
            if el["tip"] == "Button":
                draw.ellipse([center_x-ek-2, center_y-ek-2, center_x+ek+2, center_y+ek+2], fill=shape_color, outline="white")
            elif el["tip"] == "Pane":
                draw.rectangle([ex, ey, ex+ew, ey+eh], outline=shape_color, width=2)
            elif el["tip"] == "Text":
                draw.line((ex, ey+eh, ex+ew, ey+eh), fill=shape_color, width=2)
            else:
                draw.line((center_x - ek, center_y, center_x + ek, center_y), fill=shape_color, width=2)
                draw.line((center_x, center_y - ek, center_x, center_y + ek), fill=shape_color, width=2)
            if el["isim"]:
                 draw.text((center_x + 6, center_y - 6), el["isim"][:15], fill=(255, 255, 255), font=font)

    img.save(output_path)

def main():
    import traceback
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "C:\\Temp"
    if not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)
        
    try:
        all_elements, visible_elements = extract_windows_ui()
        
        if visible_elements:
            draw_ui_map(visible_elements, os.path.join(out_dir, "ui_map_visual.png"))
        
        json_all = json.dumps(all_elements, ensure_ascii=False, indent=2)
        json_visible = json.dumps(visible_elements, ensure_ascii=False, indent=2)
        
        with open(os.path.join(out_dir, "ui_output_all.json"), "w", encoding="utf-8") as f:
            f.write(json_all)
        with open(os.path.join(out_dir, "ui_output_visible.json"), "w", encoding="utf-8") as f:
            f.write(json_visible)
            
        with open(os.path.join(out_dir, "psexec_success.log"), "w", encoding="utf-8") as f:
            f.write("OK")
    except Exception as e:
        with open(os.path.join(out_dir, "psexec_error.log"), "w", encoding="utf-8") as f:
            f.write(traceback.format_exc())

if __name__ == "__main__":
    main()
