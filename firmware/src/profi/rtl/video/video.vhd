-------------------------------------------------------------------------------
-- VIDEO Controller
-------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;

entity video is
	port (
		CLK2X 	: in std_logic; -- 28 MHz
		CLK		: in std_logic; -- 14 MHz
		ENA		: in std_logic; -- 7 MHz
		
		N_RESET	: in std_logic;

		BORDER	: in std_logic_vector(7 downto 0);	-- bordr color (port #xxFE)
		PAL_ADR	: in std_logic_vector(7 downto 0);	-- pal color (port #xxFE)
		DI			: in std_logic_vector(7 downto 0);	-- video data from memory
		TURBO 	: in std_logic := '0'; -- 1 = turbo mode, 0 = normal mode
		INTA		: in std_logic := '0'; -- int request for turbo mode
		INT		: out std_logic; -- int output
		ATTR_O	: out std_logic_vector(7 downto 0); -- attribute register output
		A			: out std_logic_vector(13 downto 0); -- video address
		pFF_CS	: out std_logic; -- port FF select

		VIDEO_R	: out std_logic_vector(2 downto 0);
		VIDEO_G	: out std_logic_vector(2 downto 0);
		VIDEO_B	: out std_logic_vector(2 downto 0);
		
		HSYNC		: buffer std_logic;
		VSYNC		: buffer std_logic;
		CSYNC		: out std_logic;
		
		DS80		: in std_logic; -- 1 = Profi CP/M mode. 0 = standard mode
		CS7E 		: in std_logic := '0';
		BUS_A 	: in std_logic_vector(15 downto 8);
		BUS_WR_N : in std_logic;
		GX0 		: out std_logic;
		
		-- VRAM 
		VA 				: out std_logic_vector(14 downto 0) := "000000000000000";
		VD 				: inout std_logic_vector(7 downto 0) := "ZZZZZZZZ";
		N_VRAMWR			: out std_logic := '1';
		
		VBUS_MODE : in std_logic := '0'; -- 1 = video bus, 2 = cpu bus
		VID_RD : in std_logic -- 1 = read attribute, 0 = read pixel data
	);
end entity;

architecture rtl of video is

	signal rgb 	 		: std_logic_vector(2 downto 0);
	signal i 			: std_logic;
	
	signal palette		: std_logic_vector(15 downto 0) := x"0000";
	
	signal palette_a 	: std_logic_vector(3 downto 0);
	signal palette_wr_data 	: std_logic_vector(8 downto 0);
	signal palette_wr : std_logic := '0';
	signal palette_grb: std_logic_vector(8 downto 0);
	signal palette_grb_reg: std_logic_vector(8 downto 0);

	signal invert   : unsigned(4 downto 0) := "00000";

	signal chr_col_cnt : unsigned(2 downto 0) := "000"; -- Character column counter
	signal chr_row_cnt : unsigned(2 downto 0) := "000"; -- Character row counter

	signal hor_cnt  : unsigned(6 downto 0) := "0000000"; -- Horizontal char counter
	signal ver_cnt  : unsigned(5 downto 0) := "000000"; -- Vertical char counter
	
	signal attr     : std_logic_vector(7 downto 0);
	signal bitmap    : std_logic_vector(7 downto 0);
	
	signal paper_r  : std_logic;
	signal blank_r  : std_logic;
	signal attr_r   : std_logic_vector(7 downto 0);

	signal shift_r  : std_logic_vector(7 downto 0);
	signal shift_hr_r : std_logic_vector(15 downto 0);

	signal paper     : std_logic;
	
	signal i78     : std_logic;

	signal bl_int     : std_logic;	
		
	signal int_sig : std_logic;
		
begin

	-- sync, counters
	process( CLK2X, CLK, ENA, chr_col_cnt, hor_cnt, chr_row_cnt, ver_cnt, TURBO, INTA)
	begin
		if CLK2X'event and CLK2X = '1' then
		if DS80 = '0' then						-- pentagon
			if CLK = '1' and ENA = '1' then
			
				if chr_col_cnt = 7 then
				
					if hor_cnt = 55 then
						hor_cnt <= (others => '0');
					else
						hor_cnt <= hor_cnt + 1;
					end if;
					
					if hor_cnt = 39 then
						if chr_row_cnt = 7 then
							if ver_cnt = 39 then
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

					if (hor_cnt(5 downto 2) = "1010") then 
						HSYNC <= '0';
					else 
						HSYNC <= '1';
					end if;
					
					if ver_cnt /= 31 then
						VSYNC <= '1';
					elsif chr_row_cnt = 3 or chr_row_cnt = 4 or ( chr_row_cnt = 5 and ( hor_cnt >= 40 or hor_cnt < 12 ) ) then
						VSYNC<= '0';
					else 
						VSYNC <= '1';
					end if;
					
				end if;
			
				-- int
				if TURBO = '0' then
					-- TURBO int
					if chr_col_cnt = 6 and hor_cnt(1 downto 0) = "11" then
						if ver_cnt = 29 and chr_row_cnt = 7 and hor_cnt(5 downto 2) = "1001" then
							int_sig <= '0';
						else
							int_sig <= '1';
						end if;
					end if;
				else 
					-- PENTAGON int
					if chr_col_cnt = 6 and hor_cnt(2 downto 0) = "111" then
						if ver_cnt = 29 and chr_row_cnt = 7 and hor_cnt(5 downto 3) = "100" then
							int_sig <= '0';
						else
							int_sig <= '1';
						end if;
					end if;

				end if;

				chr_col_cnt <= chr_col_cnt + 1;
			end if;
		else					-- Profi
			if CLK = '1' then
			
				if chr_col_cnt = 7 then
				
					if hor_cnt = 95 then
						hor_cnt <= (others => '0');
					else
						hor_cnt <= hor_cnt + 1;
					end if;
					
					if hor_cnt = 71 then
						if chr_row_cnt = 7 then
							if ver_cnt = 38 then
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

					if (hor_cnt(6 downto 3) = "1001") then 
						HSYNC <= '0';
					else 
						HSYNC <= '1';
					end if;
					
					if ver_cnt /= 33 then
						VSYNC <= '1';
					elsif chr_row_cnt = 3 or chr_row_cnt = 4 or ( chr_row_cnt = 5 and ( hor_cnt >= 40 or hor_cnt < 12 ) ) then
						VSYNC<= '0';
					else 
						VSYNC <= '1';
					end if;
					
				end if;
			
				-- int
				if TURBO = '0' then
					-- TURBO int
					if chr_col_cnt = 6 and hor_cnt(1 downto 0) = "10" then
						if ver_cnt = 32 and chr_row_cnt = 7 and hor_cnt(6 downto 2) = "10010" then
							int_sig <= '0';
						else
							int_sig <= '1';
						end if;
					end if;
				else 
					-- Profi 5 int
					if chr_col_cnt = 0 and hor_cnt(2 downto 0) = "010" then
						if ver_cnt = 32 and chr_row_cnt = 1 and hor_cnt(6 downto 3) = "1010" then
							int_sig <= '0';
						else
							int_sig <= '1';
						end if;
					end if;
				end if;

				chr_col_cnt <= chr_col_cnt + 1;
			end if;
			
		end if;
							--BL_INT
					if INTA = '0' then
						bl_int <= '1';
					elsif hor_cnt(1)= '1' then
						bl_int <= not int_sig;
					end if;
		end if;
	end process;
	
	i78 <= attr_r(7) when DS80 = '1' else attr_r(6);

	-- r/g/b/i
	process( CLK2X, CLK, ENA, paper_r, shift_r, attr_r, invert, blank_r, BORDER )
	begin
		if CLK2X'event and CLK2X = '1' then
			if paper_r = '0' then -- paper
					-- standard RGB
					if(shift_r(7) xor (attr_r(7) and (invert(4) and not DS80))) = '1' then -- fg pixel
						rgb(0) <= attr_r(0);
						rgb(2) <= attr_r(1);
						rgb(1) <= attr_r(2);
						i <= attr_r(6);
					else	-- bg pixel
						rgb(0) <= attr_r(3);
						rgb(2) <= attr_r(4);
						rgb(1) <= attr_r(5);
						i <= i78;
					end if;
			else -- not paper
				if blank_r = '0' then
					-- blank
					rgb(0) <= '0';
					rgb(2) <= '0';
					rgb(1) <= '0';
					i <= '0';
				else -- std border
					-- standard RGB
					if DS80 = '0' then
						rgb(0) <= BORDER(0);
						rgb(2) <= BORDER(1);
						rgb(1) <= BORDER(2);
						i <= '0';
					else
						rgb(0) <= not BORDER(0);
						rgb(2) <= not BORDER(1);
						rgb(1) <= not BORDER(2);
--						i <= '0';
						i <= not BORDER(3) and bl_int;
					end if;
				end if;
			end if;
		end if;
	end process;

	-- paper, blank
	process( CLK2X, CLK, ENA, chr_col_cnt, hor_cnt, ver_cnt, shift_hr_r, attr, bitmap, paper, shift_r )
	begin
		if CLK2X'event and CLK2X = '1' then
		if DS80 = '0' then
			if CLK = '1' then		
				if ENA = '1' then
					if chr_col_cnt = 7 then
						if ((hor_cnt(5 downto 0) > 38 and hor_cnt(5 downto 0) < 48) or ver_cnt(5 downto 1) = 15) then	--256x192
							blank_r <= '0';
						else 
							blank_r <= '1';
						end if;							
						paper_r <= paper;
					end if;
				end if;
			end if;
		else
			if CLK = '1' then		
					if chr_col_cnt = 7 then
						if ((hor_cnt(6 downto 0) > 67 and hor_cnt(6 downto 0) < 92) or (ver_cnt(5 downto 0) > 31 and ver_cnt(5 downto 0) < 37))	then	--512x240
							blank_r <= '0';
						else 
							blank_r <= '1';
						end if;							
						paper_r <= paper;
					end if;
			end if;
		end if;
		end if;
	end process;	
	
	-- bitmap shift registers
	process( CLK2X, CLK, ENA, chr_col_cnt, hor_cnt, ver_cnt, shift_hr_r, attr, bitmap, paper, shift_r )
	begin
		if CLK2X'event and CLK2X = '1' then
		if DS80 = '0' then
			if CLK = '1' then
					-- standard shift register 
					if ENA = '1' then
						if chr_col_cnt = 7 then
							attr_r <= attr;
							shift_r <= bitmap;
						else
							shift_r(7 downto 1) <= shift_r(6 downto 0);
							shift_r(0) <= '0';
						end if;
					end if;
			end if;
		else
			if CLK = '1' then
					-- standard shift register 
						if chr_col_cnt = 7 then
							attr_r <= attr;
							shift_r <= bitmap;
						else
							shift_r(7 downto 1) <= shift_r(6 downto 0);
							shift_r(0) <= '0';
						end if;
			end if;
		end if;
		end if;
	end process;
	
	-- video mem read cycle
	process (CLK2X, CLK, chr_col_cnt, VBUS_MODE, VID_RD)
	begin 
		if (CLK2X'event and CLK2X = '1') then
			if DS80 = '0' then
			if (chr_col_cnt(0) = '1' and CLK = '0') then
				if VBUS_MODE = '1' then
					if VID_RD = '0' then 
						bitmap <= DI;
					else 
						attr <= DI;
					end if;
				end if;
			end if;
			else
			if (chr_col_cnt < 7 and CLK = '0') then
				if VBUS_MODE = '1' then
					if VID_RD = '0' then 
						bitmap <= DI;
					else 
						attr <= DI;
					end if;
				end if;
			end if;
			end if;
		end if;
	end process;
	
	A <= 
		-- data address
		std_logic_vector( '0' & ver_cnt(4 downto 3) & chr_row_cnt & ver_cnt(2 downto 0) & hor_cnt(4 downto 0)) when DS80 = '0' and VBUS_MODE = '1' and VID_RD = '0' else 
		-- standard attribute address
		std_logic_vector( '0' & "110" & ver_cnt(4 downto 0) & hor_cnt(4 downto 0)) when DS80 = '0' and VBUS_MODE = '1' and VID_RD = '1' else 
		-- Profi address
		std_logic_vector((not hor_cnt(0)) & ver_cnt(4 downto 3)) & std_logic_vector(chr_row_cnt) & std_logic_vector(ver_cnt(2 downto 0)) & std_logic_vector(hor_cnt(5 downto 1))  when DS80 = '1' and VBUS_MODE = '1' else
		"00000000000000";

	ATTR_O	<= attr_r;
	paper <= '0' when ((hor_cnt(5) = '0' and ver_cnt(5 downto 0) < 24 and ds80 = '0')				--256x192
					 or	 (hor_cnt(6) = '0' and ver_cnt(5 downto 0) < 30 and ds80 = '1')) else '1'; --512x240
	INT <= int_sig;
	pFF_CS <= paper;
	CSYNC <= not (vsync xor hsync);
	
	-- Палитра profi:

	-- 1) палитра - это память на 16 ячеек. каждая ячейка - 8-битное значение цвета в виде GGGRRRBB
	-- 2) в палитру пишется инвертированное значение старшей половины адреса ША по адресу, заданному в порту #FE (тоже инвертированное значение)
	-- 3) строб записи по схеме формируется при обращении к порту палитры #7E в режиме DS80
	-- 4) при чтении адресом выступает код цвета от видеоконтроллера - YGRB
	
	-- запись палитры
	process(CLK2x, CLK, N_RESET, palette_wr, palette_a, palette)
	begin
		if N_RESET = '0' then 
			-- set default palette on reset
			palette <= x"0000";
			
		elsif rising_edge(CLK2x) then 
			if CLK = '1' then
				if palette_wr = '1' then
					VA (3 downto 0) <= PAL_ADR(3 downto 0) xor X"F";
					VD <= not BUS_A;
					palette(to_integer(unsigned(PAL_ADR(3 downto 0) xor X"F"))) <= PAL_ADR(7);
				else
					VA (3 downto 0) <= palette_a;
					VD <= "ZZZZZZZZ";
				end if;
			end if;
		end if;
	end process;
	
	palette_a <= i & rgb(1) & rgb(2) & rgb(0);
	palette_wr <= '1' when CS7E = '1' and BUS_WR_N = '0' and ds80 = '1' and N_RESET = '1' else '0';
	
	N_VRAMWR <= not palette_wr;

	-- чтение из палитры
	palette_grb (8 downto 0) <= VD (7 downto 0) & palette(to_integer(unsigned(palette_a)));
	
	-- возвращаем наверх (top level) значение младшего разряда зеленого компонента палитры, это служит для отпределения наличия палитры в системе
	GX0 <= palette_grb(6) xor palette_grb(0) when ds80 = '1' else '1';
	
	-- применяем blank для профи, ибо в видеоконтроллере он после палитры
	process(CLK2x, CLK, blank_r, palette_grb, ds80) 
	begin 
		if (blank_r = '0' and ds80='1') then
			palette_grb_reg <= (others => '0');
		else
			palette_grb_reg <= palette_grb;
		end if;
	end process;
	
	VIDEO_R <= palette_grb_reg(5 downto 3);
	VIDEO_G <= palette_grb_reg(8 downto 6);
	VIDEO_B <= palette_grb_reg(2 downto 0);

end architecture;