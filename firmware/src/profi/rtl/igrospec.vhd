-- --------------------------------------------------------------------
-- IgroSpec rev.B firmware
-- v1.0
-- (c) 2019 Andy Karpov
-- (c) 2022 Oleh Starychenko
-- --------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity igrospec is
	port(
		-- Clock
		CLK28				: in std_logic;
		CLKX 				: in std_logic;

		-- CPU signals
		CLK_CPU			: out std_logic := '1';
		N_RESET			: in std_logic;
		N_INT				: out std_logic := '1';
		N_RD				: in std_logic;
		N_WR				: in std_logic;
		N_IORQ			: in std_logic;
		N_MREQ			: in std_logic;
		N_M1				: in std_logic;
		A					: in std_logic_vector(15 downto 0);
		D 					: inout std_logic_vector(7 downto 0) := "ZZZZZZZZ";
		
		-- Unused CPU signals
		N_BUSREQ 		: in std_logic;
		N_BUSACK 		: in std_logic;
		N_WAIT 			: in std_logic;
		N_HALT			: in std_logic;
		N_NMI 			: inout std_logic := 'Z';
		N_RFSH			: in std_logic;		

		-- RAM 
		MA 				: out std_logic_vector(18 downto 0);
		MD 				: inout std_logic_vector(7 downto 0) := "ZZZZZZZZ";
		N_MRD1			: out std_logic := '1';
		N_MWR1			: out std_logic := '1';
		N_MRD2			: out std_logic := '1';
		N_MWR2			: out std_logic := '1';
		
		-- VRAM 
		VA 				: out std_logic_vector(14 downto 0) := "000000000000000";
		VD 				: inout std_logic_vector(7 downto 0) := "ZZZZZZZZ";
		N_VRAMWR			: out std_logic := '1';

		-- ROM
		N_ROMCS			: out std_logic := '1';
		N_ROMWR			: out std_logic := '1';
		ROM_A14 			: out std_logic := '0';
		ROM_A15 			: out std_logic := '0';
		ROM_A16 			: out std_logic := '0';
		ROM_A17 			: out std_logic := '0';
		ROM_A18 			: out std_logic := '0';
		
		-- ZX BUS signals
		BUS_N_IORQGE 	: in std_logic := '0';
		BUS_N_ROMCS 	: in std_logic := '1';
		CLK_BUS 			: out std_logic := '1';
		BUS_N_RDR	 	: in std_logic := '1';
		BUS_RS 			: in std_logic := '0';
		BUS_BLK		 	: in std_logic := '0';
		BUS_N_DOS	 	: out std_logic := '1';
		BUS_F			 	: out std_logic := '0';
		BUS_N_IODOS	 	: out std_logic := '1';

		-- Video
		VIDEO_CSYNC    : out std_logic;
		VIDEO_R       	: out std_logic_vector(2 downto 0) := "000";
		VIDEO_G       	: out std_logic_vector(2 downto 0) := "000";
		VIDEO_B       	: out std_logic_vector(2 downto 0) := "000";

		-- Interfaces 
		TAPE_IN 			: in std_logic;
		TAPE_OUT			: out std_logic := '1';
		BEEPER			: out std_logic := '1';

		-- AY
		CLK_AY			: out std_logic;
		AY_BC1			: out std_logic;
		AY_BDIR			: out std_logic;

		-- SD card
		SD_CLK 			: out std_logic := '0';
		SD_DI 			: out std_logic;
		SD_DO 			: in std_logic;
		SD_N_CS 			: out std_logic := '1';
		CF_N_CS 			: out std_logic := '1';
		
		-- Keyboard
		KB					: in std_logic_vector(4 downto 0) := "11111";
		-- TODO: extra signals KB 7 downto 5
		
		-- Other in signals
		TURBO				: in std_logic := '0';
		SPECIAL			: in std_logic := '0';
		IO8 				: in std_logic := '0';		
		IO11 				: in std_logic := '0';		
		IO12 				: in std_logic := '0';		
		IO15 				: in std_logic := '0';
		IO16 				: in std_logic := '0';		
		IO19 				: in std_logic := '0';
		IO21				: in std_logic := '0';				
		IO24 				: in std_logic := '0';		
		IO26 				: in std_logic := '0';
		IO27 				: in std_logic := '0';
		IO64 				: in std_logic := '0';
		IOCLR				: in std_logic := '0';
		IOE				: in std_logic;
		MAPCOND 			: out std_logic;
		BTN_NMI			: in std_logic := '1'

	);
