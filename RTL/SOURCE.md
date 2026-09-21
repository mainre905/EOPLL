# 이 디렉터리의 출처

EOPLL 은 TDC 와 DAC 를 한 보드에서 합치는 저장소다. RTL 원본은 두 형제 저장소에 있고,
여기 있는 것은 **특정 시점의 사본**이다. 원본을 고쳤으면 여기도 다시 복사해야 한다.

가져온 날짜 : 2026-09-21

| 파일 | 원본 | 원본 커밋 |
|---|---|---|
| `tdc_zedboard_top.v` (최상위), `tdc_test_top.v`, `tdc_fmcw_core_co.v`, `tdc_timestamp_calc.v`, `tdc_calib_ram.v`, `tdc_histogram.v`, `phase_shifter.v`, `dna_reader.v`, `tdc_axi_regs.v`, `tdc_seq.v`, `tdc_capture.v`, `tdc_zedboard.xdc` | `../TDC/RTL/` | `f935720` (2026-09-21) |
| `dac_chirp_engine.v`, `dac_stream_spi.v`, `dac_test.xdc`, `dac_timing.tcl` | `../DAC/RTL/` | `dd1c23f` (2026-09-15) |

`../TDC/tcl/bd_ps_sys.tcl` 와 `../DAC/tcl/bd_dac_sys.tcl` 는 `EOPLL/tcl/` 에,
`../TDC/build_zedboard.tcl` 는 `EOPLL/tcl/build_zedboard_tdc.tcl` 로 들어왔다.

## 고른 기준 — 왜 이 파일들인가

TDC 쪽 목록은 추측이 아니라 `../TDC/build_zedboard.tcl:82-92` 의 `add_files` 목록 그대로다.
즉 **실제로 보드에 올라가는 빌드가 읽는 파일들**이다.

## 버린 것 — EOPLL 루트에 있던 구버전

2026-09-21 에 루트의 `tdc_fmcw_core.v`, `tdc_test_top.v`, `tdc_timestamp_calc.v`,
`tdc_histogram.v`, `phase_shifter.v`, `tdc.xdc` 를 지웠다 (git 이력에 남아 있다).
같은 이름이지만 **다른 설계**다 :

| | 지운 구버전 | 현재 (여기 있는 것) |
|---|---|---|
| 보드 | Zybo `xc7z010clg400` | ZedBoard `xc7z020clg484-1` |
| 캐리체인 탭 소스 | `tdc_fmcw_core.v` — CARRY4 의 `O`(XOR) 출력 | `tdc_fmcw_core_co.v` — `CO`(캐리) 출력 (2026-08-22 전환) |
| 체인 길이 | 80 단 = 320 탭 | 96 단 = 384 탭 |
| 교정표 | `tdc_calib_rom` IP (COE, 읽기 전용) | `tdc_calib_ram.v` (512x13bit, PS 가 AXI 로 쓴다) |
| 클럭 | 온보드 발진기 | PS7 `FCLK_CLK0` -> `clk_wiz_0` -> 200 MHz |
| 제어 | 버튼 + ILA | PS + AXI4-Lite (`tdc_axi_regs` / `tdc_seq` / `tdc_capture`) |
| 히트 입력 | PMOD 단선 (V8) | FMC LA27_P/N 차동 (E21/D21), TLV3605 LVDS |

## 가져온 직후 회귀 시험 결과 (2026-09-21, Orin, iverilog 12.0)

- `sim/run_iverilog_tdc.sh` — **전부 통과**. 교정표 RAM T0~T7 (mismatches 0),
  음성 시험(지연 3 이면 실패해야 -> 실패함), Mode 0 히트 생성기 5 조건,
  `tdc_zedboard_top` 최상위 엘러보레이션.
- `sim/run_iverilog_dac.sh` — **일부 실패**. SPI 스트리밍 8 항목은 전부 통과
  (단선 3.125 MSPS ~ quad 16.499 MSPS), 처프 엔진 6 항목은
  `dac_chirp_engine.v:825` 의 `ODDR` 프리미티브 스텁이 없어 컴파일 실패.
  ★ 이 실패는 **원본 `../DAC` 저장소에서도 똑같이 난다** (확인함). 복사 때문이 아니다.
  고치려면 `sim/` 에 ODDR 빈 모듈 스텁이 필요하다 — DAC 쪽 미해결 항목이다.

---

# 2026-09-21 통합 — 새로 만든 파일

사용자 결정 네 가지를 전제로 했다 :
(1) ZedBoard PS+AXI 구조를 그대로 간다, (2) 66 MHz SCK 는 쓸 일이 없다,
(3) 새 보드 핀맵은 보류, (4) EOPLL 루프는 미정.

