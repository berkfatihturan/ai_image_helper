import platform
import json
import random
import sys

def main():
    try:
        import uiautomation as auto
    except ImportError:
        with open("C:\\Temp\\psexec_error.log", "w", encoding="utf-8") as f:
            f.write("Hata: 'uiautomation' kütüphanesi bulunamadı. Lütfen yüklemek için hedef sistemde şu komutu çalıştırın: pip install uiautomation")
        sys.exit(1)

    auto.SetGlobalSearchTimeout(2.0)
    root_window = auto.GetRootControl()

    if not root_window or not root_window.Exists(0, 0):
        with open("C:\\Temp\\ui_output_all.json", "w", encoding="utf-8") as f:
            json.dump([], f, ensure_ascii=False)
        sys.exit(0)

    top_level_windows = root_window.GetChildren()
    
    current_z_index = 0
    total_elements_found = 0
    MAX_ELEMENTS = 10000
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
            
            if total_elements_found > MAX_ELEMENTS: 
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
                "ButtonControl", "EditControl", "HyperlinkControl", 
                "MenuItemControl", "TextControl", "CheckBoxControl",
                "ComboBoxControl", "ListItemControl", "TabItemControl", "DocumentControl",
                "ImageControl", "PaneControl", "TreeItemControl", "DataItemControl",
                "CustomControl", "GroupControl", "SplitButtonControl", "SplitPaneControl",
                "SplitterControl", "StatusBarControl", "TabControl", "TableControl",
                "TextBlockControl", "TitleBarControl", "WindowControl"
            ]

            if (name and name.strip()) or is_meaningful_type:
                
                center_x = rect.left + (width // 2)
                center_y = rect.top + (height // 2)
                
                element_data = {
                    "tip": control_type.replace("Control", ""),
                    "isim": name.strip() if name else "",
                    "koordinat": {
                        "x": rect.left,
                        "y": rect.top,
                        "genislik": width,
                        "yukseklik": height
                    },
                    "merkez_koordinat": {
                        "x": center_x,
                        "y": center_y
                    }
                }

                windows_dict_all[parent_name]["elemanlar"].append(element_data)
                total_elements_found += 1
            
        current_z_index += 1
        
        if total_elements_found > MAX_ELEMENTS:
            break

    grouped_ui_all = []
    for pencere_adi, data in windows_dict_all.items():
        grouped_ui_all.append({
            "pencere": pencere_adi,
            "z_index": data["z_index"],
            "renk": data["color"],
            "kutu": data["rect"],
            "elmanlar": data["elemanlar"]
        })

    with open("C:\\Temp\\ui_output_all.json", "w", encoding="utf-8") as f:
        json.dump(grouped_ui_all, f, ensure_ascii=False)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        with open("C:\\Temp\\psexec_error.log", "w", encoding="utf-8") as f:
            f.write(str(e) + "\n" + traceback.format_exc())
