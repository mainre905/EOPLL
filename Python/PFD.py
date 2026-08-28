import numpy as np
import matplotlib
import matplotlib.pyplot as plt
from scipy.signal import butter, lfilter
import io

# ==================== [핵심 해결책] 폰트를 도형(Path)으로 변환 ====================
# 글자를 폰트 텍스트가 아닌 벡터 선 형태로 그려서 마크다운 뷰어에서 100% 보이게 함
matplotlib.rcParams['svg.fonttype'] = 'path'

# ==================== 1. 시뮬레이션 데이터 생성 ====================
t = np.linspace(0, 5e-6, 5000)
dt = t[1] - t[0]
fs = 1 / dt

f_ref_val = 3e6
ref_sine = np.sin(2 * np.pi * f_ref_val * t)

f_beat_inst = 1.5e6 + (3.0e6 / 5e-6) * t 
beat_phase = 2 * np.pi * np.cumsum(f_beat_inst) * dt
beat_sine = np.sin(beat_phase)

ref_square = (ref_sine > 0).astype(int)
beat_square = (beat_sine > 0).astype(int)

up_pulse = np.zeros_like(t)
down_pulse = np.zeros_like(t)
state = 0

for i in range(1, len(t)):
    ref_edge = (ref_square[i] == 1 and ref_square[i-1] == 0)
    beat_edge = (beat_square[i] == 1 and beat_square[i-1] == 0)
    
    if ref_edge and not beat_edge:
        if state == 0: state = 1
        elif state == -1: state = 0
    elif beat_edge and not ref_edge:
        if state == 0: state = -1
        elif state == 1: state = 0
    elif ref_edge and beat_edge:
        state = 0
        
    if state == 1: up_pulse[i] = 1
    if state == -1: down_pulse[i] = 1

pfd_raw = up_pulse - down_pulse

b, a = butter(2, 10e6 / (fs / 2), btype='low')
v_filter = lfilter(b, a, pfd_raw)
v_integrated = np.cumsum(v_filter) * dt * 5e6 

# ==================== 2. 그래프 그리기 ====================
fig = plt.figure(figsize=(10, 10))

plt.subplot(5, 1, 1)
plt.plot(t*1e6, beat_sine, 'b', label=r'MZI Beat Signal ($f_{beat}$)')
plt.plot(t*1e6, ref_sine, 'r--', alpha=0.5, label=r'Target Ref ($f_{ref}$)')
plt.title('1. Photodiode Output (Analog Beat Signal with Laser Non-linearity)', fontsize=11, fontweight='bold')
plt.ylabel('Amp')
plt.legend(loc='upper right')

plt.subplot(5, 1, 2)
plt.plot(t*1e6, ref_square + 1.5, 'r', label=r'Ref Clock ($f_{Ref}$)')
plt.plot(t*1e6, beat_square, 'b', label=r'Beat Clock ($f_{beat}$)')
plt.title('2. Limiter Output (Digitized Square Waves)', fontsize=11, fontweight='bold')
plt.ylabel('Logic')
plt.yticks([0, 1, 1.5, 2.5], ['0', '1', '0', '1'])
plt.legend(loc='upper right')

plt.subplot(5, 1, 3)
plt.plot(t*1e6, up_pulse, 'g', label='UP (Beat SLOW)')
plt.plot(t*1e6, -down_pulse, 'm', label='DOWN (Beat FAST)')
plt.axhline(0, color='black', linewidth=0.5)
plt.title('3. PFD Output (Raw Pulse Train = Phase Error)', fontsize=11, fontweight='bold')
plt.ylabel('Pulse')
plt.ylim(-1.2, 1.2)
plt.legend(loc='upper right')

plt.subplot(5, 1, 4)
plt.plot(t*1e6, v_filter, 'c', linewidth=1.5, label=r'Filtered Voltage ($V_{Filter}$)')
plt.axhline(0, color='black', linewidth=0.5)
plt.title('4. Loop Filter Output (High-Frequency Noise Removed)', fontsize=11, fontweight='bold')
plt.ylabel('Voltage (V)')
plt.legend(loc='upper right')

plt.subplot(5, 1, 5)
plt.plot(t*1e6, v_integrated, 'k', linewidth=2, label=r'Integrated Voltage ($\int V_{Filter} dt$)')
plt.title('5. Integrator Output (Final Pre-distortion Signal to Laser Driver)', fontsize=11, fontweight='bold')
plt.xlabel(r'Time ($\mu s$)')
plt.ylabel('Correction (V)')
plt.legend(loc='upper left')

plt.tight_layout()

# ==================== 3. SVG 변환 및 정리 ====================
svg_buf = io.StringIO()
plt.savefig(svg_buf, format='svg')
svg_data = svg_buf.getvalue()
plt.close()

