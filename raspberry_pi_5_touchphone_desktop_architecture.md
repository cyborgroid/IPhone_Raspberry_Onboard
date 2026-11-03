# 📱 라즈베리파이 5 터치폰 데스크톱 & 국경 없는 무상 통신 엔진
# (Raspberry Pi 5 Touchphone Desktop & Borderless Free Telecom Engine)

라즈베리파이 5(Raspberry Pi 5)를 기반으로 구축되는 독립형 모바일-데스크톱 하이프리드 기기 아키텍처 사양서입니다. 
기존 통신사(SKT/KT/LGU+) 및 국가번호(+82 등) 제한을 완전히 탈피하고, Ubuntu Touch 기반의 가상화(VMware/Image) 통신 노드와 하드웨어 직결 VPN, 데이터 토큰 마이닝, 와이파이 공간 인지 엔진을 결합한 **완전 무상·국경 없는 터치폰 데스크톱**을 목표로 합니다.

---

## 🌟 핵심 비전 & 주요 특징 (Key Highlights)

* **통신비 0원 / 통신사 종속성 제거 (Free Borderless Telecom):**
  * 기존 통신사(SKT/KT 등)의 유심 요금제나 국가 번호(+82) 체계에 종속되지 않습니다.
  * Ubuntu Touch OS 이미지의 가상화 노드(VMware 기반 이미지 호환) 및 P2P/IP 기반 통신 기술을 활용하여, 데이터 및 음성 통화 사용료가 완전 무상으로 제공되는 오픈 네트워크를 지향합니다.
* **상시 데이터 & 토큰 채굴 (Data-to-Token Engine):**
  * 데이터를 켜고 끌 필요 없는 상시 연결(Always-On) 상태를 유지하며, 네트워크 패킷 사용량이 백그라운드에서 실시간 데이터 토큰으로 자동 변환됩니다.
* **와이파이 기반 주변 환경 센싱 (Wi-Fi Spatial Sensing):**
  * 와이파이 신호 밀도, RSSI(신호 강도), 채널 분포를 분석하여 외부 GPS/중앙 서버 없이도 기기 주변의 물리적 공간 환경을 스스로 인지합니다.
* **빅테크 및 통신사 통제 탈피 (Total Independence):**
  * 구글, 애플, 통신사의 계정 추적과 국경선에 얽매이지 않는 완전한 개인 소유의 탈중앙화 디바이스입니다.

---

## 📸 1. 하드웨어 구성 요소 (Hardware Components)

### 1.1 핵심 하드웨어
* **메인보드:** Raspberry Pi 5 (Broadcom BCM2712 SoC)
* **디스플레이:** 4인치~7인치 DSI 터치 LCD / 포터블 HDMI 터치 모니터
* **통신 & 안테나:** 무선 Wi-Fi/Bluetooth 모듈 및 국경 없는 P2P 노드용 외부 SMA 안테나
* **보관함/케이스:** Flirc 알루미늄 패시브 쿨링 케이스 또는 커스텀 3D 프린팅 라우터 스타일 케이스 (안테나 체결 홀 포함)

### 1.2 모드 전환 (Form Factor Modes)
* **모바일 모드 (Mobile Mode):** 들고 다니며 가상화 통신망 기반 무상 통화 및 터치 UI 이용
* **데스크톱 모드 (Desktop Mode):** 외부 모니터 및 키보드 연결 시 풀 버전 리눅스 데스크톱 환경으로 자동 전환

---

## 🔒 2. 네트워크 및 보안 아키텍처 (Network Architecture)

* **국경 없는 통신망 (Borderless WireGuard Tunneling):**
  * 부팅 시 커널 레벨에서 WireGuard VPN 터널이 즉시 활성화됩니다.
  * **하드웨어 킬스위치 (`wireguard-killswitch.sh`):** VPN 연결 해제 시 외부 일반 트래픽 출력을 즉시 차단하여 완벽한 익명성과 보안을 보장합니다.
* **와이파이 공간 인지 레이어 (Wi-Fi Spatial Radar):**
  * 주변 와이파이 비콘을 백그라운드에서 주기적으로 스캔하여 물리적 이동 경로와 환경 밀도를 시각화합니다.

---

## 🏗️ 3. 소프트웨어 아키텍처: C# & Rust 이중 구조

```
+-----------------------------------------------------------+
|                   C# (.NET / Avalonia UI)                 |
|  - 터치 최적화 모바일 UI 및 데스크톱 컨버전스 화면         |
|  - 실시간 토큰 지갑 & 무상 통신 상태 대시보드              |
|  - 와이파이 공간 레이더 시각화 (Spatial Radar View)       |
+-----------------------------------------------------------+
                             |
         IPC 통신 (Unix Domain Socket / Local TCP)
                             |
+-----------------------------------------------------------+
|                    Rust Core Engine                       |
|  - 커널 레벨 네트워크 패킷 캡처 및 토큰 자동 발행 데몬      |
|  - Ubuntu Touch 가상화 이미지/P2P 노드 통신 스택 제어     |
|  - 와이파이 주변 환경 신호 스캐닝 및 데이터화              |
+-----------------------------------------------------------+
                             |
+-----------------------------------------------------------+
|               WireGuard Hardware Kill-Switch              |
|  - iptables 기반 미암호화 트래픽 원천 차단 킬스위치        |
+-----------------------------------------------------------+
```

