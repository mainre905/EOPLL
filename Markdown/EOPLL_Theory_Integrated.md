<!--
================================================================
 문서 메타데이터
================================================================
-->

# [통합 이론서] 레이저 선폭에서 EO-PLL까지 — FMCW LiDAR 선형화의 물리와 설계

| 항목 | 내용 |
|---|---|
| **작성일** | 2026-08-05 |
| **작성자** | Claude (Opus 4.8) — Anthropic |
| **문서 성격** | AI 생성 **통합 문서**. 원본 3편을 문헌 검증 후 하나의 논리 흐름으로 재구성 |
| **원본** | [FMCW_General_equation.md](FMCW_General_equation.md), [FMCW_OPLL_equation.md](FMCW_OPLL_equation.md), [OPLL_Basic.md](OPLL_Basic.md) *(원본은 보존)* |
| **후속 연결** | [control_block_design.md](control_block_design.md) — 본 이론서의 §5가 이어짐 |
| **주의** | AI가 생성한 문서입니다. 수식·수치·절차는 실제 코드/측정/1차 문헌과 반드시 대조하십시오. |

> **문헌 검증 요약 (§1.2)**
> - **Case 1**(비결맞음, $\Delta\nu=\Delta f_b/2$): 문헌 확인됨 — DSH 비트노트는 동일 스펙트럼 2개의 자기상관(Voigt)이라 Lorentzian FWHM이 실제 선폭의 2배. [Optica OE 14-9-3923](https://opg.optica.org/oe/fulltext.cfm?uri=oe-14-9-3923&id=89596), [MDPI Sensors 11-10-9233](https://www.mdpi.com/1424-8220/11/10/9233)
> - **Case 2**(결맞음/단지연 단순 FWHM식): **표준 결과 아님** — 단지연 영역은 결맞음 포락선(사이드로브)으로 나타나 단순 역산 불가, 포락선 피팅 필요. 원본의 단순식은 **참고용 근사**로만 표기하고, 이 프로젝트에 실제로 유효한 물리(스윕 비선형성 확산)는 §1.3으로 대체 서술. [Optica AO 61-13-3761](https://opg.optica.org/ao/abstract.cfm?uri=ao-61-13-3761), [NCBI PMC9416656](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9416656/)

---

## 통합 시 적용한 정정 · 통일 (투명성 기록)

| # | 원본 위치 | 문제 | 통합본 처리 |
|---|---|---|---|
| C1 | FMCW_OPLL_equation §1 예시 | $f_{b,mzi}=20\text{THz/s}\times7.5\text{ns}$를 **150 MHz**로 표기 (1000× 오류) | **150 kHz**로 정정 (§3.2). FSR=133.3 MHz는 원본이 맞음 |
| C2 | General($\tau=2R/c$) vs OPLL($\tau=n_g\Delta L/c$) | 계수 2의 겉보기 모순 | 모순 아님 — **왕복(타깃) vs 단일통과(광섬유 MZI)**로 명시 (§2.1, §3.1) |
| C3 | 표기 불일치 | chirp rate $\gamma$/$\alpha$, 굴절률 $n_g$/$n_{eff}$, 스윕시간 $T_m$/$T$ | 본서 통일: **$\gamma$(chirp rate), $n_g$(group index), $T$(단방향 스윕시간)** |
| C4 | Coherence length | General $c/\Delta\nu$ vs OPLL_Basic $\ln2,\pi$ 포함형 | 표준형 $L_c=c/(\pi n_g\Delta\nu)$로 통일, 관례 변형 병기 (§1.1) |
| C5 | OPLL_Basic §1.2 Case 2 | 결맞음 영역 단순식이 비표준 | 참고 근사로 격하 + 유효 물리(§1.3 Carson 확산)로 대체 |

---

## 기호 정의 (통일)

| 기호 | 정의 | 단위 |
|------|------|------|
| $\nu,\ f$ | 광 주파수 / 순간 주파수 | Hz |
| $\Delta\nu$ | 레이저 선폭 (정적, Lorentzian FWHM) | Hz |
| $B$ | 주파수 스윕 대역폭 (excursion) | Hz |
| $T$ | 단방향 chirp 시간 (한 램프) | s |
| $\gamma = B/T$ | chirp rate (주파수 변화율) | Hz/s |
| $\tau$ | 광 지연 시간 (맥락에 따라 아래) | s |
| $\tau_{tgt}=2R/c$ | **타깃** 왕복 지연 (공기, $n\approx1$) | s |
| $\tau_{mzi}=n_g\Delta L/c$ | **기준 MZI** 단일통과 지연 (광섬유) | s |
| $n_g$ | 도파로/광섬유 group index ($\approx1.47$) | – |
| $\Delta L$ | MZI 두 팔의 광로차 | m |
| $f_b$ | 비트 주파수 | Hz |
| $R$ | 타깃 거리 | m |
| $L_c$ | coherence length | m |
| $c$ | 광속 ($3\times10^8$) | m/s |

**전 구간 관통 관계식:** 어떤 지연이든 $\boxed{f_b=\gamma\cdot\tau}$. 타깃이면 $\tau=\tau_{tgt}$, 기준 MZI면 $\tau=\tau_{mzi}$. 계수 2는 "왕복" 기하에서만 등장하는 값이지 보편 상수가 아니다.

---

# 1. 출발점 — 레이저 선폭과 결맞음 (왜 선형성과 결맞음이 둘 다 필요한가)

FMCW는 레이저의 **위상 결맞음**에 의존하는 간섭 측정이다. 따라서 모든 설계의 뿌리는 레이저 선폭 $\Delta\nu$이다.

## 1.1 정적 선폭과 coherence length

Lorentzian 선폭 $\Delta\nu$(FWHM)에 대한 결맞음 시간·길이:
$$\tau_c=\frac{1}{\pi\,\Delta\nu},\qquad L_c=\frac{c}{\pi\,n_g\,\Delta\nu}$$

- **물리적 의미:** $L_c$보다 긴 광로차를 만들면 두 빛이 더 이상 간섭하지 않는다 → 비트 신호가 사라진다. 이것이 §4의 $\Delta L$ 상한을 직접 규정한다.
- **관례 차이(C4):** 단순 근사 $L_c\approx c/\Delta\nu$(원본 General), Hauser 논문 관례 $L_c=2c\ln2/(\pi\Delta\nu)$ 등이 있으며 $O(1)$ 계수만 다르다.
  예) $\Delta\nu=2$ MHz(공기 $n\!\approx\!1$): $c/\Delta\nu=150$ m, $c/(\pi\Delta\nu)=47.7$ m, $2c\ln2/(\pi\Delta\nu)=66$ m. **본서는 $c/(\pi n_g\Delta\nu)$ 사용.**

## 1.2 동적 선폭 측정 — 지연 자기-헤테로다인(DSH)

스윕 중 레이저 품질은 **동적 선폭** $\Delta\nu_{dyn}$으로 평가한다. 비대칭 MZI로 자기 자신과 지연 간섭시키면($\tau=n_g\Delta L/c$), 비트노트의 퍼짐(FWHM $\Delta f_b$)으로 역산한다.

- **Case 1 — 비결맞음 영역 ($\tau\gg\tau_c$, 수 km 이상 광섬유):** ✅ 문헌 확인
  비트노트가 실제 선폭의 2배 폭 Lorentzian이 되므로
  $$\Delta\nu_{dyn}=\frac{\Delta f_b}{2}$$
  (근거: DSH 비트노트 = 동일 스펙트럼 2개의 자기상관 → Voigt, Lorentzian 성분을 2로 나눔.)

- **Case 2 — 결맞음/단지연 영역 ($\tau<\tau_c$):** ⚠️ 참고용 근사 (비표준)
  원본 OPLL_Basic이 제시한
  $$\Delta\nu_{dyn}\approx\frac{\pi\,n_g\,\Delta L\,(\Delta f_b)^2}{2\ln2\cdot c}\quad(\text{차원은 정합, 그러나 표준 유도 아님})$$
  은 **일반적으로 성립하지 않는다.** 단지연 영역에서 비트노트는 단일 Lorentzian이 아니라 **결맞음 포락선(중앙 δ-유사 피크 + 위상잡음 페데스탈 + 사이드로브)** 이며, 선폭 추출은 단순 FWHM이 아니라 **포락선 피팅**을 요한다. 이 프로젝트의 MZI는 $\tau\sim$수십 ns $\ll\tau_c\sim$수십 µs로 **결맞음 영역 깊숙이** 있어, 정적 선폭 자체는 이 셋업으로 잘 측정되지 않는다.

## 1.3 이 프로젝트에서 "동적 선폭"의 실제 의미 — 비선형성 확산

짧은 MZI 결맞음 영역에서 관측되는 비트노트 폭은 정적 선폭이 아니라 **스윕 비선형성**이 지배한다. Carson 대역 규칙(Schnuck 논문 식 5):
$$\Delta v=\frac{4\,(1+2\,f_{nl,rms})}{T}$$
여기서 $f_{nl,rms}$는 레이저 FM 비선형 성분의 rms. **비트노트 폭 = 거리 분해능 저하**이므로, "동적 선폭을 좁힌다 = 비선형성 $f_{nl,rms}$를 없앤다 = 본 EO-PLL의 목표"로 §2·§5와 직접 연결된다.

> **§1 → §2 연결:** 선폭은 (a) $L_c$로 최대 거리를, (b) 비선형 확산으로 거리 분해능을 제한한다. 이제 이상적 선형 chirp을 가정하고 FMCW 기본식을 세운 뒤(§2), 그 가정을 깨는 비선형성을 MZI로 측정(§3)·보정(§5)한다.

---

# 2. FMCW LiDAR 기본식 (이상적 선형 chirp 가정)

## 2.1 비트 주파수 — 거리 측정의 핵심
타깃 왕복 지연 $\tau_{tgt}=2R/c$를 관통식 $f_b=\gamma\tau$에 넣으면:
$$f_b=\frac{2\gamma R}{c}=\frac{2BR}{cT}$$
- 거리 $R$에 비례. **계수 2는 왕복(2R) 때문**이며, §3의 MZI 단일통과에는 없다(C2).
- 예) $\gamma=15$ THz/s, $R=300$ m → $f_b=30$ MHz.

