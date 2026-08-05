# 일일 작업 리포트 — 2026-08-5

> **작성일** 2026-08-05
> **작성** Gemini 3.1 Pro — 당일 작업 요약
> **주의** AI가 생성한 문서입니다. 수치·절차는 실제 코드/측정과 대조하십시오.

---

# [종합 기술 리포트] 광섬유 기반 MZI 원리 및 OPLL 시스템 심층 설계 가이드

## 1. MZI의 기본 원리 및 핵심 수식 (굴절률 보정)

MZI(마하-젠더 간섭계)는 광로차($\Delta L$)를 이용하여 빛의 주파수 변화를 위상 변화로, 그리고 최종적으로 측정 가능한 비트 주파수($f_b$)로 변환하는 장치입니다.

### 1.1. 기본 수식 관계
*   **주파수와 위상:** 주파수는 위상의 시간에 따른 변화율($f = \frac{d\phi}{dt}$)이며, 위상은 주파수의 적분($\phi(t) = \int f(t) dt$)입니다.
*   **비트 주파수 ($f_b$):** MZI에서 출력되는 비트 주파수는 광원의 주파수 스윕 속도(Chirp rate, $\alpha$)와 간섭계 내부의 지연 시간($\tau$)의 곱입니다.
    $$f_b = \alpha \cdot \tau = \left(\frac{B}{T}\right) \cdot \tau$$
    *(여기서 $B$: 주파수 스윕 범위, $T$: 한 방향 스윕 시간)*

### 1.2. [중요 정정] 광섬유 지연 시간($\tau$) 계산 수식
기존 자료에 명시된 $\tau = \frac{2\Delta L}{c}$는 빛이 진공/공기 중에서 왕복(Round-trip)할 때의 수식입니다. **단일모드 광섬유(Optical Fiber)를 단방향으로 통과하는 실제 시스템**에서는 광섬유의 유효 굴절률($n_{eff} \approx 1.47$)을 반드시 반영해야 합니다.
$$ \tau = \frac{n_{eff} \cdot \Delta L}{c} $$
*(여기서 $c$는 진공 중 빛의 속도 $3 \times 10^8 \text{ m/s}$)*

> **[예제 1] 주어진 조건으로 시스템 대역폭($B$) 역산하기**
> *   **조건:** 광로차 $\Delta L = 1 \text{ m}$, 스윕 시간 $T = 10 \text{ ms} = 0.01 \text{ s}$, 측정된 $f_b = 37 \text{ kHz}$
> *   **지연 시간($\tau$) 계산:** $\tau = \frac{1.47 \times 1}{3 \times 10^8} = 4.9 \times 10^{-9} \text{ s} = 4.9 \text{ ns}$
> *   **스윕 범위($B$) 도출:** $B = \frac{f_b \cdot T}{\tau} = \frac{37 \times 10^3 \times 0.01}{4.9 \times 10^{-9}} \approx 7.55 \times 10^{10} \text{ Hz} = \mathbf{75.5 \text{ GHz}}$
> *(참고: 굴절률을 무시한 기존 자료에서는 $55.5 \text{ GHz}$로 잘못 계산되었으나, $n=1.47$을 반영하면 실제 시스템은 $75.5 \text{ GHz}$ 스윕 시스템임을 알 수 있습니다.)*

---

## 2. 물리적 하드웨어의 진실: 커플러와 BPD의 역할

MZI에서 빛이 간섭하고 전기 신호로 바뀌는 하드웨어적 과정은 단순한 "분배"가 아닙니다.

### 2.1. $2 \times 2$ 방향성 커플러(Directional Coupler)의 물리적 특성
MZI의 마지막 단에서 두 빛(짧은 경로, 긴 경로)을 합치는 소자는 Y자 결합기가 아니라 $2 \times 2$ 커플러입니다. 
*   이 소자 내부에서 빛의 에너지가 옆 광섬유 코어로 넘어갈 때(소멸파 결합), 자연계의 전자기학 법칙에 의해 **반드시 $90^\circ (\pi/2)$의 위상 지연**이 발생합니다.
*   이로 인해 두 출력 포트에서 나오는 빛의 세기(Intensity)는 다음과 같이 덧셈(간섭)됩니다.
    *   **출력 1 ($I_1$):** $\propto \frac{1}{2} (1 + \cos(\Delta\phi))$
    *   **출력 2 ($I_2$):** $\propto \frac{1}{2} (1 - \cos(\Delta\phi))$
*   **결론:** MZI는 하나의 파형을 쪼개는 것이 아니라, 애초에 **서로 $180^\circ$ 위상차가 나는(역상) 두 개의 독립된 간섭 파형**을 출력합니다.

