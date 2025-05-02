-------------------------------------------------------------------------------
-- VIDEO Controller
-------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;

entity video is
	generic (
			enable_turbo 		 : boolean := true
	);
	port (
		CLK2X 	: in std_logic; -- 28 MHz
		CLK		: in std_logic; -- 14 MHz
		ENA		: in std_logic; -- 7 MHz 

		BORDER	: in std_logic_vector(3 downto 0);	-- bordr color (port #xxFE)
		DI			: in std_logic_vector(7 downto 0);	-- video data from memory
		TURBO 	: in std_logic := '0'; -- 1 = turbo mode, 0 = normal mode
		INTA		: in std_logic := '0'; -- int request for turbo mode
		INT		: out std_logic; -- int output
		ATTR_O	: out std_logic_vector(7 downto 0); -- attribute register output
		A			: out std_logic_vector(13 downto 0); -- video address

		VIDEO_R	: out std_logic_vector(2 downto 0);
		VIDEO_G	: out std_logic_vector(2 downto 0);
		VIDEO_B	: out std_logic_vector(2 downto 0);
		
		HSYNC		: buffer std_logic;
		VSYNC		: buffer std_logic;
		CSYNC		: out std_logic;
		
		DS80		: in std_logic; -- 1 = Profi CP/M mode. 0 = standard mode
		
		VBUS_MODE : in std_logic := '0'; -- 1 = video bus, 2 = cpu bus
		VID_RD : in std_logic -- 1 = read attribute, 0 = read pixel data
	);
end entity;

architecture rtl of video is

	signal rgb 	 		: std_logic_vector(2 downto 0);
	signal i 			: std_logic;

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
				if enable_turbo and TURBO = '1' then
					-- TURBO int
					if hor_cnt & chr_col_cnt = 318 and ver_cnt & chr_row_cnt = 239 then
						int_sig <= '0';
					elsif INTA = '0' then
						int_sig <= '1';
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
					
					if ver_cnt /= 31 then
						VSYNC <= '1';
					elsif chr_row_cnt = 3 or chr_row_cnt = 4 or ( chr_row_cnt = 5 and ( hor_cnt >= 40 or hor_cnt < 12 ) ) then
						VSYNC<= '0';
					else 
						VSYNC <= '1';
					end if;
					
				end if;
			
				-- int
				if enable_turbo and TURBO = '1' then
					-- TURBO int
					if hor_cnt & chr_col_cnt = 656 and ver_cnt & chr_row_cnt = 257 then
						int_sig <= '0';
					elsif INTA = '0' then
						int_sig <= '1';
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
--					if INTA = '0' then
--						bl_int <= '1';
--					elsif hor_cnt(1)= '1' then
--						bl_int <= int_sig;
--					end if;
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
						i <= '0';--not BORDER(3) and bl_int;
					end if;
				end if;
			end if;
		end if;
	end process;

	-- paper, blank
	process( CLK2X, CLK, ENA, chr_col_cnt, hor_cnt, ver_cnt, shift_hr_r, attr, bitmap, paper, shift_r )
	begin
		if CLK2X'event and CLK2X = '1' then
			if CLK = '1' then		
				if ENA = '1' then
					if chr_col_cnt = 7 then
						if (((hor_cnt(5 downto 0) > 38 and hor_cnt(5 downto 0) < 48) or ver_cnt(5 downto 1) = 15) and ds80 = '0') or											--256x192
						(((hor_cnt(6 downto 0) > 67 and hor_cnt(6 downto 0) < 91) or (ver_cnt(5 downto 0) > 32 and ver_cnt(5 downto 0) < 36)) and ds80 = '1')	then	--512x240
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
	
	-- RGBS output
	VIDEO_R <= "000" when rgb = "000" else 
				  rgb(2) & rgb(2) & '1' when i = '1' else 
				  rgb(2) & "ZZ";
	VIDEO_G <= "000" when rgb = "000" else 
				  rgb(1) & rgb(1) & '1' when i = '1' else 
				  rgb(1) & "ZZ";
	VIDEO_B <= "000" when rgb = "000" else 
			  rgb(0) & rgb(0) & '1' when i = '1' else 
			  rgb(0) & "ZZ";	
			  
	CSYNC <= not (vsync xor hsync);

end architecture;