## 2.2 거리 분해능 — 대역폭만이 결정
$$\Delta R=\frac{c}{2B}$$
- $T$·거리와 무관, 오직 $B$. 예) $B=1.5$ GHz → $\Delta R=10$ cm.
- **비선형성이 $f_b$를 퍼뜨리면(=§1.3 동적확산) 유효 $\Delta R$이 파괴된다** → 선형화 동기.

## 2.3 최대 비모호 거리
$$R_{max}=\frac{cT}{2}=\frac{c}{2f_{rep}}\qquad(f_{rep}=1/T)$$
추가로 ADC 제약: $f_{b,max}<f_s/2$ (Nyquist).

## 2.4 거리 정확도 (해상도 ≠ 정확도)
$$\delta R\approx\frac{c}{2B}\cdot\frac{1}{\sqrt{SNR}}\cdot\frac{1}{\sqrt{N}}$$
SNR·결맞음 누적 $N$이 높으면 정확도는 해상도보다 훨씬 좋아진다(µm급 가능).

## 2.5 속도 (Doppler)와 삼각파 분리
$$f_d=-\frac{2v}{\lambda}$$
단일 chirp은 거리-도플러 결합 → 삼각파 up/down 사용:
$$f_{b,up}=f_r-f_d,\quad f_{b,down}=f_r+f_d$$
$$\boxed{R=\frac{c}{4\gamma}(f_{b,up}+f_{b,down})},\qquad \boxed{v=\frac{\lambda}{4}(f_{b,down}-f_{b,up})}$$

