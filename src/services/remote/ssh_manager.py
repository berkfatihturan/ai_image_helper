import paramiko
import os
import time

class RemoteExtractor:
    def __init__(self, host: str, user: str, password: str, port: int = 22):
        self.host = host
        self.user = user
        self.password = password
        self.port = port
        self.ssh = paramiko.SSHClient()
        self.ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        
    def connect(self):
        self.ssh.connect(
            hostname=self.host,
            port=self.port,
            username=self.user,
            password=self.password,
            timeout=10
        )
        
    def get_active_session_id(self) -> str:
        """Hedefteki aktif masaüstü kullanıcısının Session ID'sini bulur."""
        stdin, stdout, stderr = self.ssh.exec_command("query session")
        output = stdout.read().decode('utf-8', errors='ignore')
        
        # 'query session' ciktisinda bizim aradigimiz sey 'Active' olan Session'dir. 
        # Cogu zaman '>services' 0 ID'siyle veya ssh terminali '> ' isaretiyle gozukur. Bizim isimizi Active console gorur.
        # Ornek satir: " console           koyun                     1  Active"
        
        # 1. Onceligimiz 'Active' state'ine sahip bir satir bulmak.
        for line in output.split('\n'):
            if 'Active' in line:
                parts = line.split()
                # Parts genelde: ['console', 'koyun', '1', 'Active'] seklindedir
                if len(parts) >= 3:
                    # Index hatasindan kacinmak icin sayiya benzeyen kismi bulalim (1, 2, 3 vb.)
                    for part in parts:
                        if part.isdigit():
                            return part
                            
        # 2. Eger Active olan yoksa (ekran kilitli vs) fallback olarak 1 dondur
        return "1"

    def execute_remote_extraction(self) -> dict:
        """SFTP ile PowerShell payload yukler, PsExec ile tetikler, JSONlari geri ceker."""
        payload_local_path = os.path.join(os.path.dirname(__file__), "payload.ps1")
        temp_dir = "C:\\Temp"
        payload_remote_path = f"{temp_dir}\\ui_scanner.ps1"
        
        try:
            self.connect()
            sftp = self.ssh.open_sftp()
            
            # Uzak tarafta Temp klasoru yoksa olustur
            self.ssh.exec_command(f"mkdir {temp_dir}")
            
            # Payload scriptini hedef Windows makineye (C:\Temp\) yolla
            print(f"[{self.host}] PowerShell Payload gonderiliyor...")
            sftp.put(payload_local_path, payload_remote_path)
            
            # Aktif UI Session ID'sini ogren (Genelde 1 veya 2)
            session_id = self.get_active_session_id()
            print(f"[{self.host}] Hedef Desktop Session ID: {session_id}")
            
            # PsExec ile Sesson 0'dan kurtulup hedef kullanicinin ekranina scripti at
            psexec_cmd = f'cmd.exe /c "set PATH=C:\\PSTools;%PATH% && psexec -i {session_id} -accepteula powershell.exe -STA -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File {payload_remote_path} {temp_dir}"'
            print(f"[{self.host}] PsExec PowerShell Enjeksiyon komutu atiliyor...")
            
            # Asenkron tetikledigimiz icin scriptin bitmesini (dosyalarin uretilmesini) bekle
            # Normal sartlarda bu 5-10 saniye surer. Ekrani kilitliyse psexec asili kalabilir, timeout koyalim.
            stdin, stdout, stderr = self.ssh.exec_command(psexec_cmd, timeout=25)
            
            # Psexec ciktilarini yakala
            psexec_err = stderr.read().decode('utf-8', errors='ignore')
            print(f"[{self.host}] PsExec Calistirma Tamamlandi.")
            
            # Sonuclari topla (SFTP ile Local'e Geri Al)
            json_all_remote = f"{temp_dir}\\ui_output_all.json"
            
            import json
            
            # Sadece "ALL" (Tum pencere agaci) datasini oku
            try:
                with sftp.file(json_all_remote, "rb") as f:
                    raw_bytes = f.read()
                    json_str = raw_bytes.decode('utf-8-sig') # Windows BOM karakterini temizler
                    all_data = json.loads(json_str)
                    
                    # PowerShell ConvertTo-Json eger array icinde tek bir pencere bulursa onu Dict olarak cevirir.
                    # Pydantic (FastAPI) List bekledigi icin onu listeye zorlayalim.
                    if isinstance(all_data, dict):
                        all_data = [all_data]
            except (FileNotFoundError, json.JSONDecodeError) as parse_error:
                 # Eger JSON okunamiyorsa, PowerShell icinde bir exception patlamis ve psexec_error.log yazilmistir
                 err_log_remote = f"{temp_dir}\\psexec_error.log"
                 powershell_error = "Log Bulunamadi"
                 try:
                     with sftp.file(err_log_remote, "rb") as f:
                         powershell_error = f.read().decode('utf-8-sig', errors='ignore')
                     sftp.remove(err_log_remote)
                 except:
                     pass

                 return {
                     "status": "error", 
                     "message": f"PowerShell UI taramasi sirasinda coktu.\n\n--- JSON PARSE HATASI ---\n{str(parse_error)}\n\n--- POWERSHELL EXCEPTION ---\n{powershell_error}\n\n--- PSEXEC STDERR ---\n{psexec_err}"
                 }

            # İzi kaybettirme (Gizlilik Cleanup)
            sftp.remove(payload_remote_path)
            sftp.remove(json_all_remote)
            
            sftp.close()
            self.ssh.close()
            
            # --- MAP REDUCE OCCLUSION (GORUNENLERI AYIKLAMA) SERVER SIDE ---
            # Python uzerinde calistigi icin cok spesifik ve hizlidir. Remote'u yormaz.
            flat_elements_all = []
            for group_raw in all_data:
                # PowerShell bazen Array icerisindeki hashtable'lari string (JSON) olarak dondurebiliyor
                if isinstance(group_raw, str):
                    if not group_raw.strip():
                        continue
                    try:
                        group = json.loads(group_raw)
                    except json.JSONDecodeError:
                        continue
                else:
                    group = group_raw
                
                z = group.get("z_index", 0)
                p_name = group.get("pencere", "")
                c = group.get("renk", [0,0,0])
                p_kutu = group.get("kutu", [0,0,0,0])
                for el in group.get("elmanlar", []):
                    try:
                        ex, ey = el["koordinat"]["x"], el["koordinat"]["y"]
                        ew, eh = el["koordinat"]["genislik"], el["koordinat"]["yukseklik"]
                        cx, cy = el["merkez_koordinat"]["x"], el["merkez_koordinat"]["y"]
                        
                        flat_elements_all.append({
                            "z_index": z, "pencere": p_name, "renk": c, "p_kutu": p_kutu,
                            "el_data": el, "rect": [ex, ey, ex + ew, ey + eh], "center": [cx, cy]
                        })
                    except KeyError:
                        continue
                        
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

            visible_data = []
            for pencere_adi, data in visible_logic_dict.items():
                visible_data.append({
                    "pencere": pencere_adi, "z_index": data["z_index"], "renk": data["color"],
                    "kutu": data["rect"], "elmanlar": data["elemanlar"]
                })
            
            return {
                "status": "success",
                "visible_elements": visible_data,
                "all_elements": all_data
            }
            
        except Exception as e:
            if self.ssh:
                 self.ssh.close()
            raise Exception(f"Uzak Baglanti Hatasi: {str(e)}")
