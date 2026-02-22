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
        
        # 'query session' ciktisinda > sembolu aktif olan (Masaustune bakan) oturumu isaret eder
        # Ornek: >user1     1    Active 
        for line in output.split('\n'):
            if '>' in line:
                parts = line.split()
                if len(parts) >= 2:
                    return parts[2] if parts[2].isdigit() else parts[1]
        
        # Eger > bulunamazsa fallback olarak Console oturumu aranir:
        for line in output.split('\n'):
            if 'console' in line.lower() and 'Active' in line:
                parts = line.split()
                if len(parts) >= 3:
                     return parts[2] if parts[2].isdigit() else parts[1]
        
        return "1"  # Fallback

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
            
            # PsExec ile Sesson 0'dan kurtulup hedef kullanicinin ekranina scripti at
            # Not: C:\PSTools dizininin Path'te olmama ihtimaline karsi komut icinde gecici olarak Path'e ekliyoruz.
            # Alternatif olarak python kurulusu oldugu varsayilmaktadir.
            psexec_cmd = f'cmd.exe /c "set PATH=C:\\PSTools;%PATH% && psexec -i {session_id} -s -d -accepteula python {payload_remote_path} {temp_dir}"'
            print(f"[{self.host}] PsExec Enjeksiyon komutu atiliyor...")
            
            self.ssh.exec_command(psexec_cmd)
            
            # Asenkron tetikledigimiz icin scriptin bitmesini (dosyalarin uretilmesini) bekle
            # Normal sartlarda bu 2-4 saniye surer.
            time.sleep(6) 
            
            # Sonuclari topla (SFTP ile Local'e Geri Al)
            json_all_remote = f"{temp_dir}\\ui_output_all.json"
            json_vis_remote = f"{temp_dir}\\ui_output_visible.json"
            img_remote = f"{temp_dir}\\ui_map_visual.png"
            
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
                 return {"status": "error", "message": "Gorsel sonuc doyalari okunamadi. PsExec tamamlanamamis olabilir."}

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