## 2.6 속도 해상도·최대 속도
$$\Delta v=\frac{\lambda}{2T},\qquad v_{max}=\frac{\lambda}{4T}$$
거리-속도 불확정성: $T$를 늘리면 원거리↑·속도분해능↑이나 프레임레이트↓.

## 2.7 헤테로다인 SNR (shot-noise 한계)
$$SNR=\frac{\eta\,P_{sig}P_{LO}}{h\nu\cdot B_{elec}}$$
LO 혼합으로 약한 신호도 검출($B_{elec}\approx f_{b,max}$).

---

# 3. MZI — "광 주파수의 자(ruler)" 로 비선형성을 측정한다

§2가 "이상적 선형"을 가정했다면, 실제 반도체 레이저는 열효과·캐리어 동역학으로 $\gamma(t)$가 흔들린다. 이를 **실시간 측정**하는 센서가 기준 MZI다.

## 3.1 MZI 지연과 비트 주파수 (C2 핵심)
$$\tau_{mzi}=\frac{n_g\,\Delta L}{c}\qquad(\text{단일통과, 계수 2 없음})$$
$$\boxed{f_{b,mzi}(t)=\gamma(t)\cdot\tau_{mzi}}$$
- 선형 스윕($\gamma=\gamma_0$)이면 $f_{b,mzi}$는 순수 단일 톤. **비선형이면 $f_{b,mzi}(t)$가 흔들리고, 그 흔들림이 곧 비선형성의 실시간 척도.**
- 원본 정정(C2): 진공 왕복식 $\tau=2\Delta L/c$는 광섬유 단일통과에 부적합 → $n_g\Delta L/c$.
  예) $\Delta L=1$ m, $T=10$ ms, $f_b=37$ kHz, $n_g=1.47$: $\tau=4.9$ ns → $B=f_bT/\tau=75.5$ GHz.

