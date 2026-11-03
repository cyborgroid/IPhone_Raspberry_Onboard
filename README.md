# Cyborgroid

Raspberry Pi 5와 공식 터치 화면으로 만드는 터치폰 겸 데스크톱입니다.

| 연결 상태 | 화면 |
|---|---|
| 기기만 들고 쓸 때 | Ubuntu Touch와 비슷하게 디자인한 터치 홈 화면 |
| 모니터를 꽂았을 때 | 일반 Ubuntu 데스크톱 |

Ubuntu Touch를 넣은 것이 아니라, Ubuntu 26.04 위에 비슷한 화면을 직접 만든 것입니다. 앱은 Ubuntu에 기본으로 들어 있는 Firefox, 파일, 계산기 등을 씁니다.

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
| `os/` | SD 카드 이미지 빌드, 시스템 설정, 시험 |
| `design/` | Before/After 이미지와 실제 부품 렌더링 |

## 이미지 빌드

Ubuntu 24.04 이상의 x86-64 PC에서 실행합니다. 필요한 것은 Rust(`aarch64-unknown-linux-musl` 타깃 포함), .NET 10 SDK, Docker, 디스크 여유 공간 약 30GB입니다.

```bash
rustup target add aarch64-unknown-linux-musl
os/build-image.sh
```

결과는 `build/cyborgroid-pi5-날짜.img.xz`입니다. 공식 Ubuntu Desktop for Raspberry Pi 이미지를 내려받아 체크섬을 확인한 뒤 그 위에 구성합니다. Docker를 privileged 모드로 쓰며, 빌드하는 동안 호스트에 arm64 에뮬레이션을 임시로 등록했다가 끝나면 해제합니다.

## 시험

```bash
(cd core && cargo test)                    # 코어 엔진 단위 테스트

docker run --rm --cap-add NET_ADMIN --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined -v "$PWD/os:/os:ro" \
  ubuntu:26.04 /os/test/test-killswitch.sh # 킬스위치: 실제 패킷과 WireGuard 터널로 시험

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