end igrospec;

architecture rtl of igrospec is

	component zcontroller is
	 port (
		RESET				: in std_logic;
		CLK    			: in std_logic;
		A   			   : in std_logic;
		DI					: in std_logic_vector(7 downto 0);
		DO					: out std_logic_vector(7 downto 0);
		RD					: in std_logic;
		WR					: in std_logic;
		SDDET				: in std_logic;
		SDPROT			: in std_logic;
		CS_n				: out std_logic;
		SCLK				: out std_logic;
		MOSI				: out std_logic;
		MISO				: in std_logic );
	 end component;

	signal reset      : std_logic := '0';

	signal CLK 			: std_logic := '0';	
	signal clk_div2 		: std_logic := '0';
	signal clk_div4 		: std_logic := '0';
	signal clk_div8 	: std_logic := '0';
	signal clk_div16	: std_logic := '0';

--	signal clk_int   	: std_logic := '0'; -- 7MHz short pulse to access zx bus
	signal clk_vid 	: std_logic := '0'; -- 7MHz inversed and delayed short pulse to access video memory
	signal clk_pix		: std_logic := '0';
	
	signal buf_md		: std_logic_vector(7 downto 0) := "11111111";
	signal is_buf_wr	: std_logic := '0';	
	
	signal invert   	: unsigned(4 downto 0) := "00000";

	signal chr_col_cnt: unsigned(2 downto 0) := "000"; -- Character column counter
	signal chr_row_cnt: unsigned(2 downto 0) := "000"; -- Character row counter

	signal hor_cnt  	: unsigned(6 downto 0) := "0000000"; -- Horizontal counter
	signal ver_cnt  	: unsigned(5 downto 0) := "000000"; -- Vertical counter

	signal attr     	: std_logic_vector(7 downto 0);
	signal shift    	: std_logic_vector(7 downto 0);
	
	signal paper_r  	: std_logic;
	signal blank_r  	: std_logic;
	signal attr_r   	: std_logic_vector(7 downto 0);
	signal shift_r  	: std_logic_vector(7 downto 0);
	signal rgbi 	 	: std_logic_vector(3 downto 0);
	signal int  		: std_logic;

	signal border_attr: std_logic_vector(2 downto 0) := "000";

	signal port_7ffd	: std_logic_vector(5 downto 0); -- D0-D2 - RAM page from address #C000
																	  -- D3 - video RAM page: 0 - bank5, 1 - bank7 
																	  -- D4 - ROM page A14: 0 - basic 128, 1 - basic48
																	  -- D5 - 48k RAM lock, 1 - locked, 0 - extended memory enabled
																	  -- D6 - not used
																	  -- D7 - not used
	
	signal port_dffd  : std_logic_vector(7 downto 0); -- D0 - RAM A17'
																	  -- D1 - RAM A18'
																	  -- D2 - RAM A19'
																	  -- D3 - sco
																	  -- D4 - norom
																	  -- D5 - cpm
																	  -- D6 - scr
																	  -- D7 - ds80
																	  
	signal sco			: std_logic := '0';
	signal norom		: std_logic := '0';
	signal cpm			: std_logic := '0';
	signal scr			: std_logic := '0';
	signal ds80			: std_logic := '0';

	signal ay_port		: std_logic := '0';
		
	signal vbus_req	: std_logic := '1';
	signal vbus_ack	: std_logic := '1';
	signal vbus_mode	: std_logic := '1';	
	signal vbus_rdy	: std_logic := '1';
	
	signal vid_rd		: std_logic := '0';
	
	signal paper     	: std_logic;

	signal hsync     	: std_logic := '1';
	signal vsync     	: std_logic := '1';

	signal vram_acc	: std_logic;
	
	signal mux 			: std_logic_vector(1 downto 0);
	
	signal n_is_ram   : std_logic := '1';
	signal kb_512		: std_logic := '0';
	signal ram_page	: std_logic_vector(5 downto 0) := "000000";
	signal vid_page	: std_logic_vector(5 downto 0) := "000000";
	signal sram_page	: std_logic_vector(5 downto 0) := "000000";

	signal n_is_rom   : std_logic := '1';
	signal rom_page	: std_logic_vector(1 downto 0) := "00";
	
	signal sound_out 	: std_logic := '0';
	signal ear 			: std_logic := '1';
	signal mic 			: std_logic := '0';
	signal port_read	: std_logic := '0';
	signal port_write	: std_logic := '0';
	
	signal fd_port 	: std_logic;
	signal fd_sel 		: std_logic;
	
	signal zc_do_bus	: std_logic_vector(7 downto 0);
	signal zc_wr 		: std_logic :='0';
	signal zc_rd		: std_logic :='0';
	
	signal trdos		: std_logic :='0';