---

## ⚙️ 4. 데이터 토큰 자동 발행 엔진 (Rust Core)

```rust
use std::fs;
use std::thread;
use std::time::Duration;

fn get_interface_bytes(interface: &str) -> Result<u64, Box<dyn std::error::Error>> {
    let path = format!("/sys/class/net/{}/statistics/rx_bytes", interface);
    let data = fs::read_to_string(path)?;
    let bytes: u64 = data.trim().parse()?;
    Ok(bytes)
}

fn main() {
    let interface = "wlan0"; // 또는 통신 노드 인터페이스
    let mut last_bytes = get_interface_bytes(interface).unwrap_or(0);
    let mut accumulated_tokens: f64 = 0.0;

    println!("Starting Traffic-to-Token Engine on {}...", interface);

    loop {
        thread::sleep(Duration::from_secs(5));
        
        match get_interface_bytes(interface) {
            Ok(current_bytes) => {
                if current_bytes > last_bytes {
                    let diff = current_bytes - last_bytes;
                    // 토큰 발행 산식: 1MB(1,048,576 bytes)당 0.01 토큰
                    let earned_tokens = (diff as f64 / 1_048_576.0) * 0.01;
                    accumulated_tokens += earned_tokens;
                    
                    println!("Traffic detected: {} bytes | Minted Tokens: {:.4} (Total: {:.4})", 
                             diff, earned_tokens, accumulated_tokens);
                }
                last_bytes = current_bytes;
            }
            Err(e) => eprintln!("Failed to read interface stats: {}", e),
        }
    }
}
```

---

## 🛡️ 5. WireGuard 하드웨어 킬스위치 (`wireguard-killswitch.sh`)

```bash
#!/usr/bin/env bash
# WireGuard Kill-Switch Script for Raspberry Pi

if [ "$EUID" -ne 0 ]; then
  echo "[!] root 권한으로 실행해야 합니다 (sudo)"
  exit 1
fi

WG_IF="wg0"
PHYS_IF="wlan0"
WG_PORT=51820

iptables -F && iptables -X
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -s 192.168.0.0/16 -j ACCEPT
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

iptables -A OUTPUT -o "$PHYS_IF" -p udp --dport "$WG_PORT" -j ACCEPT
iptables -A OUTPUT -o "$WG_IF" -j ACCEPT
iptables -A INPUT -i "$WG_IF" -j ACCEPT

echo "[+] WireGuard 킬스위치가 활성화되었습니다."
```

---

## 💻 6. C# Avalonia UI 대시보드 (`MainWindow.axaml`)

```xml
<Window xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Class="CyborgroidDashboard.Views.MainWindow"
        Title="Touchphone Desktop" Width="480" Height="800" Background="#1E1E1E">

    <Grid RowDefinitions="Auto, *, Auto" Margin="20">
        <!-- 상단 타이틀 및 네트워크 상태 -->
        <StackPanel Grid.Row="0" Spacing="5">
            <TextBlock Text="BORDERLESS TOUCHPHONE" FontSize="20" FontWeight="Bold" Foreground="#00FF7F"/>
            <TextBlock Text="{Binding VpnStatus}" FontSize="12" Foreground="#888888"/>
        </StackPanel>

        <!-- 중앙 대시보드 카드 -->
        <StackPanel Grid.Row="1" VerticalAlignment="Center" Spacing="20" HorizontalAlignment="Center">
            <Border Background="#2D2D2D" CornerRadius="12" Padding="25" Width="380">
                <StackPanel Spacing="10" HorizontalAlignment="Center">
                    <TextBlock Text="MINTED DATA TOKENS" FontSize="14" Foreground="#AAAAAA" HorizontalAlignment="Center"/>
                    <TextBlock Text="{Binding MintedTokens}" FontSize="36" FontWeight="Bold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                    <TextBlock Text="TOKENS" FontSize="12" Foreground="#00FF7F" HorizontalAlignment="Center"/>
                </StackPanel>
            </Border>

            <!-- 공간 인지 및 무료 통신 상태 -->
            <Border Background="#2D2D2D" CornerRadius="12" Padding="20" Width="380">
                <StackPanel Spacing="5">
                    <TextBlock Text="FREE NODE & SPATIAL ENGINE" FontSize="12" Foreground="#AAAAAA"/>
                    <TextBlock Text="{Binding TrafficStatus}" FontSize="14" Foreground="#DDDDDD" TextWrapping="Wrap"/>
                </StackPanel>
            </Border>
        </StackPanel>

        <!-- 하단 버튼 컨트롤 -->
        <StackPanel Grid.Row="2" Orientation="Horizontal" Spacing="15" HorizontalAlignment="Center">
            <Button Content="VPN 상태" Width="120" HorizontalContentAlignment="Center"/>
            <Button Content="공간 스캔" Width="120" HorizontalContentAlignment="Center"/>
            <Button Content="설정" Width="100" HorizontalContentAlignment="Center"/>
        </StackPanel>
    </Grid>
</Window>
```