## 3.2 출력 위상과 FSR
$$I_{mzi}(t)\propto\cos\!\Big(2\pi\tau_{mzi}\,\Delta f(t)\Big),\qquad FSR=\frac{1}{\tau_{mzi}}=\frac{c}{n_g\Delta L}$$
- FSR = 출력이 $2\pi$ 도는 동안의 광주파수 변화량. 피크 하나 지날 때마다 레이저가 정확히 FSR만큼 이동.
- **정정 예시(C1):** $\gamma=20$ THz/s, $n_g=1.5$, $\Delta L=1.5$ m → $\tau=7.5$ ns,
  $$f_{b,mzi}=20\times10^{12}\times7.5\times10^{-9}=1.5\times10^{5}=\mathbf{150\ kHz}\ \ (\text{원본 150 MHz는 오기})$$
  $$FSR=1/7.5\text{ns}=133.3\ \text{MHz}\ (\text{원본과 일치})$$

## 3.3 하드웨어의 진실 — 2×2 커플러와 BPD
- **2×2 방향성 커플러:** 소멸파 결합 시 물리적으로 $90^\circ$ 위상 지연 발생 → 두 출력이 역상.
  $$I_1\propto\tfrac12(1+\cos\Delta\phi),\qquad I_2\propto\tfrac12(1-\cos\Delta\phi)$$
  MZI는 한 파형을 쪼개는 게 아니라 **$180^\circ$ 역상 두 파형**을 출력.
- **BPD 전기적 뺄셈** $I_{out}=I_1-I_2$:
  - 신호 2배 증폭: $A\cos\omega t-(-A\cos\omega t)=2A\cos\omega t$
  - 공통 노이즈(레이저 세기 떨림·DC) 상쇄: $N-N=0$
  → 본 프로젝트 fixture의 BPD가 비교기 zero-crossing 타이밍 왜곡을 줄이는 이유(§5·control_block_design와 연결).