begin
	reset <= not(N_RESET);

	n_is_rom <= '0' when N_MREQ = '0' and A(15 downto 14)  = "00" and norom = '0' else '1';
	n_is_ram <= '0' when N_MREQ = '0' and n_is_rom = '1' else '1';

	-- pentagon ROM banks map (A14, A15):
	-- 00 - bank 0, He Gluk Reset Service
	-- 01 - bank 1, TR-DOS
	-- 10 - bank 2, Basic-128
	-- 11 - bank 3, Basic-48
	rom_page <= trdos & port_7ffd(4);

	ROM_A14 <= rom_page(0);
	ROM_A15 <= rom_page(1);
	ROM_A16 <= '0';
	ROM_A17 <= '0';
	ROM_A18 <= '0';
	
	N_ROMCS <= '0' when n_is_rom = '0' and N_RD = '0' and BUS_N_ROMCS = '0' else '1';
	N_ROMWR <= '1';
	
	mux <= A(15 downto 14);

process (mux, port_7ffd, port_dffd, sco, scr)
	begin
		case mux is

			when "00" =>	ram_page <= "000000";                 -- Seg0 ROM 0000-3FFF or Seg0 RAM 0000-3FFF	
			when "01" =>	if sco = '0' then
									ram_page <= "000101";
								else 
									ram_page <= port_dffd(2 downto 0) & port_7ffd(2 downto 0);
								end if;
			when "10" =>	if scr = '0' then
									ram_page <= "000010";
								else
									ram_page <= "000110";
								end if;
			when "11" =>	if sco = '0' then
									ram_page <= port_dffd(2 downto 0) & port_7ffd(2 downto 0);
								else
									ram_page <= "000111";
								end if;
			when others => null;
		end case;
	end process;
	
	MA(13 downto 0) <= A(13 downto 0) when vbus_mode = '0' else 
		std_logic_vector( "0" & ver_cnt(4 downto 3) & chr_row_cnt & ver_cnt(2 downto 0) & hor_cnt(4 downto 0) ) when vid_rd = '0' else
		std_logic_vector( "0110" & ver_cnt(4 downto 0) & hor_cnt(4 downto 0) );
	sram_page <= ram_page when vbus_mode = '0' else
					"0001" & port_7ffd(3) & '1' when vbus_mode = '1' and ds80 = '0' else -- spectrum screen ;
					"0001" & port_7ffd(3) & '0' when vbus_mode = '1' and ds80 = '1' and vid_rd = '0' else -- profi bitmap 
					"1110" & port_7ffd(3) & '0' when vbus_mode = '1' and ds80 = '1' and vid_rd = '1' else -- profi attributes
					"000000";
	
	MA (18 downto 14) <= sram_page(4 downto 0);
	kb_512 <= sram_page(5);
	
	MD(7 downto 0) <= 
		D(7 downto 0) when vbus_mode = '0' and ((n_is_ram = '0' or (N_IORQ = '0' and N_M1 = '1')) and N_WR = '0') else 
		(others => 'Z');

	vbus_req <= '0' when ( N_MREQ = '0' or N_IORQ = '0' ) and ( N_WR = '0' or N_RD = '0' ) else '1';
	vbus_rdy <= '0' when clk_vid = '1' or chr_col_cnt(0) = '0' else '1';
	
	N_MRD1 <= '0' when ((vbus_mode = '1' and vbus_rdy = '0') or (vbus_mode = '0' and N_RD = '0' and N_MREQ = '0')) and kb_512 = '0' else '1';  
	N_MWR1 <= '0' when vbus_mode = '0' and n_is_ram = '0' and N_WR = '0' and chr_col_cnt(0) = '0' and kb_512 = '0' else '1';
	N_MRD2 <= '0' when ((vbus_mode = '1' and vbus_rdy = '0') or (vbus_mode = '0' and N_RD = '0' and N_MREQ = '0')) and kb_512 = '1' else '1';  
	N_MWR2 <= '0' when vbus_mode = '0' and n_is_ram = '0' and N_WR = '0' and chr_col_cnt(0) = '0' and kb_512 = '1' else '1';   

	VIDEO_R <= rgbi(3) & rgbi(0) & '0';
	VIDEO_G <= rgbi(2) & rgbi(0) & '0';
	VIDEO_B <= rgbi(1) & rgbi(0) & '0';
	VIDEO_CSYNC <= not (vsync xor hsync);
	
	BEEPER <= sound_out;
	TAPE_OUT <= mic;
	ear <= TAPE_IN;

	CLK_AY <= clk_div16;
	ay_port <= '1' when A(7 downto 0) = x"FD" and A(15)='1' and BUS_N_IORQGE = '0' else '0';
	AY_BC1 <= '1' when ay_port = '1' and A(14) = '1' and N_IORQ = '0' and (N_WR='0' or N_RD='0') else '0';
	AY_BDIR <= '1' when ay_port = '1' and N_IORQ = '0' and N_WR = '0' else '0';
	
	N_NMI <= '0' when BTN_NMI = '0' else 'Z';
	MAPCOND <= '1';

	-- TODO: turbo for internal bus / video memory
