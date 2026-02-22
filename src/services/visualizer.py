import sys
try:
    from PIL import Image, ImageDraw, ImageFont, ImageGrab
except ImportError:
    print("Pillow kütüphanesi yok. Görüntü oluşturulamadı. 'pip install Pillow' çalıştırın.")

def draw_ui_map(grouped_ui: list, output_path: str = "ui_map_visual.png"):
    """
    Kesişimlerden temizlenmiş, görünür (visible_elements) listesini alır 
    ve ekran görüntüsü üzerine renkli semboller/çerçeveler olarak çizer.
    """
    if "PIL" not in sys.modules:
        print("Pillow kurulu değil, görsel servis çalıştırılamıyor.")
        return False
        
    print("Ekran görüntüsü alınıyor ve harita çiziliyor...")
    
    try:
         # Tüm ekranı kapsayan bir screenshot al (Arkaplan)
         img = ImageGrab.grab()
    except Exception:
         # Çalışmazsa boş siyah bir tuval yarat
         import ctypes
         user32 = ctypes.windll.user32
         w, h = user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)
         img = Image.new('RGB', (w, h), color=(30, 30, 30))

    draw = ImageDraw.Draw(img, "RGBA")
    
    # Varsayılan bir font yüklemeyi dene, bulamazsa default kullan
    try:
        font = ImageFont.truetype("arial.ttf", 12)
        title_font = ImageFont.truetype("arialbd.ttf", 20)
    except:
        font = ImageFont.load_default()
        title_font = ImageFont.load_default()

    for group in grouped_ui:
        p_name = group["pencere"]
        p_color = group["renk"]
        p_rect = group["kutu"]
        
        # Eğer renk listeyse Tuple'a çevirelim (JSON'dan gelirken list olabilir)
        if isinstance(p_color, list):
            p_color = tuple(p_color)
            
        # Pencere alanını yarı saydam bir filtre ve sınır ile çiz
        overlay_color = p_color + (40,) # (R,G,B, Alpha)
        border_color = p_color + (255,)
        
        draw.rectangle([p_rect[0], p_rect[1], p_rect[2], p_rect[3]], fill=overlay_color, outline=border_color, width=3)
        draw.text((p_rect[0] + 5, p_rect[1] + 5), str(p_name), fill=(255, 255, 255), font=title_font)
        
        for el in group["elmanlar"]:
            ex = el["koordinat"]["x"]
            ey = el["koordinat"]["y"]
            ew = el["koordinat"]["genislik"]
            eh = el["koordinat"]["yukseklik"]
            
            # Elementin tipine göre farklı şekiller çiz
            shape_color = p_color + (200,)
            center_x = ex + ew // 2
            center_y = ey + eh // 2

            ek = 4 # Sembol boyutu
            
            if el["tip"] == "Button":
                # Yıldız/Daire
                draw.ellipse([center_x-ek-2, center_y-ek-2, center_x+ek+2, center_y+ek+2], fill=shape_color, outline="white")
            elif el["tip"] == "Pane":
                # Kare
                draw.rectangle([ex, ey, ex+ew, ey+eh], outline=shape_color, width=2)
            elif el["tip"] == "Text":
                # Sadece küçük bir nokta + çizgi
                draw.line((ex, ey+eh, ex+ew, ey+eh), fill=shape_color, width=2)
            else:
                # Geriye kalan tüüüm elementler için tam merkeze keskin bir '+' (artı) işareti koy
                draw.line((center_x - ek, center_y, center_x + ek, center_y), fill=shape_color, width=2)
                draw.line((center_x, center_y - ek, center_x, center_y + ek), fill=shape_color, width=2)

            # İsim varsa minik bir text kutusu koy
            if el["isim"]:
                 draw.text((center_x + 6, center_y - 6), str(el["isim"])[:15], fill=(255, 255, 255), font=font)

    # Resmi ayarlar tabanlı yere kaydet
    try:
        img.save(output_path)
        print(f"Harita '{output_path}' olarak başarıyla kaydedildi!")
        return True
    except Exception as e:
        print(f"Harita kaydedilirken hata: {str(e)}")
        return False