---

# 4. $\Delta L$ 설계의 삼중 제약 — 감도 vs 결맞음 vs 안정성

$\Delta L$ 하나가 광학 감도, 결맞음, 제어 안정성을 동시에 지배한다. **§1의 $L_c$가 여기서 상한으로 되돌아온다.**

## 4.1 [감도] 길수록 오차가 증폭된다
주파수 오차가 $A\sin\omega t$일 때 MZI 비트 오차:
$$\Delta f_b=A\sin\omega t-A\sin\omega(t-\tau)\approx A\,\omega\,\tau$$
지연 $\tau\propto\Delta L$에 비례해 에러가 증폭 → 노이즈 플로어 위로 끌어올리려면 $\Delta L$이 길수록 유리.

## 4.2 [결맞음] $\Delta L<L_c$ (§1의 회귀)
$\Delta L$이 $L_c$를 넘으면 간섭 자체가 사라진다(§1.1). → **감도를 위해 늘리되 결맞음 한계 안에서.**

## 4.3 [안정성] 루프 지연이 발진을 부른다
OPLL은 오차를 측정해 실시간 교정하므로 $\tau$가 순수 지연 $e^{-s\tau}$로 작용해 위상여유를 깎는다. 안정성 황금률:
$$\boxed{\tau\cdot BW_{loop}\le0.1}\iff 10\tau\le\frac{1}{BW_{loop}}$$
제어 정착시간 $1/BW$이 물리 지연 $\tau$의 **최소 10배**여야 발진을 막는다.
- **스케일 감각:** $\Delta L=10$ m → $\tau\approx50$ ns → $BW\le2$ MHz → 정착 $0.5\ \mu$s. 느긋하게 잡아도 초당 200만 회 교정하는 초고속 루프.

## 4.4 최적 $\Delta L$ 스위트 스팟 (예: $B=55$ GHz, $T=10$ ms)
$\gamma=5.5\times10^{12}$ Hz/s, $n_g=1.47$.
- **Step 1 (안정성 상한):** $BW=50$ kHz 가정 → $\tau\le2\ \mu$s → $\Delta L_{max}=\tau c/n_g\approx\mathbf{408\ m}$ (절대 한계).
- **Step 2 ($f_b$ 타깃):** $\Delta L=c\,f_b/(\gamma n_g)$, $c/(\gamma n_g)\approx3.71\times10^{-5}$ m/Hz.
  - $f_b=50$ kHz → $\Delta L\approx1.85$ m
  - $f_b=500$ kHz → $\Delta L\approx18.5$ m
- **Step 3 (결론):** $\Delta L\approx\mathbf{5\sim20\ m}$ ($f_b\approx130\sim540$ kHz)가 감도·안정성 최적 구간.

> **본 프로젝트 정합성 점검:** 목표 beat $\le20$ MHz, TDC dead time 15 ns. §4.4의 $f_b$ 대(수백 kHz)와 §3.2 정정치(150 kHz)는 모두 20 MHz 한계 내 → 설계 일관성 확인. (control_block_design §1의 $T_b\ge50$ ns와도 정합)

---

# 5. 선형화 — 세 가지 접근과 EO-PLL

측정된 비선형성을 없애는 방법은 셋이다.

## 5.1 반복 사전왜곡 (Iterative Pre-distortion)
$$i_{n+1}(t)=i_n(t)-K\big[f_{b,mzi}(t)-f_{target}\big],\qquad f_{target}=\gamma_{ideal}\,\tau_{mzi}$$
측정 비트가 목표보다 높으면 전류 기울기를 낮추는 chirp-간 학습. (개루프, 환경변화에 취약)