### 2.2. BPD (Balanced Photodetector)의 전기적 뺄셈
BPD는 MZI에서 나온 이 180도 뒤집힌 두 신호(위상차 신호)를 받아 전기적으로 뺍니다($I_{out} = I_1 - I_2$).
*   **신호 증폭:** $A \cos(\omega t) - (-A \cos(\omega t)) = \mathbf{2A \cos(\omega t)}$ (우리가 원하는 $f_b$ 신호는 2배 증폭)
*   **노이즈 제거:** 레이저 자체의 밝기 떨림이나 DC 성분(공통 노이즈 $N$)은 $N - N = \mathbf{0}$ (완벽히 상쇄)

---

## 3. 광로차($\Delta L$) 설계의 딜레마: 감도 vs 안정성

OPLL 설계 시 $\Delta L$을 결정하는 것은 센서 성능(광학)과 제어 성능(전자) 간의 처절한 타협입니다.

### 3.1. [센서 관점] $\Delta L$을 늘려야 하는 이유: 오차의 물리적 증폭
MZI는 "현재 주파수"와 "과거 주파수"의 차이를 측정합니다.
주파수 오차가 $A \sin(\omega t)$ 형태일 때, MZI를 거친 비트 주파수의 오차 성분 $\Delta f_b$는 다음과 같이 계산됩니다.
$$ \Delta f_b = A \sin(\omega t) - A \sin(\omega(t-\tau)) \approx \mathbf{A \cdot \omega \cdot \tau} $$
즉, 원래 오차 크기($A$)가 같더라도, 광섬유가 길어져 지연 시간($\tau$)이 커지면 **최종 측정되는 에러 신호가 $\tau$에 비례하여 뻥튀기(증폭)됩니다.** 따라서 신호를 노이즈 플로어 위로 끌어올리기 위해서는 $\Delta L$이 길어야 유리합니다.

### 3.2. [제어 관점] $\Delta L$을 무작정 늘리면 안 되는 이유: 루프 지연과 발진
OPLL은 오차를 측정하여 레이저를 실시간 교정(Feedback)하는 시스템입니다. $\Delta L$이 길어지면 시스템 내부의 정보 전달 지연($\tau$)이 커집니다.
*   제어계에서 지연 요소는 전달함수 $e^{-s\tau}$로 작용하여 고주파 대역에서 **위상 여유(Phase Margin)를 급격히 깎아먹습니다.**
*   **샤워기 비유:** 보일러 파이프(지연시간 $\tau$)가 너무 긴데, 내 손(제어기)을 잽싸게 놀리면, 과거의 틀린 온도 정보 때문에 온수와 냉수를 미친 듯이 번갈아 트는 참사가 발생합니다.
*   이를 제어공학에서는 **발진(Oscillation)**이라고 부르며, 레이저 주파수가 고정되지 못하고 폭주하게 됩니다.

---

## 4. OPLL 안정성을 위한 황금률 및 최적 설계 예제

### 4.1. 시스템 안정성 설계 방침
발진을 막고 충분한 위상 여유($45^\circ \sim 60^\circ$)를 확보하기 위한 제어공학적 황금률 수식은 다음과 같습니다.
$$ \tau \cdot BW_{loop} \le 0.1 $$
*(의미: 시스템 물리적 딜레이($\tau$)에 비해 제어 루프의 반응 속도($BW_{loop}$)가 최소 10배 이상 느려야 안전하다.)*

### 4.2. [예제 2] 55GHz / 10ms 시스템의 최적 $\Delta L$ 설계
*   **주어진 시스템 조건:** 
    *   $B = 55 \text{ GHz}$
    *   $T = 10 \text{ ms}$
    *   Chirp rate $\alpha = 5.5 \times 10^{12} \text{ Hz/s}$
    *   광섬유 굴절률 $n = 1.47$

**Step 1. 루프 대역폭 기준 절대 상한선 (Upper Bound) 계산**
*   디지털 OPLL 루프 대역폭을 보수적으로 $BW = 50 \text{ kHz}$ 가정.
*   안정성 조건에 따라 $\tau \le \frac{0.1}{50\text{kHz}} = 2 \text{ }\mu\text{s}$
*   최대 광섬유 길이: $\Delta L_{max} = \frac{\tau \cdot c}{n} = \frac{2\times10^{-6} \cdot 3\times10^8}{1.47} \approx \mathbf{408 \text{ m}}$ *(절대 넘으면 안 되는 한계치)*

