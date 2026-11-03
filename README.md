# Cyborgroid

Raspberry Pi 5와 공식 터치 화면으로 만드는 터치폰 겸 데스크톱입니다.

| 연결 상태 | 화면 |
|---|---|
| 기기만 들고 쓸 때 | iPhone처럼 디자인한 터치 홈 화면 |
| 모니터를 꽂았을 때, 노트북에서 | 일반 Ubuntu 데스크톱 |

iOS나 Ubuntu Touch를 넣은 것이 아니라, Ubuntu 26.04 위에 비슷한 화면을 직접 만든 것입니다. iPhone 18 Pro의 화면 비율을 기준으로 삼았고, iOS 코드나 Apple의 아이콘은 들어 있지 않으며 iPhone 앱은 실행되지 않습니다. 앱은 Ubuntu에 기본으로 들어 있는 Firefox, 파일, 계산기 등을 씁니다.

현재 상태와 안 되는 기능은 [docs/status.md](docs/status.md)를 먼저 읽어 주세요.

## 만들기

- 부품, 가격, 조립: [docs/assembly.md](docs/assembly.md)
- 하드웨어 구성의 이유와 주의점: [docs/hardware.md](docs/hardware.md)
- 원래 구상: [아키텍처 사양서](raspberry_pi_5_touchphone_desktop_architecture.md), [브랜드](Brand_Naming.md), [조립 검토](certification.md)

## 구성

| 폴더 | 내용 |
|---|---|
| `core/` | Rust 데몬. 트래픽 기록, Wi-Fi 스캔, 모드 감지, 상태 제공 |
| `shell/` | C# Avalonia 앱. 홈 화면, 대시보드, 레이더 |
| `os/` | SD 카드 이미지와 PC용 ISO 빌드, 시스템 설정, 시험 |
| `design/` | Before/After 이미지와 실제 부품 렌더링 |

## 이미지 빌드

Ubuntu 24.04 이상의 x86-64 PC에서 실행합니다. 필요한 것은 Rust(`aarch64-unknown-linux-musl` 타깃 포함), .NET 10 SDK, Docker, 디스크 여유 공간 약 30GB입니다.

```bash
rustup target add aarch64-unknown-linux-musl
os/build-image.sh
```

결과는 `build/cyborgroid-pi5-날짜.img.xz`입니다. 공식 Ubuntu Desktop for Raspberry Pi 이미지를 내려받아 체크섬을 확인한 뒤 그 위에 구성합니다. Docker를 privileged 모드로 쓰며, 빌드하는 동안 호스트에 arm64 에뮬레이션을 임시로 등록했다가 끝나면 해제합니다.

## PC용 ISO 빌드

VMware에서 구동하거나 PC, 노트북을 USB로 부팅하는 x86-64 라이브 ISO입니다. 공식 Ubuntu 26.04.1 Desktop ISO에 Cyborgroid 레이어를 하나 더 얹어 만들며, 전원을 끄면 변경 내용이 사라지고 디스크에 설치되지 않습니다. 필요한 것은 Rust, .NET 10 SDK, Docker, 디스크 여유 공간 약 15GB입니다.

```bash
os/build-iso.sh
```

결과는 `build/cyborgroid-amd64-날짜.iso`입니다.

- **VMware:** 새 가상 머신의 CD/DVD에 ISO를 넣고, 게스트 OS는 Ubuntu 64-bit, 메모리는 4GB 이상으로 합니다. 화면은 iPhone 18 Pro 비율의 세로 창으로 뜹니다.
- **노트북:** 내장 패널을 감지하면 일반 Ubuntu 데스크톱으로 시작합니다.
- **화면 전환:** 터치 홈의 "데스크톱" 아이콘으로 데스크톱으로 가고, 앱 메뉴의 "터치 홈 화면"으로 돌아옵니다.

이 PC의 GRUB 메뉴에 올리려면 아래를 실행합니다. 파티션은 바꾸지 않고 ISO를 `~/iso/`에 복사하며, 기본 부팅 항목도 그대로 둡니다.

```bash
os/register-boot.sh --print    # 추가될 항목만 확인
os/register-boot.sh            # 등록
os/register-boot.sh --remove   # 메뉴에서 제거
```

## iPhone 연결

USB로 연결한 iPhone을 홈 화면의 "iPhone" 아이콘에서 등록합니다. 등록을 누르면 iPhone에 신뢰 확인 창이 뜹니다. 등록 후 iPhone에서 개인용 핫스팟을 켜면 USB 테더링을 인터넷 회선으로 쓸 수 있습니다. PC에서 `run.sh`로 실행할 때는 `libimobiledevice-utils`와 `usbmuxd`가 필요합니다. 등록 해제는 `idevicepair unpair`입니다.

## 시험

```bash
(cd core && cargo test)                    # 코어 엔진 단위 테스트

docker run --rm --cap-add NET_ADMIN --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined -v "$PWD/os:/os:ro" \
  ubuntu:26.04 /os/test/test-killswitch.sh # 킬스위치: 실제 패킷과 WireGuard 터널로 시험

os/test/iso-boot-test.py "$PWD"/build/cyborgroid-amd64-*.iso "$PWD"/build/iso-boot-test 600 # PC용 ISO 부팅, 화면 캡처

SKIP_COMPRESS=1 os/build-image.sh
os/test/boot-test.sh build/cyborgroid-pi5-*.img            # 가상 기기 부팅, 화면 캡처
SEED_WG=1 os/test/boot-test.sh build/cyborgroid-pi5-*.img  # VPN 설정을 넣은 부팅
```

부팅 시험의 기록과 화면은 `build/boot-test*/`에 저장됩니다.

## 첫 부팅 때 자동으로 하는 일

- 파티션을 SD 카드 크기에 맞게 확장합니다.
- 기기마다 다른 초기 비밀번호를 만들어 `~/initial-password.txt`에 저장합니다.
- 공유되면 안 되는 SSH 키와 기기 ID를 새로 만듭니다.
- 부트 파티션의 `cyborgroid/` 폴더에 넣어 둔 설정을 가져오고 원본을 지웁니다. `wg0.conf`(VPN), `*.nmconnection`(Wi-Fi), `authorized_keys`(SSH 켜기)를 넣을 수 있습니다.

## 설정 파일

| 파일 | 내용 |
|---|---|
| `/etc/cyborgroid/core.toml` | 사용할 Wi-Fi 인터페이스, 토큰 비율, 스캔 주기 |
| `/etc/cyborgroid/killswitch.conf` | 킬스위치 설정, LAN 허용 여부 |
| `/etc/cyborgroid/sway.d/display.conf` | 터치 화면 회전 |
| `/boot/firmware/config.txt` | 화면 등 하드웨어 설정 |
