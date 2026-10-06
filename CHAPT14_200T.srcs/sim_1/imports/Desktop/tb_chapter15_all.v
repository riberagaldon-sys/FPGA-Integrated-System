`timescale 1ns/1fs

// Teaching manual Chapter 15 -> chapter14_vivado_ip_xdc_200t.xpr.
// Simulation top: tb_chapter15_all. Run 2 ms; expect CH15 PASS at 1.95 ms.
// Two DUTs: clock_dut is the real top_chapter14_vivado_system (POR_BITS=4);
// dut is the real optimized game_system_5slot, fourth slot u_game4_breakout.
// All screenshot signals are read-only aliases at this testbench root.
//
// CLOCK/LOCK FIXTURE SCOPE (Figure 15-1):
// sys_clk is 50 MHz. The actual top's lcd_pix_clk and lcd_clk_locked nets
// receive controlled simulation injection. Pixel clock is exactly 51.2 MHz;
// lock rises at 500 ns, falls at 1200 ns and recovers at 1500 ns.
// This runs the ORIGINAL top-level three-stage reset chain and its reset
// consumers; it is not a measurement of MMCM acquisition time, analog lock
// behavior, generated-clock timing, hardware clocks or board acceptance.
// Only the top clock fixture's two nets are forced. No game register,
// coordinate, brick bit or array element is forced/deposited/initialized.
// The complete top and its real UNISIM primitives remain in the project.
// POR_BITS alone changes 21->4 to shorten simulation startup.
//
// GAME SCOPE (Figure 15-2):
// Original 50 bricks, dimensions, velocities and three lives are retained.
// Only normal event, pointer, pixel-coordinate and accelerated game_tick
// ports are driven. Every new tick waits until the candidate is consumed.
// The file includes an otherwise unchanged, renamed Chapter-13 original
// breakout module for comparison with the threshold/pending optimized RTL.
// Its final live results are compared after the intentional pending delay.
// The original pitch-cell centre mapping is retained; this is not an AABB
// collision-model replacement. All 50 bricks, last-brick WIN, dead-cell
// queries, life branches, pause, restart and pending cancellation are tested.
// Local display copying uses the original pixel_x/y==0 condition; that
// condition alone is not verification of a genuine LCD frame_start pulse.
// Functional regression does not prove WNS/TNS, external pin timing or CDC.
// No $finish/$stop: keep the Vivado waveform window open for screenshots.
//
// Figure 15-1: 450..1650 ns.
//   sys_clk, lcd_pix_clk, lcd_clk_locked, lcd_reset_sync, lcd_logic_rst_n.
//   Binary for all five signals. 000->001->011->111 after each lock rise;
//   loss of lock immediately clears the real reset chain to 000.
// Figure 15-2(a): 15.90..16.50 us.
//   game_tick, brick_check_pending/index, brick49_alive, score_live,
//   bricks_remaining_live, vy_live and the corresponding ref_* aliases.
//   Candidate 49 registers first; one pixel clock later it clears once,
//   score 0->1, remaining 50->49 and vy -4->+4. Reference clears one clock
//   earlier but the completed results must match.
// Figure 15-2(b): 1024.55..1024.90 us; last registered brick index is 39.
//   brick_check_pending/index, last_hit_index, score_live,
//   bricks_remaining_live, state_live, brick_alive_live and ref_* aliases.
//   Remaining 1->0, score 49->50 and RUN 1->WIN 4 on consumption.
// Decimal for positions/indices/counts/state; Signed Decimal for velocities;
// Binary for pulses/bits/reset chain; Hexadecimal for the 50-bit bitmap.

module tb_chapter15_all;
    reg sys_clk = 1'b0;
    always #10 sys_clk = ~sys_clk;
    reg pixel_clock_model = 1'b0;
    always #9.765625 pixel_clock_model = ~pixel_clock_model;
    reg locked_model = 1'b0;
    tri1 PS2_CLK, PS2_DATA, TOUCH_SDA, TOUCH_INT;
    wire [3:0] O_SWR;
    wire TOUCH_SCL, TOUCH_RST;
    wire [7:0] LCD_R, LCD_G, LCD_B;
    wire LCD_CLK, LCD_HSYNC, LCD_VSYNC, LCD_DE, LCD_BL, LCD_nRST;
    wire [4:0] led;

    // Shorten only the POR counter for this clock/reset fixture. The actual
    // top's three-stage synchronizer and all its dependent reset paths run.
    top_chapter14_vivado_system #(.POR_BITS(4)) clock_dut (
        .sys_clk(sys_clk), .I_SWC(4'hF), .O_SWR(O_SWR),
        .S1_KEYA(1'b1), .S1_KEYB(1'b1), .S1_KEYC(1'b1),
        .S1_KEYD(1'b1), .S1_KEYP(1'b1),
        .EC_A(1'b1), .EC_B(1'b1), .EC_KEY(1'b1),
        .PS2_CLK(PS2_CLK), .PS2_DATA(PS2_DATA),
        .TOUCH_SCL(TOUCH_SCL), .TOUCH_SDA(TOUCH_SDA),
        .TOUCH_INT(TOUCH_INT), .TOUCH_RST(TOUCH_RST),
        .LCD_R(LCD_R), .LCD_G(LCD_G), .LCD_B(LCD_B),
        .LCD_CLK(LCD_CLK), .LCD_HSYNC(LCD_HSYNC), .LCD_VSYNC(LCD_VSYNC),
        .LCD_DE(LCD_DE), .LCD_BL(LCD_BL), .LCD_nRST(LCD_nRST), .led(led)
    );
    wire sys_rst_n = clock_dut.rst_n;
    wire lcd_pix_clk = clock_dut.lcd_pix_clk;
    wire lcd_clk_locked = clock_dut.lcd_clk_locked;
    wire [2:0] lcd_reset_sync = clock_dut.lcd_reset_sync;
    wire lcd_logic_rst_n = clock_dut.lcd_logic_rst_n;
    wire clk = lcd_pix_clk;

    // Controlled clock/lock injection isolates the real top-level reset chain
    // from vendor MMCM startup-model timing. These two CLOCK FIXTURE nets are
    // the only forced objects; no game state, coordinate or brick is forced.
    // The injection stays active for this bench's entire waveform session.
    initial begin
        force clock_dut.lcd_pix_clk = pixel_clock_model;
        force clock_dut.lcd_clk_locked = locked_model;
        #500; locked_model=1'b1;
        #700; locked_model=1'b0;
        #300; locked_model=1'b1;
    end
    reg rst_n = 1'b0;
    wire game_rst_n = rst_n && lcd_logic_rst_n;
    reg [2:0] ui_state_control = 3'd5;
    reg [2:0] ui_state_frame = 3'd5;
    reg event_left = 1'b0;
    reg event_right = 1'b0;
    reg event_ok = 1'b0;
    reg event_back = 1'b0;
    reg event_pause = 1'b0;
    reg game_tick = 1'b0;
    reg [10:0] pointer_x = 11'd512;
    reg [9:0] pointer_y = 10'd300;
    reg pointer_down = 1'b0;
    reg [10:0] pixel_x = 11'd128;
    reg [9:0] pixel_y = 10'd250;
    wire pixel_on;
    wire [23:0] pixel_rgb;
    wire [15:0] score;
    wire [3:0] game_state;
    wire exit_request;

    game_system_5slot dut (
        .clk(clk), .rst_n(game_rst_n),
        .ui_state_control(ui_state_control), .ui_state_frame(ui_state_frame),
        .event_up(1'b0), .event_down(1'b0),
        .event_left(event_left), .event_right(event_right),
        .event_ok(event_ok), .event_back(event_back),
        .event_pause(event_pause), .game_tick(game_tick), .tick_1s(1'b0),
        .pointer_x(pointer_x), .pointer_y(pointer_y), .pointer_down(pointer_down),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .pixel_on(pixel_on),
        .pixel_rgb(pixel_rgb), .score(score), .game_state(game_state),
        .exit_request(exit_request)
    );

    wire [4:0] enable = dut.enable;
    wire game_enable = enable[3];
    wire [3:0] state_live = dut.u_game4_breakout.state_live;
    wire [10:0] ball_x_live = dut.u_game4_breakout.ball_x_live;
    wire [9:0] ball_y_live = dut.u_game4_breakout.ball_y_live;
    wire signed [5:0] vx_live = dut.u_game4_breakout.vx_live;
    wire signed [5:0] vy_live = dut.u_game4_breakout.vy_live;
    wire [10:0] paddle_x_live = dut.u_game4_breakout.paddle_x_live;
    wire [49:0] brick_alive_live = dut.u_game4_breakout.brick_alive_live;
    wire brick49_alive = brick_alive_live[49];
    wire brick0_alive = brick_alive_live[0];
    wire [5:0] bricks_remaining_live = dut.u_game4_breakout.bricks_remaining_live;
    wire [2:0] lives_live = dut.u_game4_breakout.lives_live;
    wire [15:0] score_live = dut.u_game4_breakout.score_live;
    wire signed [31:0] calc_x = dut.u_game4_breakout.calc_x;
    wire signed [31:0] calc_y = dut.u_game4_breakout.calc_y;
    wire signed [31:0] calc_vy = dut.u_game4_breakout.calc_vy;
    wire signed [31:0] calc_center_x = dut.u_game4_breakout.calc_center_x;
    wire signed [31:0] calc_center_y = dut.u_game4_breakout.calc_center_y;
    wire signed [31:0] calc_brick_col = dut.u_game4_breakout.calc_brick_col;
    wire signed [31:0] calc_brick_row = dut.u_game4_breakout.calc_brick_row;
    wire signed [31:0] calc_brick_index = dut.u_game4_breakout.calc_brick_index;
    wire [10:0] ball_x_frame = dut.u_game4_breakout.ball_x_frame;
    wire [9:0] ball_y_frame = dut.u_game4_breakout.ball_y_frame;
    wire [49:0] brick_alive_frame = dut.u_game4_breakout.brick_alive_frame;

    wire brick_check_pending = dut.u_game4_breakout.brick_check_pending;
    wire [5:0] brick_check_index = dut.u_game4_breakout.brick_check_index;

    // Renamed, otherwise unchanged Chapter-13 source is included at the end
    // of this single file. Both versions see the same public input trace.
    wire reference_pixel_on;
    wire [23:0] reference_pixel_rgb;
    wire [15:0] reference_score;
    wire [3:0] reference_game_state;
    wire reference_exit_request;
    breakout_game_ch13_reference reference_dut (
        .clk(clk), .rst_n(game_rst_n), .game_enable(game_enable),
        .event_left(event_left), .event_right(event_right),
        .event_ok(event_ok), .event_back(event_back), .event_pause(event_pause),
        .game_tick(game_tick), .pointer_x(pointer_x), .pointer_y(pointer_y),
        .pointer_down(pointer_down), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .pixel_on(reference_pixel_on), .pixel_rgb(reference_pixel_rgb),
        .score(reference_score), .game_state(reference_game_state),
        .exit_request(reference_exit_request)
    );
    wire [49:0] ref_brick_alive_live = reference_dut.brick_alive_live;
    wire ref_brick49_alive = ref_brick_alive_live[49];
    wire [15:0] ref_score_live = reference_dut.score_live;
    wire [5:0] ref_bricks_remaining_live = reference_dut.bricks_remaining_live;
    wire signed [5:0] ref_vy_live = reference_dut.vy_live;
    wire [3:0] ref_state_live = reference_dut.state_live;

    integer reset_releases = 0;
    integer lock_losses = 0;
    integer release_edges = 0;
    integer pixel_period_checks = 0;
    integer sys_period_checks = 0;
    integer pipeline_candidates = 0;
    integer pipeline_consumed = 0;
    integer pipeline_hits = 0;
    integer empty_queries = 0;
    integer reference_checks = 0;
    integer cancelled_candidates = 0;
    reg [5:0] last_hit_index = 0;
    real last_hit_ns = 0.0;
    real last_pixel_edge = 0.0;
    real last_sys_edge = 0.0;
    reg [2:0] expected_sync;
    reg was_logic_reset;

    // Check the externally observable release contract: 001, 011, 111;
    // reset remains asserted through the first two destination clock edges.
    always @(negedge lcd_clk_locked) begin
        release_edges=0;
        if ($realtime>1.0) lock_losses=lock_losses+1;
        #0.001;
        check(lcd_reset_sync===3'b000 && !lcd_logic_rst_n,
              "loss of lock did not assert the actual top reset asynchronously");
    end
    always @(posedge sys_clk) begin
        if (last_sys_edge>0.0 && sys_period_checks<8) begin
            check($realtime-last_sys_edge==20.0,"sys clock period is not 20 ns");
            sys_period_checks=sys_period_checks+1;
        end
        last_sys_edge=$realtime;
    end
    always @(posedge lcd_pix_clk) begin
        if (last_pixel_edge>0.0 && pixel_period_checks<8) begin
            check($realtime-last_pixel_edge==19.53125,
                  "injected pixel clock period is not 19.53125 ns");
            pixel_period_checks=pixel_period_checks+1;
        end
        last_pixel_edge=$realtime;
        was_logic_reset=lcd_logic_rst_n;
        if (!lcd_clk_locked) begin
            release_edges=0;
            expected_sync=3'b000;
        end else begin
            if (release_edges<3) release_edges=release_edges+1;
            case (release_edges)
                1: expected_sync=3'b001;
                2: expected_sync=3'b011;
                default: expected_sync=3'b111;
            endcase
        end
        #0.001;
        check(lcd_reset_sync===expected_sync,
              "actual top-level reset chain did not release in three pixel clocks");
        check(lcd_logic_rst_n==((expected_sync==3'b111)?1'b1:1'b0),
              "pixel logic reset was released on the wrong edge");
        if (!was_logic_reset && lcd_logic_rst_n) reset_releases=reset_releases+1;
    end

    reg stage_was_pending;
    reg stage_is_movement;
    reg [5:0] stage_index;
    reg [49:0] stage_bitmap;
    integer stage_score;
    integer stage_remaining;
    integer stage_vy;
    integer expected_index;

    // Audit each real transaction at both stages. The next movement pulse
    // is deliberately spaced after consumption, as with the hardware 60 Hz
    // tick; this does not assert operation with a pulse every pixel clock.
    always @(posedge clk) begin
        if (game_rst_n && game_enable && !checks_done) begin
            stage_was_pending=brick_check_pending;
            stage_is_movement=(state_live==1 && game_tick && !event_pause);
            stage_index=brick_check_index;
            stage_bitmap=brick_alive_live;
            stage_score=score_live;
            stage_remaining=bricks_remaining_live;
            stage_vy=vy_live;
            check(!(stage_was_pending && stage_is_movement),
                  "new movement was injected before previous candidate consumption");
            #0.001;
            if (stage_was_pending) begin
                check(!brick_check_pending,"second stage did not clear pending");
                check(stage_index<50,"registered brick candidate is out of bounds");
                if (stage_index<50) begin
                    if (stage_bitmap[stage_index]) begin
                        check(!brick_alive_live[stage_index] &&
                              alive_count(stage_bitmap & ~brick_alive_live)==1 &&
                              score_live==stage_score+1 &&
                              bricks_remaining_live==stage_remaining-1 &&
                              vy_live==-stage_vy,
                              "second stage clear/score/remaining/rebound failed");
                        if (stage_remaining==1)
                            check(state_live==4,"last brick did not enter WIN on consumption");
                        pipeline_hits=pipeline_hits+1;
                        last_hit_index=stage_index; last_hit_ns=$realtime;
                    end else begin
                        check(brick_alive_live==stage_bitmap &&
                              score_live==stage_score &&
                              bricks_remaining_live==stage_remaining && vy_live==stage_vy,
                              "already-cleared candidate was scored or reflected again");
                        empty_queries=empty_queries+1;
                    end
                end
                pipeline_consumed=pipeline_consumed+1;
            end else if (stage_is_movement) begin
                check(score_live==stage_score && bricks_remaining_live==stage_remaining &&
                      brick_alive_live==stage_bitmap,
                      "optimized first stage incorrectly cleared/scored immediately");
                if (calc_center_x>=162 && calc_center_x<882 &&
                    calc_center_y>=96 && calc_center_y<216) begin
                    expected_index=((calc_center_y-96)/24)*10+(calc_center_x-162)/72;
                    check(brick_check_pending && brick_check_index==expected_index,
                          "threshold mapping did not register the correct candidate");
                    check(vy_live==calc_vy,"first stage committed wrong movement velocity");
                    pipeline_candidates=pipeline_candidates+1;
                end else
                    check(!brick_check_pending,"out-of-region movement registered a candidate");
            end
        end
    end

    // Compare FINAL live results after the optimized stage has settled.
    // Its intentional one-clock pending interval is excluded from equality.
    // This is a source-to-source functional regression, not a timing proof.
    always @(posedge clk) begin
        #0.002;
        if (!checks_done && !brick_check_pending) begin
            check(ball_x_live===reference_dut.ball_x_live &&
                  ball_y_live===reference_dut.ball_y_live &&
                  vx_live===reference_dut.vx_live && vy_live===reference_dut.vy_live &&
                  paddle_x_live===reference_dut.paddle_x_live &&
                  brick_alive_live===ref_brick_alive_live &&
                  score_live===ref_score_live &&
                  bricks_remaining_live===ref_bricks_remaining_live &&
                  lives_live===reference_dut.lives_live && state_live===ref_state_live,
                  "original/optimized final live state differs for the same input trace");
            reference_checks=reference_checks+1;
        end
    end

    integer case_id = 0;
    integer errors = 0;
    integer checked_ticks = 0;
    integer ready_tests = 0;
    integer pointer_tests = 0;
    integer pause_tests = 0;
    integer loss_tests = 0;
    integer restart_tests = 0;
    integer win_tests = 0;
    integer first_game_score = 0;
    integer left_wall_bounces = 0;
    integer right_wall_bounces = 0;
    integer top_wall_bounces = 0;
    integer paddle_bounces = 0;
    integer cleared_cell_queries = 0;
    integer auto_ticks = 0;
    integer auto_paddle_choices = 0;
    reg index0_cleared = 1'b0;
    reg index49_cleared = 1'b0;
    reg checks_done = 1'b0;
    reg checks_pass = 1'b0;

    task check;
        input condition;
        input [767:0] message;
        begin
            if (condition !== 1'b1) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("CH15 FAIL at %0.6f us: %0s", $realtime/1000.0, message);
            end
        end
    endtask

    task at_ns;
        input integer target_ns;
        real remaining;
        begin
            remaining = target_ns - $realtime;
            if (remaining > 0) #(remaining);
            @(negedge clk);
        end
    endtask

    // Mask bits: Left, Right, OK, Back, Pause, unused, unused, game_tick.
    task pulse;
        input [7:0] mask;
        begin
            @(negedge clk);
            event_left=mask[0]; event_right=mask[1]; event_ok=mask[2];
            event_back=mask[3]; event_pause=mask[4]; game_tick=mask[7];
            #0.001;
            if (mask[3]) begin
                check(dut.u_game4_breakout.exit_request === game_enable,
                      "breakout Back output was not gated by its slot enable");
                check(exit_request === (|enable), "system Back output missed the selected slot");
            end
            @(negedge clk);
            event_left=0; event_right=0; event_ok=0;
            event_back=0; event_pause=0; game_tick=0;
            #0.001;
        end
    endtask

    task drag;
        input integer x;
        begin
            @(negedge clk); pointer_x=x; pointer_down=1;
            repeat (3) @(negedge clk);
            pointer_down=0; #0.001;
        end
    endtask

    function integer alive_count;
        input [49:0] bitmap;
        integer i;
        begin
            alive_count=0;
            for (i=0; i<50; i=i+1)
                if (bitmap[i] === 1'b1) alive_count=alive_count+1;
        end
    endfunction

    task check_initial;
        begin
            check(state_live==0 && paddle_x_live==456
               && ball_x_live==505 && ball_y_live==522
               && vx_live==4 && vy_live==-4 && lives_live==3
               && brick_alive_live=={50{1'b1}}
               && bricks_remaining_live==50 && score_live==0 && !brick_check_pending,
                  "READY/initial ball/paddle/lives/brick bitmap mismatch");
        end
    endtask

    reg [49:0] old_bitmap;
    reg [49:0] removed_bitmap;
    integer old_score;
    integer old_remaining;
    integer old_vx;
    integer old_vy;
    integer removed_count;
    integer row_ref;
    integer col_ref;
    integer index_ref;
    // Check conservation and one-time removal after each real movement tick.
    task tick_checked;
        begin
            check(game_enable && state_live==1, "checked movement tick began outside RUN");
            old_bitmap=brick_alive_live; old_score=score_live;
            old_remaining=bricks_remaining_live; old_vx=vx_live; old_vy=vy_live;
            pulse(8'h80);
            @(negedge clk); #0.001; // consume the registered candidate
            check(!brick_check_pending, "pending candidate was not consumed");
            removed_bitmap=old_bitmap & ~brick_alive_live;
            removed_count=alive_count(removed_bitmap);
            check((brick_alive_live & ~old_bitmap)==0 && removed_count<=1,
                  "a movement tick restored bricks or removed more than one");
            check(score_live==old_score+removed_count
               && bricks_remaining_live==old_remaining-removed_count
               && bricks_remaining_live==alive_count(brick_alive_live)
               && score_live+bricks_remaining_live==50,
                  "brick bitmap/score/remaining-count conservation failed");
            check(ball_x_live>=112 && ball_x_live<=898
               && ball_y_live>=64 && ball_y_live<=593,
                  "committed ball position is outside the movement limits");
            check((vx_live==4 || vx_live==-4 || vx_live==6 || vx_live==-6)
               && (vy_live==4 || vy_live==-4), "velocity sign/magnitude mismatch");
            if (calc_center_x>=162 && calc_center_x<882
             && calc_center_y>=96 && calc_center_y<216) begin
                col_ref=(calc_center_x-162)/72;
                row_ref=(calc_center_y-96)/24;
                index_ref=row_ref*10+col_ref;
                check(calc_brick_col==col_ref && calc_brick_row==row_ref
                   && calc_brick_index==index_ref && index_ref>=0 && index_ref<50,
                      "centre-to-brick column/row/index mismatch");
                if (!old_bitmap[index_ref]) begin
                    check(removed_count==0 && score_live==old_score,
                          "an already-cleared brick was scored again");
                    cleared_cell_queries=cleared_cell_queries+1;
                end
            end
            if (removed_count==1) begin
                check(removed_bitmap[calc_brick_index] && vy_live==-old_vy,
                      "brick clear used a different index or failed to reverse vertical speed");
                if (removed_bitmap[0]) index0_cleared=1;
                if (removed_bitmap[49]) index49_cleared=1;
            end
            if (old_vx<0 && vx_live>0 && ball_x_live==112)
                left_wall_bounces=left_wall_bounces+1;
            if (old_vx>0 && vx_live<0 && ball_x_live==898)
                right_wall_bounces=right_wall_bounces+1;
            if (old_vy<0 && vy_live>0 && ball_y_live==64)
                top_wall_bounces=top_wall_bounces+1;
            if (old_vy>0 && vy_live<0 && ball_y_live==522)
                paddle_bounces=paddle_bounces+1;
            checked_ticks=checked_ticks+1;
        end
    endtask

    task ticks;
        input integer count;
        integer i;
        begin
            for (i=0; i<count; i=i+1) begin
                tick_checked();
                repeat (3) @(negedge clk);
            end
            #0.001;
        end
    endtask

    task snapshot_once;
        begin
            @(negedge clk); pixel_x=0; pixel_y=0;
            @(negedge clk); pixel_x=128; pixel_y=250;
            #0.001;
            check(ball_x_frame==ball_x_live && ball_y_frame==ball_y_live
               && brick_alive_frame==brick_alive_live && score==score_live
               && game_state==state_live
               && dut.u_game4_breakout.paddle_x_frame==paddle_x_live
               && dut.u_game4_breakout.lives_frame==lives_live,
                  "local display copy missed a completed game update");
        end
    endtask

    // Move the paddle to the left through its pointer port, let the ball
    // miss naturally, then align the last two downward ticks for screenshots.
    task lose_life;
        input integer loss_ns;
        input integer after_lives;
        integer waited;
        integer before_lives;
        integer held_score;
        reg [49:0] held_bitmap;
        begin
            before_lives=lives_live;
            drag(0);
            waited=0;
            while (state_live==1 && (vy_live<0 || ball_y_live<582) && waited<2000) begin
                ticks(1); waited=waited+1;
            end
            check(state_live==1 && vy_live==4 && ball_y_live==582
               && paddle_x_live==112, "natural falling-ball setup failed");
            check($realtime<loss_ns-1000, "loss setup missed its screenshot time");
            at_ns(loss_ns-1000); tick_checked();
            check(state_live==1 && ball_y_live==586, "penultimate drop tick was not RUN at y=586");
            held_score=score_live; held_bitmap=brick_alive_live;
            at_ns(loss_ns); tick_checked();
            // tick_checked now waits through the second pixel clock, so
            // the one-clock LIFE_LOST branch has already selected READY/OVER.
            check(lives_live==after_lives && state_live==((after_lives==0)?5:0),
                  "LIFE_LOST did not select READY/OVER with exactly one life removed");
            repeat (3) @(negedge clk); #0.001;
            check(lives_live==after_lives && score_live==held_score
               && brick_alive_live==held_bitmap, "one drop removed extra lives or reset bricks/score");
            if (after_lives>0)
                check(ball_x_live==161 && ball_y_live==522 && vx_live==4 && vy_live==-4,
                      "READY after a miss did not reattach the ball/reset its velocity");
            else check(ball_y_live==590, "OVER changed the final missed-ball position");
            loss_tests=loss_tests+1;
        end
    endtask

    reg [31:0] steering_bits=32'h1ACE1234;
    integer predicted_x;
    integer predicted_center;
    integer offset;
    // The helper drives only the same pointer port a user would use.
    // Changing the landing point varies the outgoing +/-6 paddle deflection.
    task clear_all_bricks;
        begin
            auto_ticks=0; steering_bits=32'h1ACE1234;
            while (state_live==1 && auto_ticks<16000) begin
                predicted_x=ball_x_live;
                predicted_x=predicted_x+$signed(vx_live);
                if (predicted_x<112) predicted_x=112;
                else if (predicted_x>898) predicted_x=898;
                predicted_center=predicted_x+7;
                offset=0;
                if (vy_live>0 && ball_y_live>=518) begin
                    steering_bits={steering_bits[30:0],
                        steering_bits[31]^steering_bits[21]^steering_bits[1]^steering_bits[0]};
                    case (steering_bits[1:0])
                        0: offset=28;
                        1: offset=-28;
                        default: offset=0;
                    endcase
                    auto_paddle_choices=auto_paddle_choices+1;
                end
                @(negedge clk); pointer_x=predicted_center+offset; pointer_down=1;
                repeat (2) @(negedge clk);
                tick_checked(); auto_ticks=auto_ticks+1;
            end
            pointer_down=0;
            check(state_live==4 && score_live==50 && bricks_remaining_live==0
               && brick_alive_live==0 && lives_live==3,
                  "normal paddle control failed to clear all 50 bricks without a miss");
            check(index0_cleared && index49_cleared, "edge brick indices 0/49 were not cleared");
            win_tests=win_tests+1;
            $display("CH15 WIN at %0.6f us: score=%0d remaining=%0d auto_ticks=%0d last_index=%0d hit_ns=%0.6f",
                     $realtime/1000.0,score_live,bricks_remaining_live,auto_ticks,last_hit_index,last_hit_ns);
        end
    endtask

    integer held_x;
    integer held_y;
    integer held_paddle;
    reg [49:0] held_bricks;
    initial begin
        at_ns(1800); rst_n=1;
        check_initial();
        check(enable==5'b01000, "fourth-slot selection mismatch");

        at_ns(2000); case_id=1;
        pulse(8'h02); repeat (2) @(negedge clk); #0.001;
        check(paddle_x_live==472 && ball_x_live==521, "READY Right step/attached-ball delay mismatch");
        ready_tests=ready_tests+1;
        pulse(8'h01); repeat (2) @(negedge clk); #0.001;
        check(paddle_x_live==456 && ball_x_live==505, "READY Left step mismatch"); ready_tests=ready_tests+1;
        pulse(8'h03); repeat (2) @(negedge clk); #0.001;
        check(paddle_x_live==440, "simultaneous Left/Right did not prioritize Left"); ready_tests=ready_tests+1;
        pulse(8'h02); repeat (2) @(negedge clk);
        drag(0); check(paddle_x_live==112 && ball_x_live==161, "left pointer clamp failed"); pointer_tests=pointer_tests+1;
        drag(1023); check(paddle_x_live==800 && ball_x_live==849, "right pointer clamp failed"); pointer_tests=pointer_tests+1;
        drag(512); check_initial(); pointer_tests=pointer_tests+1;
        snapshot_once();

        at_ns(4000); pulse(8'h04); check(state_live==1, "OK did not launch the attached ball");
        at_ns(5000); ticks(78);
        check(ball_x_live==817 && ball_y_live==210 && score_live==0,
              "normal flight did not reach the first brick approach");
        at_ns(16000); case_id=2; tick_checked();
        check(calc_center_x==828 && calc_center_y==213
           && calc_brick_col==9 && calc_brick_row==4 && calc_brick_index==49
           && !brick49_alive && score_live==1 && bricks_remaining_live==49
           && vx_live==4 && vy_live==4 && ball_x_live==821 && ball_y_live==206,
              "first natural collision/index-49 clear failed");
        ticks(2);
        check(score_live==1 && bricks_remaining_live==49 && !brick49_alive,
              "the first hit was repeatedly scored on following ticks");
        check(score==0 && brick_alive_frame=={50{1'b1}}, "display changed without a zero-coordinate copy");
        snapshot_once();
        pixel_x=844; pixel_y=202; #0.001;
        check(pixel_rgb==24'h351A20, "cleared brick still rendered as a live brick");
        pixel_x=196; pixel_y=106; #0.001;
        check(pixel_rgb==24'hE3B341, "uncleared row-0 brick color mismatch");
        pixel_x=231; #0.001;
        check(pixel_rgb==24'h351A20, "four-pixel rendered brick gap color mismatch");
        pixel_x=128; pixel_y=250;

        at_ns(20000); case_id=3; pulse(8'h10);
        held_x=ball_x_live; held_y=ball_y_live; held_paddle=paddle_x_live;
        held_bricks=brick_alive_live;
        check(state_live==2, "Pause did not enter PAUSED");
        pulse(8'h83); drag(0); pulse(8'h80);
        check(state_live==2 && ball_x_live==held_x && ball_y_live==held_y
           && paddle_x_live==held_paddle && brick_alive_live==held_bricks
           && score_live==1 && lives_live==3, "PAUSED consumed movement/pointer/tick input");
        snapshot_once();
        at_ns(23000); pulse(8'h04);
        check(state_live==1, "OK did not resume PAUSED"); pause_tests=pause_tests+1;

        at_ns(24000); case_id=4; lose_life(40000,2); // regression: multiple-life branch
        at_ns(45000); pulse(8'h04); case_id=5; lose_life(70000,1);
        at_ns(75000); pulse(8'h04); case_id=6; lose_life(100000,0); // regression: final-life branch
        held_x=ball_x_live; held_y=ball_y_live; held_bricks=brick_alive_live;
        pulse(8'h93); drag(1023);
        check(state_live==5 && lives_live==0 && ball_x_live==held_x
           && ball_y_live==held_y && brick_alive_live==held_bricks,
              "OVER consumed movement/pause/pointer/ticks");
        snapshot_once(); pixel_x=512; pixel_y=300; #0.001;
        check(game_state==5 && pixel_rgb==24'hE05252, "OVER overlay/state mismatch");
        pixel_x=128; pixel_y=250;
        at_ns(105000); case_id=7; first_game_score=score_live; pulse(8'h04);
        repeat (3) @(negedge clk); #0.001; check_initial(); restart_tests=restart_tests+1;
        snapshot_once();

        at_ns(110000); pulse(8'h04); case_id=8; clear_all_bricks();
        snapshot_once();
        pixel_x=512; pixel_y=300; #0.001;
        check(game_state==4 && score==50 && pixel_rgb==24'h62D394,
              "WIN score/state/overlay or fourth-slot RGB mux mismatch");
        pixel_x=128; pixel_y=250;
        pulse(8'h93); drag(0);
        check(state_live==4 && score_live==50 && brick_alive_live==0,
              "WIN consumed movement/pause/pointer/ticks");

        at_ns(1100000); case_id=9; pulse(8'h04);
        repeat (3) @(negedge clk); #0.001; check_initial(); restart_tests=restart_tests+1;
        snapshot_once();
        pixel_x=505; pixel_y=522; #0.001;
        check(pixel_rgb==24'hFFE16A, "READY attached-ball color mismatch");
        pixel_x=460; pixel_y=540; #0.001;
        check(pixel_rgb==24'hF4F4F4, "paddle color mismatch");
        pixel_x=112; pixel_y=250; #0.001;
        check(pixel_rgb==24'hC45A5A, "field-border color mismatch");
        pixel_x=32; #0.001; check(pixel_rgb==24'h101820, "outside-field color mismatch");
        pixel_x=128; pixel_y=250;

        // Cancelling a page between registration and consumption must reset
        // pending and prevent a stale transaction from affecting reentry.
        at_ns(1120000); case_id=12; pulse(8'h04); ticks(78);
        at_ns(1140000); pulse(8'h80);
        check(brick_check_pending && brick_check_index==49 &&
              score_live==0 && brick49_alive,
              "page-cancellation setup missed the registered first candidate");
        ui_state_control=3'd1;
        repeat (3) @(negedge clk); #0.001;
        check(!brick_check_pending,"leaving page retained a pending candidate");
        check_initial(); cancelled_candidates=cancelled_candidates+1;
        ui_state_control=3'd5;
        repeat (3) @(negedge clk);

        // Async game reset between the two stages must also discard pending.
        at_ns(1150000); case_id=13; pulse(8'h04); ticks(78);
        at_ns(1180000); pulse(8'h80);
        check(brick_check_pending && brick_check_index==49,
              "async-reset cancellation setup missed its pending candidate");
        rst_n=1'b0; #0.001;
        check(!brick_check_pending && brick_check_index==0,
              "async reset retained a pending index/valid bit");
        check_initial(); cancelled_candidates=cancelled_candidates+1;
        repeat (3) @(negedge clk); rst_n=1'b1;

        at_ns(1200000); case_id=10; pulse(8'h08);
        check(state_live==0, "standalone Back changed game state instead of requesting a page exit");
        @(negedge clk); ui_state_control=4;
        pulse(8'h87); repeat (3) @(negedge clk); #0.001;
        check(!game_enable && enable==5'b00100, "breakout remained enabled on another page");
        check_initial(); pulse(8'h08);
        check(!dut.u_game4_breakout.exit_request, "disabled breakout requested exit");
        @(negedge clk); ui_state_control=5;
        pulse(8'h04); check(state_live==1 && score_live==0 && lives_live==3,
                               "page reentry did not start a fresh game");
        at_ns(1300000); case_id=11; rst_n=0; #0.001;
        check_initial();
        check(score==0 && game_state==0 && brick_alive_frame=={50{1'b1}},
              "asynchronous reset failed to restore displayed READY");
        at_ns(1301000); rst_n=1;
        at_ns(1950000);
        check(ready_tests==3 && pointer_tests==3 && pause_tests==1
           && loss_tests==3 && restart_tests==2 && win_tests==1
           && index0_cleared && index49_cleared && cleared_cell_queries>0
           && left_wall_bounces>0 && right_wall_bounces>0
           && top_wall_bounces>0 && paddle_bounces>0
           && reset_releases==2 && lock_losses==1
           && pixel_period_checks==8 && sys_period_checks==8
           && pipeline_hits==50+first_game_score && first_game_score>=1
           && pipeline_consumed>pipeline_hits
           && pipeline_candidates==pipeline_consumed+cancelled_candidates
           && empty_queries>0 && reference_checks>1000 && cancelled_candidates==2,
              "a required launch/wall/brick/life/pause/restart/win case was skipped");
        checks_done=1; checks_pass=(errors==0);
        if (checks_pass)
            $display("CH15 PASS: releases=%0d lock_losses=%0d candidates=%0d consumed=%0d hits=%0d empty=%0d cancelled=%0d reference_checks=%0d win=%0d errors=%0d",
                     reset_releases,lock_losses,pipeline_candidates,pipeline_consumed,
                     pipeline_hits,empty_queries,cancelled_candidates,reference_checks,win_tests,errors);
        else $display("CH15 FAIL: errors=%0d",errors);
    end
endmodule

// Chapter-13 comparison source: only the module name below is changed.
`timescale 1ns/1ps

