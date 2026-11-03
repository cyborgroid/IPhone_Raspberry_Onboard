# 하드웨어

부품 목록과 조립 순서는 [assembly.md](assembly.md)에 있습니다. 이 문서는 왜 이렇게 구성했는지를 설명합니다.

## 구성

| 항목 | 선택 | 이유 |
|---|---|---|
| 보드 | Raspberry Pi 5 | 사양서 기준 |
| 화면 | 공식 5인치 터치 디스플레이 2 (720×1280, 91.5 × 143.5 mm) | 국내에서 바로 구매, 자동 인식, 파이를 뒷면에 직접 고정 |
| 케이스 | 없음 | 화면이 몸체 역할을 합니다 |
| 전원 | 공식 27W 어댑터, 이동 시 USB-C 보조배터리 | 납땜이 필요 없음 |

Before 이미지는 Flirc Raspberry Pi 3 Case이고, 이 케이스에는 Pi 5가 들어가지 않습니다. After 이미지는 Before를 바탕으로 만든 합성 이미지로 보이며 실제 제품이 아닙니다. 그 모습 그대로는 만들 수 없으므로, 살 수 있는 부품으로 터치폰 형태를 만들었습니다.

실제 부품의 모습은 `design/Raspberry_Desktop_After_v2.png`에 렌더링했습니다.

## 렌더링과 다른 점

| After 이미지 | 실제 기기 |
|---|---|
| 작은 금속 상자 | 5인치 화면 뒤에 파이가 붙은 형태 |
| 풀사이즈 HDMI, 3.5mm 잭 | micro-HDMI 2개, USB-C, 잭 없음 |
| USB 2개 | USB 4개 모두 사용 가능 |
| 화면 내 지문 인식 | 없음 |
| 배터리 78% 표시 | 잔량 측정 부품이 없어 `--`로 표시 |

## 알아 둘 점

- **두께:** 화면 깊이 16 mm에 파이와 USB 단자 높이가 더해져 약 3–4 cm(추정)입니다.
- **발열:** Pi 5는 부하가 걸리면 냉각이 필요합니다. 방열판을 붙이고 [assembly.md](assembly.md)의 부하 시험으로 확인하세요.
- **Wi-Fi:** 내장 안테나를 씁니다. Pi 5에는 외장 안테나 단자가 없습니다.
- **셀룰러 모뎀:** 없습니다. Wi-Fi, 이더넷 또는 휴대폰 테더링이 없는 곳에서는 통신이 안 됩니다.
- **오디오:** 마이크와 스피커가 없으므로 USB 오디오나 블루투스 헤드셋이 필요합니다.
- **전원:** 파이는 5 V 5 A(25 W)를 권장합니다. 부족하면 USB 전류가 600 mA로 제한됩니다.
- **내장 배터리:** 리튬 셀 직접 납땜은 합선 시 화재 위험이 있습니다. 넣으려면 보호회로와 승압 회로가 갖춰진 검증된 모듈을 쓰세요.
- **판매:** `certification.md`는 조립 가능성 검토이며 인증 문서가 아닙니다. 국내 판매에는 전파 적합성 평가(KC)와 배터리 안전 인증 등을 확인해야 합니다.

## 참고 자료

- [디바이스마트 공식 5인치 터치 디스플레이 2](https://www.devicemart.co.kr/goods/view?no=15907263)
- [Raspberry Pi Touch Display 2 문서](https://www.raspberrypi.com/documentation/accessories/touch-display-2.html)
- [USB Power Delivery on Raspberry Pi 5 백서](https://pip-assets.raspberrypi.com/categories/685-app-notes-guides-whitepapers/documents/RP-009856-WP-1-USB%20Power%20delivery%20on%20Raspberry%20Pi%205.pdf)
