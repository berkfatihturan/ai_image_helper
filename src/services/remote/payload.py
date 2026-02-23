import sys
import json
import random

def get_bounding_rect(rect):
    return {
        "x": rect.left,
        "y": rect.top,
        "genislik": rect.right - rect.left,
        "yukseklik": rect.bottom - rect.top
    }

def main():
    try:
        import uiautomation as auto
    except ImportError:
        with open("C:\\Temp\\psexec_error.log", "w", encoding="utf-8") as f:
            f.write("Hata: uiautomation kütüphanesi bulunamadı. Lütfen hedef makinede 'pip install uiautomation' komutunu çalıştırın.")
        sys.exit(1)

    auto.SetGlobalSearchTimeout(2.0)
    root = auto.GetRootControl()
    
    if not root or not root.Exists(0, 0):
        sys.exit(0)

    all_elements_output = []
    
    # Masaüstünü (Desktop) ekleyelim (z_index=99990)
    desktop_rect = root.BoundingRectangle
    desktop_data = {
        "pencere": "Windows Desktop",
        "z_index": 99990,
        "renk": [random.randint(50, 250), random.randint(50, 250), random.randint(50, 250)],
        "kutu": [desktop_rect.left, desktop_rect.top, desktop_rect.right, desktop_rect.bottom],
        "elmanlar": []
    }
    
    # Root altındaki pencereleri tarayalım
    current_z_index = 10
    top_level_windows = root.GetChildren()
    
    valid_panes = ["Shell_TrayWnd", "Progman", "WorkerW"]
    
    for window in top_level_windows:
        try:
            if window.IsOffscreen:
                continue
                
            class_name = window.ClassName
            c_type = window.ControlTypeName
            
            if class_name in ["Progman", "WorkerW"]:
                # Pencereler taramasına girme, masaüstünü yukarıda hallettik veya içine eleman atacağız
                pass
            
            if c_type == "PaneControl":
                if class_name not in valid_panes:
                    continue
            elif c_type != "WindowControl" and class_name not in valid_panes:
                continue
                
            w_rect = window.BoundingRectangle
            if w_rect.right <= w_rect.left or w_rect.bottom <= w_rect.top:
                continue
                
            is_taskbar = (class_name == "Shell_TrayWnd")
            is_desktop = (class_name in ["Progman", "WorkerW"])
            
            p_name = window.Name if window.Name else ""
            if not p_name:
                p_name = "Windows Taskbar" if is_taskbar else ("Windows Desktop" if is_desktop else "Bilinmeyen Pencere")
                
            my_z_index = 1 if is_taskbar else current_z_index
            if is_desktop:
                my_z_index = 99990
            
            # Desktop ise var olan desktop_data içerisine ekleyeceğiz
            target_group = desktop_data if is_desktop else {
                "pencere": p_name,
                "z_index": my_z_index,
                "renk": [random.randint(50, 250), random.randint(50, 250), random.randint(50, 250)],
                "kutu": [w_rect.left, w_rect.top, w_rect.right, w_rect.bottom],
                "elmanlar": []
            }
            
            # DFS Taraması
            queue = [window]
            element_count = 0
            while queue:
                if element_count >= 5000:
                    break
                control = queue.pop(0)
                
                try:
                    children = control.GetChildren()
                    if children:
                        queue.extend(children)
                except Exception:
                    pass
                    
                try:
                    c_rect = control.BoundingRectangle
                    w = c_rect.right - c_rect.left
                    h = c_rect.bottom - c_rect.top
                    
                    if w <= 0 or h <= 0:
                        continue
                    
                    node_type = control.ControlTypeName.replace("Control", "")
                    c_name = control.Name.strip() if control.Name else ""
                    
                    # Saydam, isimsiz arkaplanları boşverelim
                    if not c_name and node_type in ["Pane", "Group", "Custom", "List"]:
                        continue
                        
                    center_x = c_rect.left + (w // 2)
                    center_y = c_rect.top + (h // 2)
                    
                    el_data = {
                        "tip": node_type,
                        "isim": c_name,
                        "koordinat": {"x": c_rect.left, "y": c_rect.top, "genislik": w, "yukseklik": h},
                        "merkez_koordinat": {"x": center_x, "y": center_y}
                    }
                    target_group["elmanlar"].append(el_data)
                    element_count += 1
                except Exception:
                    pass
            
            if not is_desktop:
                all_elements_output.append(target_group)
                if not is_taskbar:
                    current_z_index += 10
                    
        except Exception:
            pass

    all_elements_output.append(desktop_data)
    
    with open("C:\\Temp\\ui_output_all.json", "w", encoding="utf-8") as f:
        json.dump(all_elements_output, f, ensure_ascii=False)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        with open("C:\\Temp\\psexec_error.log", "w", encoding="utf-8") as f:
            f.write(str(e) + "\n" + traceback.format_exc())