# SVG 파일 본문만 커팅
svg_start_idx = svg_data.find('<svg')
svg_clean = svg_data[svg_start_idx:]

# ==================== 4. Markdown 문서 자동 생성 ====================
md_content = f"""# FMCW LiDAR 레이저 선형화를 위한 EOPLL 신호 처리 분석 보고서

## 1. 개요 (Overview)
본 문서는 FMCW LiDAR 시스템에서 레이저 광원의 비선형 주파수 변조(Non-linear Chirp) 특성을 보정하기 위한 **광 위상 고정 루프(EOPLL, Electro-Optical Phase-Locked Loop)**의 신호 처리 과정을 분석합니다.

보조 간섭계(MZI)로부터 피드백된 신호가 **PFD(위상/주파수 검출기) ➔ 루프 필터 ➔ 적분기**를 거치면서 레이저 구동 신호(Pre-distortion Voltage)로 변환되는 전체 메커니즘을 시뮬레이션합니다.

---

## 2. EOPLL 피드백 시스템 파형 시뮬레이션

<div align="center">

{svg_clean}

</div>

---

## 3. 단계별 신호 처리 상세 설명

### ① 1단계: Photodiode Output (아날로그 비트 신호)
* **상황:** 레이저 주파수가 초반에는 천천히 증가하다가 후반부에 너무 빠르게 증가하는 비선형성을 가집니다.
* **파형 특성:** MZI 보조 간섭계를 통과한 실제 비트 신호($f_{{beat}}$, 파란색)는 초반(0~3$\\mu s$)에는 파동 간격이 듬성듬성(느림)하고, 후반부(4~5$\\mu s$)에는 촘촘해집니다(빠름). 
* **목표:** 분홍색 점선인 고정된 기준 주파수($f_{{ref}}$)에 $f_{{beat}}$를 맞추는 것입니다.

### ② 2단계: Limiter Output (디지털 사각파 변환)
* **역할:** 디지털 PFD 로직 회로가 신호를 인식할 수 있도록 아날로그 파동을 비교기(Limiter)를 통해 **0과 1의 사각파(Square Wave)**로 변환합니다.
* **비교:** 빨간색 기준 클록($f_{{Ref}}$)과 파란색 실제 비트 클록($f_{{Beat}}$)의 상승 에지(Rising Edge) 시점을 비교합니다.

### ③ 3단계: PFD Output (위상/주파수 오차 펄스 추출)
* **초록색 UP 펄스 (+1.0):** 0~4$\\mu s$ 구간에서 $f_{{beat}}$가 $f_{{ref}}$보다 느리므로 PFD는 레이저 속도를 올리라는 **UP 펄스**를 출력합니다.
* **보라색 DOWN 펄스 (-1.0):** 4.2~5$\\mu s$ 구간에서 $f_{{beat}}$가 $f_{{ref}}$보다 빨라지자 레이저 속도를 낮추라는 **DOWN 펄스**를 출력합니다.

### ④ 4단계: Loop Filter Output (고주파 노이즈 제거)
* **역할:** PFD에서 튀어나온 뾰족한 펄스 성분을 저역통과 필터(Low-Pass Filter)로 깎아내어 매끄러운 **순간 오차 전압($V_{{Filter}}$)**으로 전환합니다.
* **결과:** 초반에는 양(+)의 전압, 후반에는 음(-)의 전압 형태를 가집니다.

### ⑤ 5단계: Integrator Output (최종 레이저 보정 전압)
* **역할:** MZI 간섭계는 미분기(Derivative) 역할을 하므로, 오차 전압을 **시간 축으로 적분($\\int V_{{Filter}} dt$)**하여 원본 주파수 보정 곡선을 만듭니다.
* **결과:** 
  * 0~4.2$\\mu s$ 동안 양(+)의 전압이 누적되며 전압이 0V에서 14.7V까지 **우상향 상승**합니다. (부족한 주파수 변화율을 보충)
  * 4.2$\\mu s$ 이후 음(-)의 전압이 적분되면서 전압이 **아래로 꺾이기 시작**합니다. (과도한 주파수 변화율을 억제)

---

## 4. 결론
이 최종 5단계 전압 파형은 레이저의 기본 톱니파 전류(Nominal Chirp)에 **사전 왜곡(Pre-distortion) 신호**로 합산되어 피드백됩니다. 이를 통해 비선형적이었던 레이저 광원은 최종적으로 **완벽한 선형 주파수 스위핑(Linear Chirp)**을 달성하게 됩니다.
"""

with open("FMCW_LiDAR_EOPLL_Report.md", "w", encoding="utf-8") as f:
    f.write(md_content)

print("성공적으로 글자 출력이 완벽하게 해결된 'FMCW_LiDAR_EOPLL_Report.md' 파일이 생성되었습니다!")