## 5.2 EO-PLL / OPLL (실시간 폐루프)
$$e(t)=\phi_{mzi}(t)-\phi_{ref}(t)\ \Rightarrow\ \text{제어기}\ \Rightarrow\ \text{레이저 전류/전압}$$
MZI 위상을 완벽히 선형인 RF 기준과 비교, $e(t)\to0$으로 실시간 폐루프 제어. **본 프로젝트의 경로.**

## 5.3 K-clock 리샘플링 (신호처리 보정)
레이저는 비선형인 채 두고, 보조 MZI 비트의 zero-crossing/peak를 ADC 클럭으로 사용:
$$t_k:\ \int_0^{t_k}f_{b,mzi}(t)\,dt=k\cdot\text{const}\ \Rightarrow\ S_{lin}[k]=S_{tgt}(t_k)$$
"시간 등간격"이 아니라 "광주파수 등간격(FSR마다)"으로 샘플 → 수학적으로 완벽한 선형 chirp 데이터.

## 5.4 본 프로젝트로의 연결
- 본 EO-PLL은 §5.2를 택하되, TDC로 위상오차 $e(n)$를 ps급으로 측정한다 (control_block_design §1):
  $$e(n)=t_n-T_n,\quad \nu_{nl}(t_n)=-\gamma\,e(n)$$
  이는 §3.1의 $f_{b,mzi}=\gamma\tau$를 **시간 도메인에서 미분 역변환**한 것 — MZI가 준 주파수 정보를 TDC가 손실 없이 시간축으로 옮긴다.
- 안정성 황금률 §4.3 $\tau\cdot BW\le0.1$은 control_block_design의 루프지연 보상 $D_{edge}$·칼만 대역 제한의 물리적 근거.
- §1.3의 비선형 확산 $f_{nl,rms}$를 없애는 것이 최종 성능지표(잔류 $\nu_{nl,rms}$, $1-r^2$, beat FWHM).

---

## 부록 A. 원본 대비 수식 교차검증 표

| 물리량 | 통합본 (통일 표기) | 원본 출처 | 검증 |
|---|---|---|---|
| 관통 관계 | $f_b=\gamma\tau$ | General/OPLL 공통 | ✅ 두 문서 동일 골격 |
| 타깃 비트 | $f_b=2\gamma R/c$ | General §2(1) | ✅ ($\tau_{tgt}=2R/c$) |
| MZI 비트 | $f_{b,mzi}=\gamma\,n_g\Delta L/c$ | OPLL §2(2), Basic §2 | ✅ (단일통과) |
| 거리 분해능 | $\Delta R=c/2B$ | General §2(2) | ✅ |
| FSR | $c/(n_g\Delta L)$ | OPLL §3, Basic §2 | ✅ |
| DSH Case 1 | $\Delta\nu=\Delta f_b/2$ | Basic §1.2 | ✅ 문헌 확인 |
| DSH Case 2 | (비표준 근사) | Basic §1.2 | ⚠️ 참고용, §1.3로 대체 |
| 안정성 | $\tau\,BW\le0.1$ | Basic §5 | ✅ 제어공학 관례 |
| MZI 예시 $f_b$ | **150 kHz** | OPLL §1 예시 | 🔧 원본 150 MHz 정정 |

## 부록 B. 참고 문헌 (검증에 사용)
- DSH 비결맞음 영역 FWHM=2×선폭: [Optica OE 14-9-3923](https://opg.optica.org/oe/fulltext.cfm?uri=oe-14-9-3923&id=89596), [MDPI Sensors 11-10-9233](https://www.mdpi.com/1424-8220/11/10/9233)
- 단지연 결맞음 영역 포락선/한계: [Optica AO 61-13-3761](https://opg.optica.org/ao/abstract.cfm?uri=ao-61-13-3761), [NCBI PMC9416656](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9416656/)
- 프로젝트 1차 문헌: Hauser & Hofbauer 2022 (IEEE Photonics J.), Schnuck et al. 2025 (Appl. Phys. B) — `Paper/` 폴더
