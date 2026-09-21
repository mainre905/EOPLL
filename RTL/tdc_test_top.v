`timescale 1ns / 1ps

module tdc_test_top #(
    // ==========================================================
    // 0 : Hit = Test Sync(내부)  | Clock = Shifted 200MHz (MMCM 캘리브레이션용)
    // 1 : Hit = Ring Osc(랜덤)   | Clock = Fixed 200MHz  (기본 동작 및 탭 누적 테스트용)
    // 2 : Hit = 외부 LVDS 비교기 | Clock = Fixed 200MHz  (실제 측정용)
    //     ★ 2026-09-15 : "외부 STM32 신호" -> "외부 LVDS 비교기". PMOD 단선(STM32) 입력 삭제에 맞춘 주석 수정.
    //       (OPERATION_MODE 1/2 는 지금 같은 하드웨어이고 RO/LVDS 는 CTRL[1:0] 로 런타임 선택 — 아래 §3)
    // ==========================================================
    parameter integer OPERATION_MODE = 1,

    // ★ [2026-09-03 추가] 캐리체인 단수 (탭 수 = CARRY4_STAGES x 4)
    //   ZedBoard 는 tdc_zedboard_top.v 에서 96단(384탭)으로 넘긴다. 이유는
    //   tdc_fmcw_core_co.v 상단의 ★ 2026-09-03 주석 참조.
    //   기본값 80단(320탭)은 옛 Zybo 빌드용이었다. Zybo 는 2026-09-04 부로 사용
    //   중단했으므로 지금 실제로 쓰이는 값은 96단뿐이다.
    //   ※ 16의 배수여야 popcount 트리가 4x(N/16)x16 으로 떨어진다 (80, 96, 112 ...).
    //   ※ 448 초과 금지 — sum_fine/ts_fine_idx 가 [8:0](<=511) 이고 히스토그램이 512칸이다.
    parameter integer CARRY4_STAGES  = 80
)(
    input  wire       clk_125, 
    input  wire       rst_n, 
    input  wire       btn_shift,   
    input  wire       ext_hit_in,  
    output wire [3:0] led,

    // ★ [2026-09-04 추가] AXI 레지스터 블록이 볼 TDC 도메인 신호들.
    //   tdc_axi_regs 가 이 신호들을 AXI 도메인으로 동기화해 PS 에 보여준다.
    //   3단계에서 시퀀서가 붙으면 busy/done 도 여기로 나온다.
    output wire       o_tdc_clk,      // clk_200_fixed — AXI 레지스터의 TDC 도메인 클럭
    output wire       o_locked,       // MMCM lock
    output wire [30:0] o_dna,         // 보드 식별자 (31비트)
    output wire       o_dna_valid,
    output wire       o_phase_busy,   // 위상 이동 중

    // ★ [2026-09-05 추가 — AXI 2단계] 측정 조건과 위상 제어
    output wire        o_meas_strobe, // 10 ms 게이트마다 1클럭. RO/온도 갱신 완료
    output wire [31:0] o_ro_cnt,      // 게이트당 RO 에지 수
    output wire [15:0] o_die_temp,    // XADC 온도 raw
    output wire [8:0]  o_phase_cur,   // 현재 위상 스텝 (0..279)
    input  wire [8:0]  i_phase_tgt,   // 목표 위상 — BTNU 임시 블록을 대체한다
    input  wire        i_histo_clr,   // 히스토그램 지우기 (레벨, 소프트웨어 수동)

    // ★ [2026-09-05 추가 — AXI 3단계] 시퀀서 FSM
    //   CTRL.START 하나로 "RO 켜기 -> 주파수 재기 -> 안정화 -> 누적 -> 완료"가
    //   자동으로 돈다. 상세는 RTL/tdc_seq.v 헤더 참조.
    input  wire        i_ctrl_start,
    input  wire        i_ctrl_stop,
    input  wire [1:0]  i_ctrl_hit_src,
    input  wire        i_ctrl_cap_fmt,   // 0=timestamp_ps  1=raw{coarse,fine}
    input  wire [31:0] i_target_hits,
    input  wire [31:0] i_settle_n,
    input  wire [8:0]  i_danger_lo,   // ★ 2026-09-05 : 상수 -> 레지스터
    input  wire [8:0]  i_danger_hi,
    // ★ 2026-09-16 : Mode 0 확인(내부 루프백)용 히트 생성기 주기 [tdc_clk 클럭 수], 0 = 정지
    input  wire [15:0] i_m0_period,
    output wire        o_busy,
    output wire        o_done,
    output wire [2:0]  o_state,
    output wire [31:0] o_hit_cnt,     // 실제 누적된 히트 수 (384탭 합과 같아야 함)
    output wire [31:0] o_drop_cnt,    // 데드타임에 버려진 히트 수
    output wire [31:0] o_ro_start,
    output wire [31:0] o_ro_end,
    output wire [15:0] o_temp_start,
    output wire [15:0] o_temp_end,
    output wire        o_snap_tgl,    // 위 값들의 CDC 토글

    // ★ [2026-09-05 추가] 히스토그램 BRAM Port B — 전부 AXI 클럭 도메인이다.
    //   ILA 리드아웃 스캐너를 걷어내고 그 자리를 AXI 가 받는다.
    input  wire        i_axi_clk,
    input  wire [8:0]  i_histo_addr,
    output wire [31:0] o_histo_data,

    // ★ [2026-09-05 추가] 캡처 버퍼 (Mode 2 = 외부 LVDS 실측)
    input  wire [12:0] i_cap_n,        // 이만큼 모으면 끝낸다 (최대 4096)
    output wire [12:0] o_cap_cnt,      // 지금까지 모인 수
    input  wire [11:0] i_cap_addr,     // 읽기 주소 (AXI 도메인)
    input  wire        i_cap_hi,       // 0=하위 워드 1=상위 워드
    output wire [31:0] o_cap_data,

    // ★ 2026-09-15 추가 : 교정표 RAM (i_axi_clk 도메인). tdc_timestamp_calc 안 tdc_calib_ram 의 Port A 로 간다.
    input  wire        i_cal_we,
    input  wire [8:0]  i_cal_addr,
    input  wire [12:0] i_cal_din,
    output wire [12:0] o_cal_dout
);


    // ★ [2026-09-03 추가] 탭 수 — 히스토그램 리드아웃 스캔 범위에 쓴다.
    //   히스토그램 BRAM 은 512칸(tdc_bram_512x32)이므로 448탭까지 그대로 담긴다.
    localparam integer NUM_TAPS = CARRY4_STAGES * 4;

    // ★ 2026-09-05 : 시퀀서(tdc_seq)와 주고받는 신호. 인스턴스는 §6 아래에 있다.
    wire        seq_ro_en, seq_histo_en, seq_histo_clr;
    wire        histo_hit_accepted, histo_hit_dropped;
    wire        seq_cap_en, seq_cap_clr;
    wire        cap_full, cap_written, cap_lost;

    // ==========================================
    // 1. Clock Generation & MMCM Phase Shifter
    // ==========================================
    wire clk_200_fixed, clk_200_shifted, clk_locked;
    wire psen, psincdec, psdone, ps_busy; 
    wire [8:0] current_loop_cnt; 
    wire loop_updated_toggle; // ★ 2026-08-19 추가: 1단 CDC용 토글 와이어

    // ==========================================================
    // ★ 2026-08-20 추가 — Device DNA(칩 고유 ID) 보드 식별자
    //
    //  왜: Zybo 보드가 2대(회사/집)인데 캡처 CSV에 어느 보드인지 기록이 없었다.
    //      두 칩은 공정 편차로 지연선이 다르다 — 실측:
    //        집  보드  유효탭 299  LSB 16.722 ps  (8/04, 8/09, 8/12, 8/13)
    //        회사 보드  유효탭 284  LSB 17.606 ps  (8/06 온도셋, 8/20)
    //        같은 칩끼리 탭 폭 상관 r=0.999 (빌드가 달라도), 다른 칩끼리 r=0.54
    //      CARRY4 와 FF 이 tdc.xdc 로 같은 슬라이스에 고정돼 있어 탭 폭은 그
    //      슬라이스의 실리콘이 정한다. 보드가 바뀌면 지연선이 바뀐다.
    //      이 값을 ILA 에 찍어 모든 캡처에 보드 식별자를 영구히 남긴다.
    //      상세는 RTL/dna_reader.v 헤더 참조.
    // ==========================================================
    wire [56:0] device_dna;
    wire        device_dna_valid;

    dna_reader #(
        .CLK_DIV (16)                 // 200 MHz / 16 = 12.5 MHz (보수적)
    ) u_dna (
        .clk       (clk_200_fixed),
        .rst_n     (clk_locked),
        .dna       (device_dna),
        .dna_valid (device_dna_valid)
    );

    clk_wiz_0 u_clk (
        .clk_in1  (clk_125), 
        .reset    (rst_n),  
        .clk_out1 (clk_200_fixed), 
        .clk_out2 (clk_200_shifted), 
        .psclk    (clk_200_fixed), 
        .psen     (psen), 
        .psincdec (psincdec), 
        .psdone   (psdone), 
        .locked   (clk_locked)
    );
    
    // ==========================================================
    // ★ [2026-09-04] phase_shifter 가 "목표 위상으로 이동" 방식으로 바뀌었다.
    //   (기존: start_shift 한 번에 280스텝 자동 스윕 -> 변경: phase_tgt 로 이동)
    //   이유와 상세는 RTL/phase_shifter.v 상단 주석 참조.
    //
    //   ★ [2026-09-05] BTNU 임시 구동부를 걷어냈다.
    //   무엇이 있었나 : 버튼(btn_shift)을 누를 때마다 목표 위상을 한 칸 올리는
    //     phase_tgt_reg 블록이 있었다. 그 목적은 위상 이동이 아니라, 그로 인해
    //     생기는 ps_busy 하강 에지로 ILA 히스토그램 리드아웃을 띄우는 것이었다.
    //   왜 없앴나 : 히스토그램을 AXI 로 직접 읽게 되어 리드아웃 스캐너 자체가
    //     사라졌다. 그러자 버튼도 함께 필요 없어졌다. 실제로 2026-09-05 측정에서
    //     이 버튼을 안 눌러 빈 CSV 를 받은 일이 있었다 — 사람 손이 측정 절차에
    //     끼어 있던 것이 문제였다.
    //   지금은 PS 가 PHASE 레지스터(0x1C)에 목표 위상을 쓰면 그대로 이동한다.
    //     스윕이 필요하면 PS 쪽 for 문이 한다.
    // ==========================================================
    mmcm_phase_shifter u_ps_ctrl (
        .clk                 (clk_200_fixed),
        .rst_n               (clk_locked),
        .phase_tgt           (i_phase_tgt),     // ★ 2026-09-05 : AXI PHASE 레지스터
        .psen                (psen), 
        .psincdec            (psincdec), 
        .psdone              (psdone), 
        .busy                (ps_busy), 
        .phase_cur           (current_loop_cnt),// ★ 2026-09-04 : 포트명 loop_cnt -> phase_cur
        .loop_updated_toggle (loop_updated_toggle) // ★ 2026-08-19 추가
    );

    // [Mode 0용] Calibration Test Hit Sync
    reg [15:0] sync_cnt; 
    reg test_hit_sync;
    always @(posedge clk_200_fixed) begin 
        if (!clk_locked) begin 
            sync_cnt <= 0; test_hit_sync <= 0; 
        end else begin 
            if (sync_cnt == 16'd9) sync_cnt <= 0; 
            else sync_cnt <= sync_cnt + 1; 

            if (sync_cnt < 16'd2) test_hit_sync <= 1'b1; 
            else test_hit_sync <= 1'b0;
        end 
    end

    // ==========================================
    // 2. Ring Oscillator (Mode 1용)
    // ==========================================
    // ★ 2026-09-05 : RO 를 시퀀서가 껐다 켠다.
    //   [무엇이 있었나] ro_enable_reg <= clk_locked (clk_125 도메인).
    //     즉 MMCM 이 잠기는 순간 발진을 시작해 그 뒤로 영영 멈추지 않았다.
    //     끄는 조건이 아예 없었다.
    //   [왜 바꾸나] FSM 의 S_RO_ENABLE 이 의미를 가지려면 실제로 껐다 켤 수
    //     있어야 한다. LUT2(INIT=4'h7 = NAND)가 게이트라, ro_enable_reg=0 이면
    //     출력이 상수 1 이 되어 고리가 끊긴다.
    //   [따라오는 것] RO 가 꺼지면 ro_clk_buffered 가 아예 멈추고 ro_divider_cnt
    //     가 얼어붙는다. 다시 켜면 얼었던 자리에서 이어 센다. 코드밀도에는
    //     무관하다(히트 위상이 무작위이기만 하면 된다).
    //   [도메인] clk_125(=FCLK 100 MHz) -> tdc_clk(200 MHz) 로 옮겼다.
    //     FSM 이 tdc_clk 에 살기 때문이다. 원래 clk_125 였던 이유는 코드에
    //     적혀 있지 않고, 단일 비트 레벨이라 어느 쪽이든 동작에 문제없다.
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) reg ro_enable_reg = 1'b0;
    always @(posedge clk_200_fixed) ro_enable_reg <= clk_locked & seq_ro_en;

    (* ALLOW_COMBINATORIAL_LOOPS = "TRUE", KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [30:0] ro_chain;
    genvar r; generate 
        for(r=0; r<30; r=r+1) begin : RO_LOOP 
            (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) LUT1 #(.INIT(2'h1)) u_lut_inv (.I0(ro_chain[r]), .O(ro_chain[r+1])); 
        end 
    endgenerate
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) LUT2 #(.INIT(4'h7)) u_lut_inv_fb (.I0(ro_chain[30]), .I1(ro_enable_reg), .O(ro_chain[0]));

    wire ro_clk_buffered; 
    BUFG u_bufg_ro (.I(ro_chain[30]), .O(ro_clk_buffered));
    
    (* DONT_TOUCH = "TRUE" *) reg [15:0] ro_divider_cnt = 0; 
    always @(posedge ro_clk_buffered) ro_divider_cnt <= ro_divider_cnt + 1'b1;

    // ★ 2026-09-15 : hit_random 을 고정 64 분주에서 LFSR 난수 분주로 바꿨다 (사용자 승인).
    //   [무엇이 문제였나] 히트 간격 / 클럭 주기 r = 64 x T_RO / 5 ns 가 정수 근처면 히트가 매번
    //     클럭의 거의 같은 위상에 떨어져 코드밀도(위상이 고르게 퍼져야 성립)가 깨진다.
    //     zed_ro 보드 측정(RO_CNT 201259 -> 201212)에서 r = 32e6/RO_CNT 가 158.9992 -> 159.0363 으로
    //     측정 도중 정확히 159 를 지나갔다. 온도가 오르며 159.09~159.14 로 멀어졌다(8 초 폴링).
    //     모델(가정: r 이 정확히 159 로 고정, RO 지터 0.5 ps/주기) : 고정 분주는 위상 칸 흔들림
    //     RMS 44.7 %, 난수 분주는 1.37 % (계수 통계만이면 1.26 %).
    //   [고정 분주비를 바꾸면 안 되나] RO 주파수가 온도로 움직여 어떤 N 이든 어느 온도에서는 다시
    //     정수 근처에 온다. 쓸 수 있던 2 의 거듭제곱(32 -> r=79.50, 128 -> 318.01)은 오히려 나쁘다.
    //   [무엇을 했나] 반주기마다 N = 16 + LFSR[4:0] (16..47) RO 주기를 센 뒤 hit 를 뒤집는다.
    //     상승 간격 = N1 + N2 (32..94 주기). xsim 시험(2 만 발, 12.422 ns) : 최소 397.5 ns, 평균 777.6 ns
    //     (고정 64 분주 795.0 ns 와 비슷), 가능한 간격 63 개 중 62 개가 나옴.
    //     재측정 금지 2 사이클(10 ns, tdc_fmcw_core_co.v:234)보다 최소 간격이 훨씬 길다.
    //   [한계] RO 지터가 0 이고 RO 주기 자체가 클럭에 잠기면(주입 잠김) 이것으로도 안 된다.
    //     그때는 RO_CNT 가 두 값에만 붙으므로 따로 알아볼 수 있다.
    //   [안 바뀌는 것] RO 주파수 측정은 ro_divider_cnt[1] 을 그대로 쓴다. RO 가 꺼지면(ro_enable=0)
    //     ro_clk_buffered 가 멈춰 이 발생기도 멈춘다 — 예전 64 분주와 같다.
    (* DONT_TOUCH = "TRUE" *) reg [15:0] hd_lfsr = 16'hACE1;   // Galois x^16+x^14+x^13+x^11+1, 주기 65535
    (* DONT_TOUCH = "TRUE" *) reg [5:0]  hd_cnt  = 6'd16;
    (* DONT_TOUCH = "TRUE" *) reg        hd_q    = 1'b0;
    always @(posedge ro_clk_buffered) begin
        hd_lfsr <= hd_lfsr[0] ? ((hd_lfsr >> 1) ^ 16'hB400) : (hd_lfsr >> 1);
        if (hd_cnt == 6'd1) begin
            hd_q   <= ~hd_q;
            hd_cnt <= 6'd16 + {1'b0, hd_lfsr[4:0]};
        end else begin
            hd_cnt <= hd_cnt - 1'b1;
        end
    end
    wire hit_random = hd_q;
    
    
    // ==========================================================
    // ★ RO 주파수 카운터 — 2026-07-24 수정 (원본: 1초 게이트, ÷64 탭)
    // ==========================================================
    //  [변경1] 게이트 1s -> 10ms.
    //     이유: injection lock 판정은 평균이 아니라 '변동'으로 해야 한다.
    //           잠긴 RO는 매번 정확히 같은 값이 나오고, 자유발진 RO는 흔들린다.
    //           1s 게이트는 ILA 한 캡처(=5us 창)에 값이 1개뿐이라 변동을
    //           볼 수 없었다. 10ms면 storage qualification으로 1024샘플
    //           = 10.24초 이력을 한 번에 확보한다.
    //     주의: code density에는 이 '흔들림'이 오히려 필수다. RO가 드리프트해야
    //           hit이 클럭 주기 전 위상을 고르게 훑는다.
    //  [변경2] 측정 탭 ro_divider_cnt[5](÷64) -> [1](÷4).
    //     이유: hit_random([5])은 TDC 데드타임(~15ns) 확보용이라 그대로 두고,
    //           주파수 카운터만 별도 탭을 쓴다. 같은 게이트에서 카운트 16배
    //           -> 분해능 16배. Nyquist: f_RO=40MHz 가정 시 탭 주파수 10MHz,
    //           200MHz 샘플링으로 주기당 20샘플이라 여유 충분.
    //  [변경3] gate_tick과 에지가 같은 사이클에 겹치면 그 에지가 유실되던 버그
    //           수정 (원본은 카운터를 무조건 0으로 리셋했음).
    //  [변경4] meas_strobe 추가 — ILA storage qualification용.
    //           gate_tick 시점에 캡처하면 '갱신 전' 값이 잡히므로 1클럭 지연.
    // ==========================================================
    localparam integer GATE_CYCLES = 2_000_000;  // 10 ms @ 200MHz
    localparam integer RO_MEAS_TAP = 1;          // ro_divider_cnt 탭 (÷4)

    reg [20:0] gate_cnt  = 0;
    reg        gate_tick = 0;
    always @(posedge clk_200_fixed) begin
        if (gate_cnt == GATE_CYCLES-1) begin
            gate_cnt  <= 0;
            gate_tick <= 1'b1;
        end else begin
            gate_cnt  <= gate_cnt + 1'b1;
            gate_tick <= 1'b0;
        end
    end

    // RO(비동기) -> 200MHz 도메인 동기화. ASYNC_REG로 배치 밀착 유도(MTBF 확보).
    wire ro_meas_tap = ro_divider_cnt[RO_MEAS_TAP];
    (* ASYNC_REG = "TRUE" *) reg ro_sync_d1 = 0;
    (* ASYNC_REG = "TRUE" *) reg ro_sync_d2 = 0;
    reg ro_sync_d3 = 0;
    always @(posedge clk_200_fixed) begin
        ro_sync_d1 <= ro_meas_tap;
        ro_sync_d2 <= ro_sync_d1;   // 메타스테빌리티 해소
        ro_sync_d3 <= ro_sync_d2;   // 에지 검출용 1클럭 추가 지연
    end
    wire ro_edge = (ro_sync_d2 && !ro_sync_d3);

    reg [31:0] ro_edge_cnt  = 0;
    (* mark_debug = "true" *) reg [31:0] ro_meas_cnt = 0;  // 게이트(10ms)당 에지 수
    reg        meas_strobe  = 0;

    always @(posedge clk_200_fixed) begin
        if (gate_tick) begin
            ro_meas_cnt <= ro_edge_cnt;
            ro_edge_cnt <= ro_edge ? 32'd1 : 32'd0;  // [변경3] 겹침 시 유실 방지
        end else if (ro_edge) begin
            ro_edge_cnt <= ro_edge_cnt + 1'b1;
        end
        meas_strobe <= gate_tick;                    // [변경4] 갱신 확정 사이클
    end

    // ==========================================================
    // ★ XADC 다이 온도 — 2026-07-24 신규
    // ==========================================================
    //  목적: RO 주파수와 온도의 상관을 '동시 캡처'로 확인하기 위함.
    //        (기존에는 Hardware Manager의 System Monitor를 눈으로 읽어
    //         ILA 값과 손으로 짝지어야 해서 동시성이 없었다.)
    //  동작: 변환 완료(eoc) -> DRP 주소 0x00(온도) 1회 읽기 -> drdy에 래치.
    //  환산: Temp[C] = (do_out[15:4] * 503.975 / 4096) - 273.15
    //        (12비트 결과가 16비트 레지스터의 상위에 정렬되어 있음)
    //  gate_tick에 함께 래치해 ro_meas_cnt와 시점을 명시적으로 맞춘다.
    // ==========================================================
    wire        xadc_eoc, xadc_drdy;
    wire [15:0] xadc_do;
    reg         xadc_den      = 1'b0;
    reg [15:0]  die_temp_raw  = 16'd0;
    (* mark_debug = "true" *) reg [15:0] die_temp_at_meas = 16'd0;

    always @(posedge clk_200_fixed) begin
        xadc_den <= 1'b0;                       // 기본 0, eoc에서만 1클럭 펄스
        if (xadc_eoc)  xadc_den     <= 1'b1;
        if (xadc_drdy) die_temp_raw <= xadc_do;
        if (gate_tick) die_temp_at_meas <= die_temp_raw;  // 주파수와 시점 정렬
    end

    xadc_wiz_0 u_xadc (
        .daddr_in    (7'h00),          // 0x00 = on-chip temperature
        .dclk_in     (clk_200_fixed),
        .den_in      (xadc_den),
        .di_in       (16'h0000),
        .dwe_in      (1'b0),
        .do_out      (xadc_do),
        .drdy_out    (xadc_drdy),
        .reset_in    (1'b0),
        .vp_in       (1'b0),
        .vn_in       (1'b0),
        .busy_out    (),
        .channel_out (),
        .eoc_out     (xadc_eoc),
        .eos_out     (),
        .alarm_out   ()
    );

    // ==========================================
    // 3. 하드코딩된 모드 선택 제너레이터
    // ==========================================
    wire tdc_hit_in;
    wire tdc_clk;

    // ==========================================
    // 3-B. ★ 2026-09-16 : Mode 0 확인용 히트 생성기 (내부 루프백)
    // ==========================================
    //  [무엇을 하나] clk_200_shifted 에서 일정 주기의 사각파를 만든다. 코어는 히트의
    //    '하강 에지'에서 측정하므로(tdc_fmcw_core_co.v:267), 하강 에지 간격 = i_m0_period
    //    클럭 = i_m0_period x 5000 ps 가 '아는 시간' 이 된다.
    //  [왜 clk_200_shifted 인가] 이 클럭은 MMCM 동적 위상 시프트가 걸려 있어 AXI PHASE
    //    레지스터로 17.857 ps(= VCO 1000 MHz 주기의 1/56) 단위로 움직일 수 있다. 히트를
    //    그 위상에서 만들고 샘플링은 clk_200_fixed 로 두면, 위상 한 스텝마다 측정 시각이
    //    17.857 ps 씩 움직여야 한다 — 교정표가 맞는지 이걸로 본다.
    //  [검증 범위] 간격과 선형성만 본다. 절대 시각(원점)과 클럭의 ppm 오차는 못 본다.
    //  [주의] 2026-08-03 보고서 §11-3 은 '클럭 대신 히트를 미는' 구조를 폐기했는데, 그것은
    //    온도 의존성을 재는 기준자로 쓸 수 없다는 뜻이었다. 한 온도에서 시간 간격이 맞는지
    //    보는 이 용도에는 유효하다. 다만 측정된 산포에는 이 경로의 지터가 섞인다.
    //  [CDC] 두 클럭은 같은 MMCM 에서 나오고 XDC 가 logically_exclusive 로 묶어 두었다.
    //    주기·모드 값은 거의 바뀌지 않으므로 2FF 로 받는다.
    (* ASYNC_REG = "TRUE" *) reg [15:0] m0_per_d1 = 16'd0, m0_per_d2 = 16'd0;
    (* ASYNC_REG = "TRUE" *) reg [1:0]  m0_src_d1 = 2'd0,  m0_src_d2 = 2'd0;
    //  ★ 2026-09-16 (2차) : 아래 세 값을 한 단 미리 계산해 둔다.
    //    [무엇이 문제였나] 처음에는 카운터 분기 안에서 바로 계산했다 :
    //        if ((m0_src_d2 != 2'b10) || (m0_per_d2 < 8)) ... else if (m0_cnt >= m0_per_d2 - 1)
    //      16비트 뺄셈 -> 16비트 비교 -> OR 결과가 카운터 16비트의 리셋 핀을 구동해
    //      한 사이클에 논리 7단이 쌓였다. 실측(zed_m0, 2026-09-16) :
    //        m0_per_d2_reg[2]/C -> m0_cnt_reg[*]/R, 데이터 지연 4.868 ns, WNS -0.393 ns.
    //    [어떻게 고쳤나] 뺄셈·시프트·모드 판정을 앞 단 레지스터로 옮겨, 카운터 경로에는
    //      등록된 값과의 비교 하나만 남긴다. 주기는 측정 사이에만 바뀌므로 한 클럭 늦게
    //      반영돼도 무해하다. 같은 수법을 tdc_seq.v 가 remain_last 로 이미 쓰고 있다.
    reg [15:0] m0_per_m1 = 16'd0;   // 주기 - 1
    reg [15:0] m0_per_hf = 16'd0;   // 주기 / 2  (여기서 하강 = 측정 시점)
    reg        m0_run    = 1'b0;    // 가동 조건 : HIT_SRC=10 이고 주기 >= 8클럭
    reg [15:0] m0_cnt = 16'd0;
    reg        m0_hit = 1'b0;
    always @(posedge clk_200_shifted) begin
        m0_per_d1 <= i_m0_period;      m0_per_d2 <= m0_per_d1;
        m0_src_d1 <= i_ctrl_hit_src;   m0_src_d2 <= m0_src_d1;

        m0_per_m1 <= m0_per_d2 - 16'd1;
        m0_per_hf <= {1'b0, m0_per_d2[15:1]};
        // 최소 8클럭(40 ns)은 두어 코어 데드타임(2클럭)과 파이프라인을 넘긴다.
        m0_run    <= (m0_src_d2 == 2'b10) && (m0_per_d2 >= 16'd8);

        if (!m0_run) begin
            m0_cnt <= 16'd0;
            m0_hit <= 1'b0;
        end else if (m0_cnt >= m0_per_m1) begin
            m0_cnt <= 16'd0;
            m0_hit <= 1'b1;                   // 주기 시작에서 상승
        end else begin
            m0_cnt <= m0_cnt + 16'd1;
            m0_hit <= (m0_cnt < m0_per_hf);   // 절반 지점에서 하강 = 측정 시점
        end
    end

    // ★ 2026-09-05 : Mode 1(RO)과 Mode 2(EXT)는 히트 소스를 런타임에 고른다.
    //   [왜 되나] 두 모드는 샘플링 클럭이 똑같이 clk_200_fixed 다. 클럭이 같으니
    //     고를 것은 데이터 한 줄(히트 네트)뿐이고, 그건 그냥 먹스다. 비트스트림
    //     하나로 두 모드를 쓴다.
    //   [왜 Mode 0 은 안 되나] DPS 는 clk_200_shifted 로 샘플링한다. 런타임에
    //     고르려면 지연선의 샘플링 클럭에 BUFGMUX 를 달아야 하는데, 그러면 탭 폭이
    //     흔들릴 위험이 있다. 대신 "클럭 대신 히트를 흔드는" 재설계를 따로 할 것.
    //     그때까지 Mode 0 은 OPERATION_MODE=0 으로 빌드해야 한다.
    //
    //   ★ 히트 네트에 먹스가 붙는 것 자체는 괜찮은가 :
    //     hit 은 CYINIT 만 구동해야 한다는 규칙(led[2] 사례)은 '팬아웃'에 관한
    //     것이지 '앞단 로직'에 관한 것이 아니다. 먹스는 hit 앞에 있고 출력은
    //     여전히 CYINIT 하나만 구동한다. 다만 먹스 LUT 이 끼면서 에지 slew 가
    //     달라질 수 있으므로, 이번 빌드의 히스토그램 모양을 2026-09-05 3단계
    //     결과와 대조해 진입 트랜지언트가 나빠지지 않았는지 확인할 것.
    generate
        if (OPERATION_MODE == 0) begin : MODE_0_MMCM_SWEEP
            assign tdc_hit_in = test_hit_sync;
            assign tdc_clk    = clk_200_shifted;
        end
        else begin : MODE_RUNTIME_MUX
            // 00=off  01=RO  10=DPS(★ 2026-09-16 구현)  11=EXT
            //
            // ★ 2026-09-15 : 추론 LUT -> LUT4 프리미티브 u_hit_mux 로 명시 (논리는 같다).
            //   [무엇이 문제였나] 이 먹스가 합성에서 추론 LUT4(…CARRY_CHAIN[0].STAGE_0.u_carry4_i_1)
            //     로 캐리 체인 첫 슬라이스 SLICE_X42Y0 의 B5LUT 에 들어갔고, 같은 슬라이스 AFF 에
            //     LOC 된 탭 0 샘플링 FF(u_ff_0)가 SLICE_X44Y0 AFF 로 밀려났다.
            //       - 09-15 zed_cal (회사 노트북) : CO[0] -> u_ff_0 배선 793 ps, 탭 1·2 는 91 ps
            //         (Markdown/2026-09-15_report.md §6-5, get_net_delays SLOW_MAX)
            //       - 09-06 zed_uart (집 PC, routed DCP 조회) : 같은 LUT·같은 B5LUT, u_ff_0 도
            //         똑같이 SLICE_X44Y0 AFF, LUT 출력 -> CYINIT 560 ps. 즉 전부터 이랬다.
            //   [무엇을 바꿨나] 이름을 고정해 XDC 에서 캐리 슬라이스 밖에 LOC 한다.
            //     INIT 16'hC0A0 : I0=hit_random, I1=ext_hit_in, I2=src[0], I3=src[1] 일 때
            //     src=01 -> I0, src=11 -> I1, 그 밖 -> 0. 16조합 전부 원래 식과 대조했다.
            //   [아직 가설] u_ff_0 이 밀려난 원인이 이 LUT 이라는 것은 확인되지 않았다.
            //     빌드 후 u_ff_0 이 SLICE_X42Y0 AFF 로 돌아오는지로 판정한다.
            //   [대가] LUT 이 다른 슬라이스로 가서 히트 도착이 고정량 달라진다 -> 창이 옮겨가므로
            //     빌드 후 보드에서 '1' 로 교정표를 다시 만들 것.
            //   ★ 2026-09-16 : LUT4 -> LUT5. 입력이 하나(m0_hit) 늘었다.
            //     INIT 32'hCFA0C0A0 : I0=hit_random, I1=ext_hit_in, I2=src[0], I3=src[1], I4=m0_hit
            //       src=01 -> I0,  src=11 -> I1,  src=10 -> I4,  src=00 -> 0.
            //     32조합을 전부 파이썬으로 돌려 확인했고, 같은 방법으로 옛 C0A0 도 재현했다.
            //     [지켜야 할 것] 이 LUT 은 XDC 가 SLICE_X41Y0 에 고정한다. 캐리 슬라이스
            //     (X42Y0) 안에 들어가면 탭 0 FF 가 밀려난다 (2026-09-15 보고서 §6-5, §11-2).
            //     LUT5 도 슬라이스 하나를 넘지 않으므로 같은 LOC 가 그대로 유효하다.
            //     [대가] 먹스 입력이 늘어 히트 도착 시각이 조금 달라질 수 있다 -> 빌드 후
            //     보드에서 '1' 로 창·danger·교정표를 다시 만들 것.
            (* DONT_TOUCH = "TRUE" *)
            LUT5 #(.INIT(32'hCFA0C0A0)) u_hit_mux (
                .O  (tdc_hit_in),
                .I0 (hit_random),
                .I1 (ext_hit_in),
                .I2 (i_ctrl_hit_src[0]),
                .I3 (i_ctrl_hit_src[1]),
                .I4 (m0_hit)
            );
            assign tdc_clk    = clk_200_fixed;
        end
    endgenerate

    // ==========================================
    // 4. TDC Core & 절대 시간 변환기
    // ==========================================
    wire [31:0] raw_ts_coarse; 
    wire [8:0]  raw_ts_fine_idx; 
    wire        raw_ts_valid;
    
    // 탭 소스 전환 : tdc_fmcw_core(O/XOR 출력) <-> tdc_fmcw_core_co(CO/캐리 출력)
    //   모듈명 한 단어만 바꾸면 된다. 포트와 내부 인스턴스 이름이 동일하므로
    //   tdc.xdc 의 LOC/BEL 제약이 양쪽 모두에 그대로 적용된다.
    //   실측(2026-08-04, 빌드 통제 완료) : INL p-p 155.8(O) -> 96.8(CO) ps,
    //   40->80 C 무보정 드리프트 69.7(O) -> 8.3(CO) ps. 상세는
    //   Markdown/2026-08-04_report.md §2-7 / §3-5 참조.
    // ★ 2026-08-22 : tdc_fmcw_core(O 탭) -> tdc_fmcw_core_co(CO 탭) 로 전환.
    //   집 보드 CO 단일 지연선 캠페인(Markdown/2026-08-22_home_board_campaign.md) 대상이다.
    // ★ 2026-09-03 : 단수를 상위에서 넘긴다 (Zybo 80단 / ZedBoard 112단)
    tdc_fmcw_core_co #(
        .CARRY4_STAGES (CARRY4_STAGES)
    ) u_tdc (
        .clk         (tdc_clk),
        .rst_n       (clk_locked),
        .hit         (tdc_hit_in),
        .danger_lo   (i_danger_lo),      // ★ 2026-09-05
        .danger_hi   (i_danger_hi),
        .ts_coarse   (raw_ts_coarse),
        .ts_fine_idx (raw_ts_fine_idx),
        .ts_valid    (raw_ts_valid)
    );
    
    wire [63:0] final_timestamp_ps;
    wire        final_ts_valid;
    wire [8:0]  aligned_fine_idx;
    wire [31:0] aligned_coarse;

    tdc_timestamp_calc u_ts_calc (
        .clk             (tdc_clk),
        .rst_n           (clk_locked),
        .ts_coarse       (raw_ts_coarse),
        .ts_fine_idx     (raw_ts_fine_idx),
        .ts_valid        (raw_ts_valid),
        // ★ 2026-09-15 : 교정표 RAM Port A (AXI 클럭). ROM IP 를 PS 가 쓰는 RAM 으로 바꿨다.
        .cal_clk         (i_axi_clk),
        .cal_we          (i_cal_we),
        .cal_addr        (i_cal_addr),
        .cal_din         (i_cal_din),
        .cal_dout        (o_cal_dout),
        .timestamp_ps    (final_timestamp_ps),
        .timestamp_valid (final_ts_valid),
        .fine_idx_out    (aligned_fine_idx),
        .coarse_out      (aligned_coarse)         
    );

    // ==========================================================
    // 5. ★ [2026-09-05] 리드아웃 스캐너 제거 — 히스토그램은 AXI 가 읽는다
    // ==========================================================
    //  [무엇이 있었나]
    //  readout_active / sweep_addr / probe_read_addr / probe_read_addr_d1 로
    //  히스토그램 BRAM 을 0..NUM_TAPS-1 까지 훑으면서 ILA 에 뿌리는 스캐너가
    //  있었다. 시작 조건은 sweep_finished(ps_busy 하강 에지)였다.
    //
    //  [왜 없앴나]
    //  (1) BRAM Port B 를 AXI 슬레이브가 직접 읽게 되어 스캐너가 필요 없다.
    //      PS 가 0x43C0_1000 + 탭*4 를 읽으면 그 탭의 카운트가 나온다.
    //  (2) 시작 조건이 위상 이동에 묶여 있어서, 위상 스윕이 없는 Mode 1 에서는
    //      사람이 BTNU 를 눌러 억지로 ps_busy 를 만들어야 했다. 그 절차가
    //      문서에 없어 2026-09-05 측정에서 빈 CSV 를 받았다.
    //  (3) BRAM 읽기 지연 1클럭 보상(probe_read_addr_d1)도 함께 없어졌다.
    //      같은 보상이 이제 tdc_axi_regs 의 hpend 시프트 레지스터에 있다 —
    //      같은 함정이므로 그쪽 주석을 참조할 것.
    //
    //  아래 ps_busy 3단 동기화는 남긴다. Mode 0 의 히스토그램 게이팅
    //  (gated_ts_valid)이 ps_busy_sync_d2 를 쓰기 때문이다.
    // ==========================================================

    // ★ CDC 및 조기 트리거 수정 1: 이종 클럭(fixed -> shifted) 간 안전한 ps_busy 동기화를 위한 3단 FF 구현
    reg ps_busy_sync_d1;
    reg ps_busy_sync_d2;
    reg ps_busy_sync_d3; // 하강 에지 검출용 지연 레지스터

    always @(posedge tdc_clk or negedge clk_locked) begin
        if (!clk_locked) begin
            ps_busy_sync_d1 <= 1'b0;
            ps_busy_sync_d2 <= 1'b0;
            ps_busy_sync_d3 <= 1'b0;
        end else begin
            ps_busy_sync_d1 <= ps_busy;
            ps_busy_sync_d2 <= ps_busy_sync_d1; // 메타스테빌리티 방지 보장
            ps_busy_sync_d3 <= ps_busy_sync_d2; // 하강 에지 구분을 위해 1클럭 더 지연
        end
    end

    // ==========================================================
    // 6. 히스토그램 데이터 게이팅 및 모듈 인스턴스 (핵심 수정)
    // ==========================================================
    wire gated_ts_valid;

    generate
        if (OPERATION_MODE == 0) begin : MODE_0_HISTO_CTRL
            // Mode 0: 스윕(Phase Shift) 중일 때만 Hit 누적! (대기 중 쌓이는 쓰레기 값 차단)
            // ★ CDC 수정 3: tdc_clk 도메인으로 동기화가 완료된 ps_busy_sync_d2를 적용하여 글리치 및 타이밍 불일치 차단
            assign gated_ts_valid = final_ts_valid && ps_busy_sync_d2;
        end else begin : MODE_1_HISTO_CTRL
            // Mode 1: 대기 중에도 백그라운드에서 자연스럽게 수백만 개가 누적되도록 항상 켬
            assign gated_ts_valid = final_ts_valid;
        end
    endgenerate

    // ★ 2026-09-05 : Port B 가 AXI 로 넘어갔다.
    //   read_addr/read_data 가 i_axi_clk 도메인이라 이 모듈 안에서는 쓰지 않고
    //   최상위 포트로 그대로 통과시킨다. 히스토그램 지우기(i_histo_clr)는
    //   tdc_axi_regs 가 이미 tdc_clk 도메인으로 래치해서 준 레벨 신호다.
    tdc_histogram #(
        .ADDR_WIDTH(9),
        .DATA_WIDTH(32)
    ) u_histo (
        .clk         (tdc_clk),
        .rst_n       (clk_locked),
        .ts_fine_idx (aligned_fine_idx),
        .ts_valid    (gated_ts_valid),
        // ★ 2026-09-05 : 지우기는 두 곳에서 온다 — 소프트웨어 수동(CTRL.HISTO_CLR)과
        //   시퀀서의 S_STABILIZE. 둘 다 레벨이라 OR 로 합치면 된다.
        .histo_clr   (i_histo_clr | seq_histo_clr),
        .en          (seq_histo_en),
        .hit_accepted(histo_hit_accepted),
        .hit_dropped (histo_hit_dropped),
        .clk_b       (i_axi_clk),
        .read_addr   (i_histo_addr),
        .read_data   (o_histo_data)
    );

    // ==========================================================
    // ★ 2026-09-05 : 측정 시퀀서 FSM
    // ==========================================================
    tdc_seq u_seq (
        .clk           (tdc_clk),
        .rst_n         (clk_locked),
        .ctrl_start    (i_ctrl_start),
        .ctrl_stop     (i_ctrl_stop),
        .ctrl_hit_src  (i_ctrl_hit_src),
        .target_hits   (i_target_hits),
        .settle_n      (i_settle_n),
        .meas_strobe   (meas_strobe),
        .ro_cnt        (ro_meas_cnt),
        .die_temp      (die_temp_at_meas),
        .hit_accepted  (histo_hit_accepted),
        .hit_dropped   (histo_hit_dropped),
        .cap_full      (cap_full),
        .cap_written   (cap_written),
        .cap_lost      (cap_lost),
        .cap_en        (seq_cap_en),
        .cap_clr       (seq_cap_clr),
        .ro_en         (seq_ro_en),
        .histo_en      (seq_histo_en),
        .histo_clr     (seq_histo_clr),
        .busy          (o_busy),
        .done          (o_done),
        .state_out     (o_state),
        .hit_cnt       (o_hit_cnt),
        .drop_cnt      (o_drop_cnt),
        .ro_at_start   (o_ro_start),
        .ro_at_end     (o_ro_end),
        .temp_at_start (o_temp_start),
        .temp_at_end   (o_temp_end),
        .snap_tgl      (o_snap_tgl)
    );

    // ==========================================================
    // ★ 2026-09-05 : 캡처 버퍼 (Mode 2 = 외부 LVDS 실측)
    //   히스토그램이 "탭마다 몇 발" 이라면 이쪽은 "히트 하나하나의 시각" 이다.
    //   final_timestamp_ps 는 상위 비트가 안 쓰이므로 48비트만 넘긴다
    //   (coarse 32비트 x 5000 ps 라 이론 최대가 48비트를 넘지 않는다).
    // ==========================================================
    tdc_capture #(
        .ADDR_WIDTH (12)                    // 4096 발
    ) u_cap (
        .clk          (tdc_clk),
        .rst_n        (clk_locked),
        .en           (seq_cap_en),
        .clr          (seq_cap_clr),
        .cap_fmt      (i_ctrl_cap_fmt),
        .ts_valid     (final_ts_valid),
        .timestamp_ps (final_timestamp_ps[47:0]),
        .ts_coarse    (aligned_coarse),
        .ts_fine_idx  (aligned_fine_idx),
        .cap_n        (i_cap_n),
        .cap_cnt      (o_cap_cnt),
        .full         (cap_full),
        .hit_written  (cap_written),
        .hit_lost     (cap_lost),
        .clk_b        (i_axi_clk),
        .read_addr    (i_cap_addr),
        .read_hi      (i_cap_hi),
        .read_data    (o_cap_data)
    );

    assign led[0] = clk_locked;
    // ★ 2026-09-05 : readout_active 가 없어져 위상 이동 표시로 바꾼다.
    assign led[1] = ps_busy;
    // ★ Entry transient 수정: 과거 led[2]에 tdc_hit_in을 연결했으나 제거함.
    //   hit 네트가 딜레이라인 CYINIT과 LED 패드(G14)를 동시에 구동하면서
    //   배선 부하로 에지 slew가 저하되고, 그 결과 CARRY4 초입에 entry transient 발생.
    //   (실측: net delay 4227ps / CARRY4#0 소비시간 129.71ps = 이상값 68.5ps의 1.89배,
    //    #1 1.51배, #2 1.16배로 감쇠하다 #3부터 정상 회복 → DNL 최댓값 +3.234의 주범)
    //   hit은 CYINIT 외에 어떤 부하도 걸어서는 안 되므로 연결하지 않는다.
    assign led[2] = 1'b0;
    assign led[3] = final_ts_valid; 

    // ==========================================================
    // 7. ★ [2026-09-05] ILA 제거 — 데이터는 전부 AXI 로 나간다
    // ==========================================================
    //  [무엇이 있었나]
    //  ila_0(universal_ila) 인스턴스와, 그 캡처 조건을 만들던 로직
    //  (toggle_sync_d1..d3 / step_changed_pulse / cap_cnt /
    //   current_loop_cnt_stable / capture_trigger)이 있었다. 프로브 10개로
    //  타임스탬프·히스토그램·RO 주파수·온도·DNA 를 한꺼번에 뽑았다.
    //
    //  [왜 없앴나]
    //  (1) 히스토그램은 이제 AXI 로 읽는다(0x43C0_1000 + 탭*4).
    //      RO 카운트·온도·DNA 도 레지스터로 나간다(0x14 / 0x18 / 0x10).
    //      즉 ILA 로만 볼 수 있던 것이 남지 않았다.
    //  (2) ILA 를 쓰려면 Vivado Hardware Manager 를 띄우고 사람이 버튼을
    //      눌러야 했다. Vitis 에서 레지스터만으로 측정을 끝내는 것이 목표다.
    //  (3) 2026-09-04 빌드에서 타이밍 임계경로가 ILA IP 안에 있었다.
    //      빼면 그만큼 여유가 늘어난다. (실제 효과는 이번 빌드에서 확인할 것)
    //
    //  [무엇이 함께 사라졌나 — 3단계에서 되살릴 것]
    //  개별 히트의 타임스탬프를 모으는 경로가 지금은 없다. capture_trigger 가
    //  하던 "위상 스텝이 바뀌면 CAP_PER_STEP 발만 캡처" 로직은 3단계의
    //  캡처 버퍼 + 시퀀서 FSM 으로 옮긴다. 그때까지 Mode 0(DPS)과 Mode 2(EXT)의
    //  타임스탬프는 읽을 수 없다 — 2단계는 Mode 1(코드밀도)만 완성시킨다.
    //
    //  [ila_0 IP 자체]
    //  build_zedboard.tcl 의 IP 생성 목록에서도 뺐다. 다시 넣으려면 그 목록과
    //  이 자리 양쪽을 되살려야 한다.

    // ★ [2026-09-04] AXI 레지스터 블록으로 내보내는 TDC 도메인 신호
    assign o_tdc_clk    = clk_200_fixed;
    assign o_locked     = clk_locked;
    assign o_dna        = device_dna[30:0];
    assign o_dna_valid  = device_dna_valid;
    assign o_phase_busy = ps_busy;

    // ★ [2026-09-05 추가] ILA 로만 보던 값들을 레지스터로 내보낸다.
    //   o_meas_strobe 는 tdc_axi_regs 가 다중 비트 CDC 용 토글을 만드는 데 쓴다.
    //   ILA 시절에는 이 신호가 '자격저장 조건'이었다 — 같은 신호의 역할만 바뀐 셈이다.
    assign o_meas_strobe = meas_strobe;
    assign o_ro_cnt      = ro_meas_cnt;
    assign o_die_temp    = die_temp_at_meas;
    assign o_phase_cur   = current_loop_cnt;

    // ★ [2026-09-05] btn_shift 는 이제 쓰지 않는다.
    //   포트와 XDC 제약(T18)은 남겨 둔다. 3단계 시퀀서에서 "측정 시작" 같은
    //   수동 트리거로 다시 쓸 여지가 있고, 지우면 XDC 도 함께 고쳐야 한다.
    //   합성에서 "unused port" 경고가 뜨는 것은 정상이다.

endmodule
