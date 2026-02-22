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
        """SFTP ile payload yukler, PsExec ile tetikler, JSONlari geri ceker."""
        payload_local_path = os.path.join(os.path.dirname(__file__), "payload.py")
        temp_dir = "C:\\Temp"
        payload_remote_path = f"{temp_dir}\\ui_scanner.py"
        
        try:
            self.connect()
            sftp = self.ssh.open_sftp()
            
            # Uzak tarafta Temp klasoru yoksa olustur
            self.ssh.exec_command(f"mkdir {temp_dir}")
            
            # Payload scriptini hedef Windows makineye (C:\Temp\) yolla
            print(f"[{self.host}] Payload gonderiliyor...")
            sftp.put(payload_local_path, payload_remote_path)
            
            # Aktif UI Session ID'sini ogren (Genelde 1 veya 2)
            session_id = self.get_active_session_id()
            print(f"[{self.host}] Hedef Desktop Session ID: {session_id}")
            
            # Python'un hedeftesi mutlak (absolute) yolunu bulalim
            # Sadece 'python' yazarsak, psexec SYSTEM (-s) session'inda PATH'i bulamayip cokuyor
            stdin, stdout, stderr = self.ssh.exec_command("where python")
            python_paths = stdout.read().decode('utf-8').strip().split('\n')
            
            if not python_paths or 'Could not find' in python_paths[0] or python_paths[0].strip() == '':
                 return {"status": "error", "message": "Hedef makinede 'python' kurulu degil veya PATH'e eklenmemis."}
                 
            # Eger birden fazla varsa ilkini (en gecerli olani) secelim
            python_exe = python_paths[0].strip()
            print(f"[{self.host}] Bulunan Python Yolu: {python_exe}")
            
            # PsExec ile Sesson 0'dan kurtulup hedef kullanicinin ekranina scripti at
            # Not: C:\PSTools dizininin Path'te olmama ihtimaline karsi komut icinde gecici olarak Path'e ekliyoruz.
            psexec_cmd = f'cmd.exe /c "set PATH=C:\\PSTools;%PATH% && psexec -i {session_id} -s -d -accepteula \"{python_exe}\" {payload_remote_path} {temp_dir}"'
            print(f"[{self.host}] PsExec Enjeksiyon komutu atiliyor...")
            
            # Asenkron tetikledigimiz icin scriptin bitmesini (dosyalarin uretilmesini) bekle
            # Normal sartlarda bu 2-4 saniye surer. Ekrani kilitliyse psexec asili kalabilir, timeout koyalim.
            stdin, stdout, stderr = self.ssh.exec_command(psexec_cmd, timeout=15)
            
            # Psexec ciktilarini yakala (Hata ayiklama icin cok kritik)
            psexec_out = stdout.read().decode('utf-8', errors='ignore')
            psexec_err = stderr.read().decode('utf-8', errors='ignore')
            
            print(f"[{self.host}] PsExec Calistirma Tamamlandi.")
            
            # Sonuclari topla (SFTP ile Local'e Geri Al)
            json_all_remote = f"{temp_dir}\\ui_output_all.json"
            json_vis_remote = f"{temp_dir}\\ui_output_visible.json"
            img_remote = f"{temp_dir}\\ui_map_visual.png"
            err_log_remote = f"{temp_dir}\\psexec_error.log"
            
            import json
            
            # RAM'e anlik okuma yap (Dosya olusturmada)
            try:
                with sftp.file(json_vis_remote, "r") as f:
                    visible_data = json.load(f)
                    
                with sftp.file(json_all_remote, "r") as f:
                    all_data = json.load(f)
                    
                # Resmi API sunucusuna indirelim
                sftp.get(img_remote, "remote_map.png")
            except FileNotFoundError:
                 # Eger dosyalar yoksa, muhtemelen python scripti iceride patladi. Logu okumaya calis.
                 error_details = "Python Log Bulunamadi."
                 try:
                     with sftp.file(err_log_remote, "r") as f:
                         error_details = f.read().decode('utf-8', errors='ignore')
                     sftp.remove(err_log_remote)
                 except:
                     pass
                     
                 # Python logu yoksa asil sorun PsExec seviyesindedir
                 return {
                     "status": "error", 
                     "message": f"Gorseller uretilemedi. PsExec veya Python coktu.\n\n--- PSEXEC STDERR ---\n{psexec_err}\n\n--- PYTHON LOG ---\n{error_details}"
                 }

            # İzi kaybettirme (Gizlilik Cleanup)
            sftp.remove(payload_remote_path)
            sftp.remove(json_all_remote)
            sftp.remove(json_vis_remote)
            sftp.remove(img_remote)
            
            sftp.close()
            self.ssh.close()
            
            return {
                "status": "success",
                "visible_elements": visible_data,
                "all_elements": all_data
            }
            
        except Exception as e:
            if self.ssh:
                 self.ssh.close()
            raise Exception(f"Uzak Baglanti Hatasi: {str(e)}")