// Chapter 12: 10 x 5 brick-breaker game for the verified 1024 x 600 LCD.
//
// The object sizes follow the tutorial: 14 x 14 ball, 112 x 16 paddle,
// 68 x 20 bricks with a four-pixel horizontal gap.  The original 800-pixel
// playfield is centred in the 1024-pixel panel.
module breakout_game_ch13_reference(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        game_enable,

    input  wire        event_left,
    input  wire        event_right,
    input  wire        event_ok,
    input  wire        event_back,
    input  wire        event_pause,
    input  wire        game_tick,

    input  wire [10:0] pointer_x,
    input  wire [9:0]  pointer_y,
    input  wire        pointer_down,

    input  wire [10:0] pixel_x,
    input  wire [9:0]  pixel_y,

    output wire        pixel_on,
    output reg  [23:0] pixel_rgb,
    output wire [15:0] score,
    output wire [3:0]  game_state,
    output wire        exit_request
);

    localparam integer FIELD_LEFT   = 112;
    localparam integer FIELD_RIGHT  = 912;
    localparam integer FIELD_TOP    = 64;
    localparam integer FIELD_BOTTOM = 590;

    localparam integer BALL_SIZE = 14;
    localparam integer PADDLE_W   = 112;
    localparam integer PADDLE_H   = 16;
    localparam integer PADDLE_Y   = 536;
    localparam integer PADDLE_STEP= 16;

    localparam integer BRICK_COLS  = 10;
    localparam integer BRICK_ROWS  = 5;
    localparam integer BRICK_W     = 68;
    localparam integer BRICK_H     = 20;
    localparam integer BRICK_PITCH_X = 72;
    localparam integer BRICK_PITCH_Y = 24;
    localparam integer BRICK_X0    = 162;
    localparam integer BRICK_Y0    = 96;

    localparam integer PADDLE_X_INIT = 456;
    localparam integer BALL_X_OFFSET  = 49;
    localparam integer BALL_Y_READY   = PADDLE_Y - BALL_SIZE;

    localparam [3:0]
        ST_READY     = 4'd0,
        ST_RUN       = 4'd1,
        ST_PAUSED    = 4'd2,
        ST_LIFE_LOST = 4'd3,
        ST_WIN       = 4'd4,
        ST_OVER      = 4'd5;

    localparam [23:0]
        C_OUTSIDE = 24'h101820,
        C_STATUS  = 24'h17212B,
        C_FIELD   = 24'h351A20,
        C_BORDER  = 24'hC45A5A,
        C_PADDLE  = 24'hF4F4F4,
        C_BALL    = 24'hFFE16A,
        C_YELLOW  = 24'hE3B341,
        C_GREEN   = 24'h62D394,
        C_RED     = 24'hE05252,
        C_ORANGE  = 24'hE8874A,
        C_PURPLE  = 24'h8E62C6,
        C_CYAN    = 24'h2A9DAD;

    reg [10:0] ball_x_live;
    reg [9:0]  ball_y_live;
    reg signed [5:0] vx_live;
    reg signed [5:0] vy_live;
    reg [10:0] paddle_x_live;
    reg [49:0] brick_alive_live;
    reg [5:0]  bricks_remaining_live;
    reg [2:0]  lives_live;
    reg [15:0] score_live;
    reg [3:0]  state_live;

    // LCD-frame snapshots avoid changing object positions halfway through a
    // raster scan.
    reg [10:0] ball_x_frame;
    reg [9:0]  ball_y_frame;
    reg [10:0] paddle_x_frame;
    reg [49:0] brick_alive_frame;
    reg [2:0]  lives_frame;
    reg [15:0] score_frame;
    reg [3:0]  state_frame;

    integer calc_x;
    integer calc_y;
    integer calc_vx;
    integer calc_vy;
    integer calc_center_x;
    integer calc_center_y;
    integer calc_brick_col;
    integer calc_brick_row;
    integer calc_brick_index;

    assign pixel_on     = 1'b1;
    assign score        = score_frame;
    assign game_state   = state_frame;
    assign exit_request = game_enable && event_back;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ball_x_live          <= PADDLE_X_INIT + BALL_X_OFFSET;
            ball_y_live          <= BALL_Y_READY;
            vx_live              <= 6'sd4;
            vy_live              <= -6'sd4;
            paddle_x_live        <= PADDLE_X_INIT;
            brick_alive_live     <= {50{1'b1}};
            bricks_remaining_live<= 6'd50;
            lives_live           <= 3'd3;
            score_live           <= 16'd0;
            state_live           <= ST_READY;

            ball_x_frame         <= PADDLE_X_INIT + BALL_X_OFFSET;
            ball_y_frame         <= BALL_Y_READY;
            paddle_x_frame       <= PADDLE_X_INIT;
            brick_alive_frame    <= {50{1'b1}};
            lives_frame          <= 3'd3;
            score_frame          <= 16'd0;
            state_frame          <= ST_READY;
        end else begin
            if ((pixel_x == 11'd0) && (pixel_y == 10'd0)) begin
                ball_x_frame      <= ball_x_live;
                ball_y_frame      <= ball_y_live;
                paddle_x_frame    <= paddle_x_live;
                brick_alive_frame <= brick_alive_live;
                lives_frame       <= lives_live;
                score_frame       <= score_live;
                state_frame       <= state_live;
            end

            if (!game_enable) begin
                ball_x_live           <= PADDLE_X_INIT + BALL_X_OFFSET;
                ball_y_live           <= BALL_Y_READY;
                vx_live               <= 6'sd4;
                vy_live               <= -6'sd4;
                paddle_x_live         <= PADDLE_X_INIT;
                brick_alive_live      <= {50{1'b1}};
                bricks_remaining_live <= 6'd50;
                lives_live            <= 3'd3;
                score_live            <= 16'd0;
                state_live            <= ST_READY;
            end else begin
                case (state_live)
                    ST_READY: begin
                        // The ball remains attached to the paddle before
                        // launch.  Keyboard/five-way/matrix and touch can all
                        // position the paddle.
                        ball_x_live <= paddle_x_live + BALL_X_OFFSET;
                        ball_y_live <= BALL_Y_READY;
                        vx_live     <= 6'sd4;
                        vy_live     <= -6'sd4;

                        if (pointer_down) begin
                            if (pointer_x <= FIELD_LEFT + PADDLE_W/2)
                                paddle_x_live <= FIELD_LEFT;
                            else if (pointer_x >= FIELD_RIGHT - PADDLE_W/2)
                                paddle_x_live <= FIELD_RIGHT - PADDLE_W;
                            else
                                paddle_x_live <= pointer_x - PADDLE_W/2;
                        end else if (event_left) begin
                            if (paddle_x_live <= FIELD_LEFT + PADDLE_STEP)
                                paddle_x_live <= FIELD_LEFT;
                            else
                                paddle_x_live <= paddle_x_live - PADDLE_STEP;
                        end else if (event_right) begin
                            if (paddle_x_live >= FIELD_RIGHT-PADDLE_W-PADDLE_STEP)
                                paddle_x_live <= FIELD_RIGHT - PADDLE_W;
                            else
                                paddle_x_live <= paddle_x_live + PADDLE_STEP;
                        end

                        if (event_ok)
                            state_live <= ST_RUN;
                    end

                    ST_RUN: begin
                        if (event_pause) begin
                            state_live <= ST_PAUSED;
                        end else begin
                            if (pointer_down) begin
                                if (pointer_x <= FIELD_LEFT + PADDLE_W/2)
                                    paddle_x_live <= FIELD_LEFT;
                                else if (pointer_x >= FIELD_RIGHT-PADDLE_W/2)
                                    paddle_x_live <= FIELD_RIGHT - PADDLE_W;
                                else
                                    paddle_x_live <= pointer_x - PADDLE_W/2;
                            end else if (event_left) begin
                                if (paddle_x_live <= FIELD_LEFT + PADDLE_STEP)
                                    paddle_x_live <= FIELD_LEFT;
                                else
                                    paddle_x_live <= paddle_x_live-PADDLE_STEP;
                            end else if (event_right) begin
                                if (paddle_x_live >= FIELD_RIGHT-PADDLE_W-PADDLE_STEP)
                                    paddle_x_live <= FIELD_RIGHT - PADDLE_W;
                                else
                                    paddle_x_live <= paddle_x_live+PADDLE_STEP;
                            end

                            if (game_tick) begin
                                calc_x  = $signed({1'b0,ball_x_live}) + vx_live;
                                calc_y  = $signed({1'b0,ball_y_live}) + vy_live;
                                calc_vx = vx_live;
                                calc_vy = vy_live;

                                if (calc_x <= FIELD_LEFT) begin
                                    calc_x  = FIELD_LEFT;
                                    calc_vx = (calc_vx < 0) ? -calc_vx : calc_vx;
                                end else if (calc_x >= FIELD_RIGHT-BALL_SIZE) begin
                                    calc_x  = FIELD_RIGHT-BALL_SIZE;
                                    calc_vx = (calc_vx > 0) ? -calc_vx : calc_vx;
                                end

                                if (calc_y <= FIELD_TOP) begin
                                    calc_y  = FIELD_TOP;
                                    calc_vy = (calc_vy < 0) ? -calc_vy : calc_vy;
                                end

                                // Downward crossing of the paddle top.
                                if ((calc_vy > 0) &&
                                    (ball_y_live + BALL_SIZE <= PADDLE_Y+4) &&
                                    (calc_y + BALL_SIZE >= PADDLE_Y) &&
                                    (calc_x + BALL_SIZE > paddle_x_live) &&
                                    (calc_x < paddle_x_live + PADDLE_W)) begin
                                    calc_y  = PADDLE_Y - BALL_SIZE;
                                    calc_vy = -((calc_vy < 0) ? -calc_vy : calc_vy);

                                    if (calc_x + BALL_SIZE/2 < paddle_x_live+PADDLE_W/3)
                                        calc_vx = -6;
                                    else if (calc_x + BALL_SIZE/2 >
                                             paddle_x_live+(PADDLE_W*2)/3)
                                        calc_vx = 6;
                                end

                                // Tutorial-compatible centre-point mapping
                                // into the 10 x 5 brick grid.
                                calc_center_x = calc_x + BALL_SIZE/2;
                                calc_center_y = calc_y + BALL_SIZE/2;
                                if ((calc_center_x >= BRICK_X0) &&
                                    (calc_center_x < BRICK_X0 +
                                     BRICK_COLS*BRICK_PITCH_X) &&
                                    (calc_center_y >= BRICK_Y0) &&
                                    (calc_center_y < BRICK_Y0 +
                                     BRICK_ROWS*BRICK_PITCH_Y)) begin
                                    calc_brick_col =
                                        (calc_center_x-BRICK_X0)/BRICK_PITCH_X;
                                    calc_brick_row =
                                        (calc_center_y-BRICK_Y0)/BRICK_PITCH_Y;
                                    calc_brick_index =
                                        calc_brick_row*BRICK_COLS+calc_brick_col;

                                    if ((calc_brick_index >= 0) &&
                                        (calc_brick_index < 50) &&
                                        brick_alive_live[calc_brick_index]) begin
                                        brick_alive_live[calc_brick_index] <= 1'b0;
                                        score_live <= score_live + 16'd1;
                                        bricks_remaining_live <=
                                            bricks_remaining_live - 6'd1;
                                        calc_vy = -calc_vy;

                                        if (bricks_remaining_live == 6'd1)
                                            state_live <= ST_WIN;
                                    end
                                end

                                ball_x_live <= calc_x[10:0];
                                ball_y_live <= calc_y[9:0];
                                vx_live     <= calc_vx[5:0];
                                vy_live     <= calc_vy[5:0];

                                if (calc_y >= FIELD_BOTTOM)
                                    state_live <= ST_LIFE_LOST;
                            end
                        end
                    end

                    ST_PAUSED: begin
                        if (event_pause || event_ok)
                            state_live <= ST_RUN;
                    end

                    ST_LIFE_LOST: begin
                        if (lives_live > 3'd1) begin
                            lives_live     <= lives_live - 3'd1;
                            ball_x_live    <= paddle_x_live + BALL_X_OFFSET;
                            ball_y_live    <= BALL_Y_READY;
                            vx_live        <= 6'sd4;
                            vy_live        <= -6'sd4;
                            state_live     <= ST_READY;
                        end else begin
                            lives_live <= 3'd0;
                            state_live <= ST_OVER;
                        end
                    end

                    ST_WIN: begin
                        if (event_ok) begin
                            paddle_x_live         <= PADDLE_X_INIT;
                            brick_alive_live      <= {50{1'b1}};
                            bricks_remaining_live <= 6'd50;
                            lives_live            <= 3'd3;
                            score_live            <= 16'd0;
                            state_live            <= ST_READY;
                        end
                    end

                    ST_OVER: begin
                        if (event_ok) begin
                            paddle_x_live         <= PADDLE_X_INIT;
                            brick_alive_live      <= {50{1'b1}};
                            bricks_remaining_live <= 6'd50;
                            lives_live            <= 3'd3;
                            score_live            <= 16'd0;
                            state_live            <= ST_READY;
                        end
                    end

                    default: state_live <= ST_READY;
                endcase
            end
        end
    end

    wire in_field =
        (pixel_x >= FIELD_LEFT) && (pixel_x < FIELD_RIGHT) &&
        (pixel_y >= FIELD_TOP)  && (pixel_y < FIELD_BOTTOM);

    wire ball_pixel =
        (pixel_x >= ball_x_frame) &&
        (pixel_x <  ball_x_frame + BALL_SIZE) &&
        (pixel_y >= ball_y_frame) &&
        (pixel_y <  ball_y_frame + BALL_SIZE);

    wire paddle_pixel =
        (pixel_x >= paddle_x_frame) &&
        (pixel_x <  paddle_x_frame + PADDLE_W) &&
        (pixel_y >= PADDLE_Y) &&
        (pixel_y <  PADDLE_Y + PADDLE_H);

    wire in_brick_region =
        (pixel_x >= BRICK_X0) &&
        (pixel_x < BRICK_X0 + BRICK_COLS*BRICK_PITCH_X) &&
        (pixel_y >= BRICK_Y0) &&
        (pixel_y < BRICK_Y0 + BRICK_ROWS*BRICK_PITCH_Y);

    wire [10:0] brick_rel_x = pixel_x - BRICK_X0;
    wire [9:0]  brick_rel_y = pixel_y - BRICK_Y0;
    wire [3:0] render_brick_col = brick_rel_x / BRICK_PITCH_X;
    wire [2:0] render_brick_row = brick_rel_y / BRICK_PITCH_Y;
    wire [6:0] render_brick_index =
        render_brick_row * BRICK_COLS + render_brick_col;
    wire render_brick_inner =
        ((brick_rel_x % BRICK_PITCH_X) < BRICK_W) &&
        ((brick_rel_y % BRICK_PITCH_Y) < BRICK_H);
    wire brick_pixel = in_brick_region && render_brick_inner &&
        (render_brick_index < 50) &&
        brick_alive_frame[render_brick_index];

    integer life_i;
    always @(*) begin
        pixel_rgb = C_OUTSIDE;

        if (pixel_y < FIELD_TOP)
            pixel_rgb = C_STATUS;
        else if (in_field)
            pixel_rgb = C_FIELD;

        if (in_field &&
            ((pixel_x == FIELD_LEFT) || (pixel_x == FIELD_RIGHT-1) ||
             (pixel_y == FIELD_TOP)))
            pixel_rgb = C_BORDER;

        if (brick_pixel) begin
            case (render_brick_row)
                3'd0: pixel_rgb = C_YELLOW;
                3'd1: pixel_rgb = C_ORANGE;
                3'd2: pixel_rgb = C_RED;
                3'd3: pixel_rgb = C_PURPLE;
                default: pixel_rgb = C_CYAN;
            endcase
        end

        if (paddle_pixel)
            pixel_rgb = C_PADDLE;
        if (ball_pixel)
            pixel_rgb = C_BALL;

        // Score bar: each removed brick adds twelve pixels.
        if ((pixel_y >= 10'd24) && (pixel_y < 10'd40) &&
            (pixel_x >= FIELD_LEFT) &&
            (pixel_x < FIELD_LEFT + score_frame*12))
            pixel_rgb = C_YELLOW;

        // Three life blocks in the upper-right status area.
        for (life_i = 0; life_i < 3; life_i = life_i + 1) begin
            if ((life_i < lives_frame) &&
                (pixel_x >= 11'd790 + life_i*36) &&
                (pixel_x <  11'd814 + life_i*36) &&
                (pixel_y >= 10'd20) && (pixel_y < 10'd44))
                pixel_rgb = C_RED;
        end

        if ((state_frame == ST_READY) &&
            (pixel_x >= 11'd384) && (pixel_x < 11'd640) &&
            (pixel_y >= 10'd270) && (pixel_y < 10'd350))
            pixel_rgb = C_YELLOW;

        if ((state_frame == ST_PAUSED) &&
            (pixel_x >= 11'd384) && (pixel_x < 11'd640) &&
            (pixel_y >= 10'd270) && (pixel_y < 10'd350))
            pixel_rgb = C_YELLOW;

        if ((state_frame == ST_LIFE_LOST) &&
            (pixel_x >= 11'd360) && (pixel_x < 11'd664) &&
            (pixel_y >= 10'd260) && (pixel_y < 10'd360))
            pixel_rgb = C_ORANGE;

        if ((state_frame == ST_WIN) &&
            (pixel_x >= 11'd340) && (pixel_x < 11'd684) &&
            (pixel_y >= 10'd240) && (pixel_y < 10'd360))
            pixel_rgb = C_GREEN;

        if ((state_frame == ST_OVER) &&
            (pixel_x >= 11'd320) && (pixel_x < 11'd704) &&
            (pixel_y >= 10'd230) && (pixel_y < 10'd370))
            pixel_rgb = C_RED;
    end

endmodule