**Step 2. 비트 주파수($f_b$) 타겟팅에 따른 $\Delta L$ 계산**
수정된 공식 $\Delta L = \frac{c \cdot f_b}{\alpha \cdot n}$ 적용. ($\frac{c}{\alpha \cdot n} \approx 3.71 \times 10^{-5} \text{ m/Hz}$)
*   디지털 카운터가 처리하기 좋은 하한선 $f_b = 50 \text{ kHz} \rightarrow \Delta L \approx \mathbf{1.85 \text{ m}}$
*   디지털 카운터가 처리하기 좋은 상한선 $f_b = 500 \text{ kHz} \rightarrow \Delta L \approx \mathbf{18.5 \text{ m}}$

**Step 3. 최적 구간 결론**
*   $\Delta L$이 **$5 \sim 20 \text{ m}$** 인 구간($f_b \approx 130 \sim 540 \text{ kHz}$)이 측정 감도(에러 증폭)를 충분히 확보하면서도, 딜레이($\tau$)가 루프 대역폭에 악영향을 주지 않아 발진을 막을 수 있는 **최적의 스위트 스팟(Sweet Spot)**입니다.

---

## 5. 파이썬 증명 시뮬레이션

$\Delta L$이 1m에서 10m로 길어질 때, PD에서 관측되는 **실제 오실로스코프 파형(전압)의 주파수가 빽빽해지는 현상**을 증명하는 코드입니다.

```python
import numpy as np
import matplotlib.pyplot as plt

# --- 1. 시스템 파라미터 ---
c = 3e8
n_eff = 1.47
alpha = 5.5e12  # 55GHz / 10ms 스윕 속도

L_short = 1.0   # 1m 광로차
L_long = 10.0   # 10m 광로차

# 지연 시간(tau) 계산
tau_short = (n_eff * L_short) / c
tau_long = (n_eff * L_long) / c

# 이상적인 비트 주파수 (거리에 비례하여 10배 차이 발생)
fb_base_short = alpha * tau_short  # 약 27.2 kHz
fb_base_long = alpha * tau_long    # 약 272.7 kHz

# 레이저 자체의 위상 노이즈 (1kHz 주기로 50MHz 폭으로 흔들림을 가정)
error_amp = 50e6
error_f = 1e3

# 파형 관측을 위한 미세 시간 배열 (0.2ms)
t = np.linspace(0, 0.0002, 5000)

# --- 2. 오실로스코프 파형 생성 함수 ---
def generate_oscilloscope_signal(t, tau, fb_base):
    # 과거와 현재의 주파수 에러 차이 (물리적 뺄셈)
    current_err = error_amp * np.sin(2 * np.pi * error_f * t)
    past_err = error_amp * np.sin(2 * np.pi * error_f * (t - tau))
    beat_error_freq = current_err - past_err  # 뺀 결과물 (에러 신호)
    
    # 순시 주파수 = 기본 비트주파수 + 에러 성분
    inst_freq = fb_base + beat_error_freq
    
    # 주파수를 적분하여 위상(Phase) 도출
    dt = t[1] - t[0]
    phase = np.cumsum(inst_freq) * dt
    
    # 빛의 간섭 신호 (오실로스코프 전압 형태)
    return np.cos(2 * np.pi * phase)

# 파형 생성
signal_short = generate_oscilloscope_signal(t, tau_short, fb_base_short)
signal_long = generate_oscilloscope_signal(t, tau_long, fb_base_long)

# --- 3. 결과 그래프 출력 ---
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)

ax1.plot(t * 1000, signal_short, color='blue', linewidth=1.5)
ax1.set_title(f"Oscilloscope Trace: 1m Fiber (Base Freq $\\approx$ {fb_base_short/1000:.1f} kHz)")
ax1.set_ylabel("Voltage (V)")
ax1.grid(True, linestyle='--', alpha=0.6)

ax2.plot(t * 1000, signal_long, color='red', linewidth=1.5)
ax2.set_title(f"Oscilloscope Trace: 10m Fiber (Base Freq $\\approx$ {fb_base_long/1000:.1f} kHz)")
ax2.set_xlabel("Time (ms)")
ax2.set_ylabel("Voltage (V)")
ax2.grid(True, linestyle='--', alpha=0.6)

plt.tight_layout()
plt.show()
```

*   **시뮬레이션 결론:** 파이썬 실행 시 10m 광섬유의 파형(빨간색)이 1m 파형(파란색)보다 정확히 10배 더 빽빽하게 진동하는 고주파 파형임을 시각적으로 확인할 수 있습니다. 이 과정에서 파도에 숨겨진 미세한 에러 신호 진폭 역시 함께 증폭되어, 전자 회로가 레이저의 오차를 명확히 인지하고 제어(Feedback)할 수 있게 됩니다.