--	clk_int <= clk_div2 and clk_div4;-- when TURBO = '0' else CLK28 and clk_div2; -- internal clock for counters
	clk_vid <= not(clk_div2) and not(clk_div4);-- when TURBO = '0' else CLK28 and not(clk_div2); --when TURBO = '0' else CLK28 and not(clk_div2) and not(clk_div4); -- internal clock for video read
	
	-- todo
	process( clk_div2, clk_div4 )
	begin
	-- rising edge of CLK14
		if clk_div2'event and clk_div2 = '1' then
			if clk_div4 = '1' then
				CLK_CPU <= clk_div8;
				CLK_BUS <= not clk_div8;
			end if;
		end if;
	end process;
	
	is_buf_wr <= '1' when vbus_mode = '0' and chr_col_cnt(0) = '0' else '0';
	
	-- fill memory buf
	process(is_buf_wr, MD)
	begin 
		if (is_buf_wr'event and is_buf_wr = '0') then  -- high to low transition to lattch the MD into BUF
			buf_md(7 downto 0) <= MD(7 downto 0);
		end if;
	end process;
	 
	port_read <= '1' when N_IORQ = '0' and N_RD = '0' and N_M1 = '1' and BUS_N_IORQGE = '0' else '0';
	
	-- read ports by CPU
	D(7 downto 0) <= 
		buf_md(7 downto 0) when n_is_ram = '0' and N_RD = '0' else -- MD buf	
		'1' & ear & '1' & KB(4 downto 0) when port_read = '1' and A(0) = '0' else -- #FE
--		port_7ffd when port_read = '1' and A = X"7FFD" else -- #7FFD
--		port_1ffd when port_read = '1' and A = X"1FFD" else -- #1FFD
--		port_dffd when port_read = '1' and A = X"DFFD" else -- #DFFD
		zc_do_bus when port_read = '1' and A(7 downto 6) = "01" and A(4 downto 0) = "10111" else -- Z-controller
--		attr_r when port_read = '1' and A(7 downto 0) = "11111111" else -- #FF
		"ZZZZZZZZ";

	-- z-controller 
	zc_wr <= '1' when (N_IORQ = '0' and N_WR = '0' and A(7 downto 6) = "01" and A(4 downto 0) = "10111") else '0';
	zc_rd <= '1' when (N_IORQ = '0' and N_RD = '0' and A(7 downto 6) = "01" and A(4 downto 0) = "10111") else '0';
	
	-- clocks
	 -- main clock selector
	 U0: entity work.clk_mux
	 port map(
		data0 => CLK28,
		data1 => CLKX,
		sel => ds80,
		result => CLK
	 );
	 
	 U1: entity work.clk_pix_mux
	 port map(
		data0 => clk_div4,
		data1 => clk_div2,
		sel => ds80,
		result => clk_pix
	 );
	
	-- clocks
	process (CLK, clk_div2)
	begin 
		if (CLK'event and CLK = '1') then 
			clk_div2 <= not(clk_div2);
		end if;
	end process;
	
	process (clk_div2, clk_div4)
	begin 
		if (clk_div2'event and clk_div2 = '1') then 
			clk_div4 <= not(clk_div4);
		end if;
	end process;
	
	process (clk_div4, clk_div8)
	begin 
		if (clk_div4'event and clk_div4 = '1') then 
			clk_div8 <= not(clk_div8);
		end if;
	end process;

	process (clk_div8, clk_div16)
	begin 
		if (clk_div8'event and clk_div8 = '1') then 
			clk_div16 <= not(clk_div16);
		end if;
	end process;
	
	-- sync, counters
	process( clk, clk_pix, chr_col_cnt, hor_cnt, chr_row_cnt, ver_cnt, int)
	begin
		if clk'event and clk = '1' then
		
			if clk_pix = '1' then
			
				if chr_col_cnt = 7 then
				
					if (hor_cnt = 55 and ds80 = '0') or (hor_cnt = 95 and ds80 = '1') then					-- точки
						hor_cnt <= (others => '0');
					else
						hor_cnt <= hor_cnt + 1;
					end if;
					
					if (hor_cnt = 39 and ds80 = '0') or (hor_cnt = 71 and ds80 = '1') then
						if chr_row_cnt = 7 then
							if (ver_cnt = 39 and ds80 = '0') or (ver_cnt = 38 and ds80 = '1') then			-- строки 39 для Пентагона, 38 для Спектрума и Профи
								ver_cnt <= (others => '0');
								invert <= invert + 1;
							else
								ver_cnt <= ver_cnt + 1;
							end if;
						end if;
						chr_row_cnt <= chr_row_cnt + 1;
					end if;
				end if;

				-- h/v sync

				if chr_col_cnt = 7 then

					if (hor_cnt(5 downto 2) = "1010" and ds80 = '0') or (hor_cnt(6 downto 3) = "1001" and ds80 = '1') then 
						hsync <= '0';
					else 
						hsync <= '1';
					end if;
					
					if ds80 = '0' then
						if ver_cnt /= 31 then
							vsync <= '0';
						elsif chr_row_cnt = 3 or chr_row_cnt = 4 or ( chr_row_cnt = 5 and ( hor_cnt >= 40 or hor_cnt < 12 ) ) then
							vsync <= '1';
						else 
							vsync <= '0';
						end if;
					else
						if ver_cnt (5 downto 2) = 8 and ver_cnt(0)='0' and chr_row_cnt = 7 then
							vsync <= '1';
						else 
							vsync <= '0';
						end if;
					end if;
					
				end if;
			
				-- int
				if chr_col_cnt = 6 and hor_cnt(2 downto 0) = "111" then
					if ver_cnt = 29 and chr_row_cnt = 7 and hor_cnt(5 downto 3) = "100" then
						int <= '0';
					else
						int <= '1';
					end if;
				end if;

				chr_col_cnt <= chr_col_cnt + 1;
			end if;
		end if;
	end process;

	-- video mem
	process( clk, clk_pix, chr_col_cnt, vbus_mode, vid_rd, vbus_req, vbus_ack )
	begin
		-- lower edge of 7 mhz clock
		if clk'event and clk = '1' then 
			if chr_col_cnt(0) = '1' and clk_pix = '0' then
			
				if vbus_mode = '1' then
					if vid_rd = '0' then
						shift <= MD;
					else
						attr  <= MD;
					end if;
				end if;
				
				if vbus_req = '0' and vbus_ack = '1' then
					vbus_mode <= '0';
				else
					vbus_mode <= '1';
					vid_rd <= not vid_rd;
				end if;	
				vbus_ack <= vbus_req;
			end if;
		end if;
	end process;

	-- r/g/b
	process( clk, clk_pix, paper_r, shift_r, attr_r, invert, blank_r )
	begin
		if clk'event and clk = '1' then
			if (clk_pix  = '1') then
				if paper_r = '0' then           
					if( shift_r(7) xor ( attr_r(7) and invert(4) ) ) = '1' then
						rgbi(3) <= attr_r(1);
						rgbi(2) <= attr_r(2);
						rgbi(1) <= attr_r(0);
					else
						rgbi(3) <= attr_r(4);
						rgbi(2) <= attr_r(5);
						rgbi(1) <= attr_r(3);
					end if;
				else
					if blank_r = '0' then
						rgbi(3 downto 1) <= "000";
					else
						rgbi(3) <= border_attr(1);
						rgbi(2) <= border_attr(2);
						rgbi(1) <= border_attr(0);
					end if;
				end if;
			end if;
		end if;
	end process;

	-- brightness
	process( clk, clk_pix, paper_r, attr_r, rgbi(3 downto 1) )
	begin
		if clk'event and clk = '1' then
			if (clk_pix = '1') then
				if paper_r = '0' and attr_r(6) = '1' and rgbi(3 downto 1) /= "000" then
					rgbi(0) <= '1';
				else
					rgbi(0) <= '0';
				end if;
			end if;
		end if;
	end process;

	paper <= '0' when ((hor_cnt(5) = '0' and ver_cnt(5 downto 0) < 24 and ds80 = '0') or				--256x192
							 (hor_cnt(6) = '0' and ver_cnt(5 downto 0) < 30 and ds80 = '1')) else '1';  	--512x240  

	-- paper, blank
	process( clk, clk_pix, chr_col_cnt, hor_cnt, ver_cnt )
	begin
		if clk'event and clk = '1' then
			if (clk_pix = '1') then
				if chr_col_cnt = 7 then
					attr_r <= attr;
					shift_r <= shift;

					if (((hor_cnt(5 downto 0) > 38 and hor_cnt(5 downto 0) < 48) or ver_cnt(5 downto 1) = 15) and ds80 = '0') or												--256x192
						(((hor_cnt(6 downto 0) > 67 and hor_cnt(6 downto 0) < 91) or (ver_cnt(5 downto 0) > 32 and ver_cnt(5 downto 0) < 36)) and ds80 = '1')	then	--512x240
						blank_r <= '0';
					else 
						blank_r <= '1';
					end if;
					
					paper_r <= paper;
				else
					shift_r(7 downto 1) <= shift_r(6 downto 0);
					shift_r(0) <= '0';
				end if;
			end if;
		end if;
	end process;
	
N_INT <= int;

	-- #FD port correction
	fd_sel <= '0' when D(7 downto 4) = "1101" and D(2 downto 0) = "011" else '1'; -- IN, OUT Z80 Command Latch

	process(fd_sel, N_M1, reset)
	begin
		if reset='1' then
			fd_port <= '1';
		elsif rising_edge(N_M1) then 
			fd_port <= fd_sel;
		end if;
	end process;
	
	BUS_N_DOS <= trdos; -- 0 - boot into service rom, 1 - boot into 128 menu
	port_write <= '1' when N_IORQ = '0' and N_WR = '0' and N_M1 = '1' and vbus_mode = '0' else '0';
	
	-- ports, write by CPU
	process( clk, clk_div2, clk_div4, reset, A, D, port_write, fd_port, port_7ffd, N_M1, N_MREQ, norom )
	begin
		if reset = '1' then
			port_7ffd <= "000000";
			port_dffd <= "00000000";
			sound_out <= '0';
			mic <= '0';
			trdos <= '0';
		elsif clk'event and clk = '1' then 
			if clk_div2 = '1' then
				if port_write = '1' then

					 -- port #7FFD  
					if A(15)='0' and A(1) = '0' and (port_7ffd(5) = '0' or norom = '1')  then
						port_7ffd <= D(5 downto 0);
					end if;
					 
					 -- port #DFFD (ram ext)
					if A = X"DFFD" and fd_port='1' then  
							port_dffd <= D;
					end if;
					
					-- port #FE
					if A(0) = '0' then
						border_attr <= D(2 downto 0); -- border attr
						mic <= D(3); -- MIC
						sound_out <= D(4); -- BEEPER
					end if;
				end if;
				
				-- trdos flag
				if N_M1 = '0' and N_MREQ = '0' and A(15 downto 8) = X"3D" and port_7ffd(4) = '1' then 
					trdos <= '0';
				elsif N_M1 = '0' and N_MREQ = '0' and A(15 downto 14) /= "00" then 
					trdos <= '1'; 
				end if;
			end if;
		end if;
	end process;

sco 	<= port_dffd (3);
norom <= port_dffd (4);
cpm 	<= port_dffd (5);
scr 	<= port_dffd (6);
ds80 	<= port_dffd (7);

	--VRAM
VA <= "000000000000000";
N_VRAMWR <= '1';

	--ZX-BUS Clock
BUS_F <= clk;
BUS_N_IODOS <= not cpm;

	-- CF Card
CF_N_CS <= '1';
	
	--ZC
	U2: zcontroller 
	port map(
		RESET	 	=> reset,
		CLK 		=> clk_div4,
		A 			=> A(5),
		DI 		=> D,
		DO 		=> zc_do_bus,
		RD 		=> zc_rd,
		WR 		=> zc_wr,
		SDDET 	=> '0',
		SDPROT 	=> '0',
		CS_n 		=> SD_N_CS,
		SCLK 		=> SD_CLK,
		MOSI 		=> SD_DI,
		MISO 		=> SD_DO
	);

end;