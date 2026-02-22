import platform
import json
import random

from src.core.config import settings

def get_os_type():
    """Mevcut işletim sistemini döndürür."""
    return platform.system()

def extract_windows_ui():
    """Windows üzerinde uiautomation kütüphanesi ile UI öğelerini çeker."""
    try:
        import uiautomation as auto
    except ImportError:
        raise ImportError("Hata: 'uiautomation' kütüphanesi bulunamadı. Lütfen yüklemek için şu komutu çalıştırın: pip install uiautomation")

    print("Tüm ekran taranıyor...")

    # Tüm ekranı (Masaüstü/Root) temsil eden ana objeyi al
    root_window = auto.GetRootControl()

    # Eğer kök pencere bulunamazsa uyar ve çık (Çok nadir)
    if not root_window or not root_window.Exists(0, 0):
        print("Ekran kök düğümü bulunamadı.")
        return None, None

    # Root nesnesinin doğrudan çocuklarını (Ana pencereleri Z-Order'a göre, üstten alta) alalım
    top_level_windows = root_window.GetChildren()
    
    # Z-index'e göre sırayla pencereleri (ve altındaki her şeyi) tarayalım
    # Z-index 0 = En üstteki pencere (Foreground)
    current_z_index = 0
    total_elements_found = 0
    windows_dict_all = {}
    
    for window in top_level_windows:
        parent_name = window.Name if window.Name else "Bilinmeyen Pencere"
        
        # Sadece görünür ve minimize olmamış pencerelere girelim
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
             
        # Renk ve pencere genel çerçevesi
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
            
            if total_elements_found > settings.MAX_ELEMENTS_TO_PARSE: 
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
        
        if total_elements_found > settings.MAX_ELEMENTS_TO_PARSE:
            break

    # TÜM ELEMANLARI (ALL) Formatla
    grouped_ui_all = []
    for pencere_adi, data in windows_dict_all.items():
        grouped_ui_all.append({
            "pencere": pencere_adi,
            "z_index": data["z_index"],
            "renk": data["color"],
            "kutu": data["rect"],
            "elmanlar": data["elemanlar"]
        })

    # --- SADECE GÖRÜNEN ELEMANLARI AYIKLAMA (MAP-REDUCE COLLISION) ---
    flat_elements_all = []
    for group in grouped_ui_all:
        z = group["z_index"]
        p_name = group["pencere"]
        c = group["renk"]
        p_kutu = group["kutu"]
        
        for el in group["elmanlar"]:
            ex = el["koordinat"]["x"]
            ey = el["koordinat"]["y"]
            ew = el["koordinat"]["genislik"]
            eh = el["koordinat"]["yukseklik"]
            
            flat_elements_all.append({
                "z_index": z,
                "pencere": p_name,
                "renk": c,
                "p_kutu": p_kutu,
                "el_data": el,
                "rect": [ex, ey, ex + ew, ey + eh],
                "center": [el["merkez_koordinat"]["x"], el["merkez_koordinat"]["y"]]
            })
            
    # Sadece Görünenleri Tutacağımız Yeni Sözlük
    visible_logic_dict = {}
    
    for current_item in flat_elements_all:
        c_z = current_item["z_index"]
        cx, cy = current_item["center"]
        
        is_occluded = False
        
        # Bu elementten DAHA ÜSTTE (Z-indexi daha KÜÇÜK olan) öğelere bakalım
        for top_item in flat_elements_all:
            if top_item["z_index"] < c_z:
                tx1, ty1, tx2, ty2 = top_item["rect"]
                
                # Eğer alttaki elemanın MERKEZİ, üstteki herhangi bir elemanın 
                # kutusunun (bounding box) içinde kalıyorsa, gizlenmiş diyoruz.
                if tx1 <= cx <= tx2 and ty1 <= cy <= ty2:
                    is_occluded = True
                    break
                    
        if not is_occluded:
            p_name = current_item["pencere"]
            if p_name not in visible_logic_dict:
                visible_logic_dict[p_name] = {
                    "color": current_item["renk"],
                    "rect": current_item["p_kutu"],
                    "z_index": current_item["z_index"],
                    "elemanlar": []
                }
            visible_logic_dict[p_name]["elemanlar"].append(current_item["el_data"])

    # GÖRÜNEN ELEMANLARI (VISIBLE) Formatla
    grouped_ui_visible = []
    for pencere_adi, data in visible_logic_dict.items():
        grouped_ui_visible.append({
            "pencere": pencere_adi,
            "z_index": data["z_index"],
            "renk": data["color"],
            "kutu": data["rect"],
            "elmanlar": data["elemanlar"]
        })

    if len(grouped_ui_all) == 0:
        print("\n[UYARI] Ekranda hiçbir UI elementi bulunamadı.")
        
    return grouped_ui_all, grouped_ui_visible