| 파일 | 무엇인가 |
|---|---|
| `tcl/bd_eopll_sys.tcl` | **통합 블록 디자인**. PS7 하나에 인터커넥트 하나, 마스터 4개 — M00 `axi_quad_spi`(DAC 설정) / M01 `axi_gpio` / M02 `dac_chirp_engine` / M03 외부 `M_AXI`(top 에서 `tdc_axi_regs`). `bd_ps_sys.tcl` + `bd_dac_sys.tcl` 을 합친 것이다. |
| `RTL/eopll_zedboard_top.v` | **통합 최상위**. `tdc_zedboard_top.v` 에서 네 군데만 고쳤다 — 모듈 이름, BD 래퍼 이름, DAC 핀 포트 7개 추가, 그 포트 연결. TDC 경로는 한 줄도 안 건드렸다. |
| `build_eopll.tcl` (루트) | **통합 빌드**. `../TDC/build_zedboard.tcl` 에서 최상위·BD·소스목록만 바꾸고 핀맵 안전장치를 넣었다. IP 설정과 구현 전략은 그대로다. |
| `tcl/check_build.tcl` | `../TDC/tcl/` 에서 그대로 복사 (커밋 `f935720`). 최상위 이름을 박아 두지 않아 수정 없이 쓴다. |
| `sim/run_iverilog_eopll.sh` | 통합 최상위 엘러보레이션 회귀. |
| `sim/elab_stubs.v` (추가분) | `eopll_sys_wrapper` 스텁 (BD 래퍼 대역). |

`tcl/bd_ps_sys.tcl` 과 `tcl/bd_dac_sys.tcl` 은 **출처 참고용**으로만 둔다.
EOPLL 빌드는 `tcl/bd_eopll_sys.tcl` 하나만 source 한다. 저 둘을 돌리면 각각 별개의
PS7 블록 디자인이 만들어진다.

## ★ AXI 주소 충돌 — 합치면서 DAC 를 옮겼다

합치기 전 두 설계가 같은 주소를 쓰고 있었다 :

| | 원래 | 근거 | 통합 후 |
|---|---|---|---|
| `tdc_axi_regs` | 0x43C0_0000, 64 KB | `../TDC/vitis/tdc_app.c:88` `TDC_BASE` | **그대로** |
| `dac_chirp_engine` | 0x43C0_0000, 16 KB | `../DAC/vitis/dac_chirp.c:73` `FSM_BASE` | **0x43C1_0000** 으로 이동 |
| `axi_quad_spi` | 0x41E0_0000 | `dac_chirp.c:71` | 그대로 |
| `axi_gpio` | 0x4120_0000 | `dac_chirp.c:72` | 그대로 |

TDC 를 남긴 이유 : 둘 중 하나는 소프트웨어를 고쳐야 하는데, TDC 앱은 측정 절차
전체(메뉴·캡처·교정)가 그 상수에 얽혀 있고 DAC 쪽은 `#define` 한 줄이다.
TDC 아퍼처가 64 KB(0x43C0_0000~0x43C0_FFFF)라 0x43C1_0000 이 바로 뒤 빈자리다.

**→ EOPLL 용 DAC 소프트웨어는 `FSM_BASE` 를 0x43C1_0000 으로 고쳐야 한다.**
안 고치면 DAC 레지스터 접근이 TDC 레지스터를 때린다 — 빌드는 통과하고 실물에서만 틀린다.

## 클럭

`FCLK_CLK0`(100 MHz) 하나로 AXI 도메인과 DAC 를 돌린다. TDC 의 200 MHz 는 예전처럼
top 의 `clk_wiz_0`(MMCM, VCO 1000 MHz) 이 만든다. DAC 용 별도 SPI 도메인은 넣지 않았다
(사용자 결정). 따라서 DAC 재생 상한은 `aclk` 100 MHz 기준 **quad 12.5 MSPS** 다 —
`../DAC/sim` 회귀의 실측 표시값이고, 132 MHz 도메인을 뒀을 때의 16.499 MSPS 는 포기한 값이다.

## 아직 안 된 것

1. **핀 배치(XDC)** — 보류. `RTL/tdc_zedboard.xdc` 만 빌드에 들어간다. `RTL/dac_test.xdc` 는
   EVAL-AD3552RFMCZ 기준이라 합친 보드에서는 **틀린 핀**이므로 넣지 않았다.
   그래서 `build_eopll.tcl` 은 세 번째 인자가 1 이어도 합성·구조확인까지만 하고 멈춘다
   (`EOPLL_PINMAP_READY` 로 푼다). 핀 없는 I/O 로 비트스트림을 뽑으면 Vivado 가 임의 핀에
   배치하고, 그것을 실물에 올리면 엉뚱한 핀이 구동된다.
2. **EOPLL 루프 RTL** — 타임스탬프 → 위상/주파수 오차 → 루프필터 → DAC 코드. 미정.
3. **Vivado 실행 검증** — Orin 에 Vivado 가 없어 `bd_eopll_sys.tcl` 과 `build_eopll.tcl` 은
   **한 번도 돌려 본 적이 없다.** 특히 외부 마스터 포트 `M_AXI` 의 주소 세그먼트 이름과
   `axi_quad_spi` 인터페이스 멤버 핀 이름은 실행해 봐야 안다 (둘 다 못 찾으면 명확히 죽거나
   경고를 찍도록 써 두었다).
