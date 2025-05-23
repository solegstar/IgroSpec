-------------------------------------------------------------------------------
-- Memory controller
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;

entity memory is
	port (
		CLK2X 		: in std_logic;
		CLKX	   	: in std_logic;
		CLK_CPU 		: in std_logic;
		BUS_N_ROMCS : in std_logic;

		A           : in std_logic_vector(15 downto 0); -- address bus
		D 				: in std_logic_vector(7 downto 0);
		N_MREQ		: in std_logic;
		N_IORQ 		: in std_logic;
		N_WR 			: in std_logic;
		N_RD 			: in std_logic;
		N_M1 			: in std_logic;
	
		DO 			: out std_logic_vector(7 downto 0);
		N_OE 			: out std_logic;
	
		MA 			: out std_logic_vector(19 downto 0);
		MD 			: inout std_logic_vector(7 downto 0);
		N_MRD 		: out std_logic;
		N_MWR 		: out std_logic;
	
		RAM_BANK		: in std_logic_vector(2 downto 0);
		RAM_EXT 		: in std_logic_vector(2 downto 0);
		VA				: in std_logic_vector(13 downto 0);
		VID_PAGE 	: in std_logic := '0';
		DS80			: in std_logic := '0';
		CPM 			: in std_logic := '0';
		SCO			: in std_logic := '0';
		SCR 			: in std_logic := '0';
		WOROM 		: in std_logic := '0';
	
		VBUS_MODE_O : out std_logic;
		VID_RD_O : out std_logic
	);
end memory;

architecture RTL of memory is

	signal buf_md		: std_logic_vector(7 downto 0) := "11111111";
	signal is_buf_wr	: std_logic := '0';	
	
	signal is_rom 		: std_logic := '0';
	signal is_ram 		: std_logic := '0';

	signal ram_page 	: std_logic_vector(5 downto 0) := "000000";

	signal vbus_req	: std_logic := '1';
	signal vbus_mode	: std_logic := '1';	
	signal vbus_rdy	: std_logic := '1';
	signal vbus_ack 	: std_logic := '1';
	signal vid_rd 		: std_logic;
	
	signal mux 			: std_logic_vector(1 downto 0);

begin

	is_rom <= '1' when N_MREQ = '0' and A(15 downto 14)  = "00" and WOROM = '0' else '0';
	is_ram <= '1' when N_MREQ = '0' and is_rom = '0' else '0';

	vbus_req <= '0' when (N_MREQ = '0' or N_IORQ = '0') and ( N_WR = '0' or N_RD = '0' ) else '1';
	vbus_rdy <= '0' when (CLKX = '0' or CLK_CPU = '0')  else '1';

	VBUS_MODE_O <= vbus_mode;
	VID_RD_O <= vid_rd;
	
	N_MRD <= '0' when (vbus_mode = '1' and vbus_rdy = '0') or 
							(vbus_mode = '0' and N_RD = '0' and N_MREQ = '0') 
				else '1';

	N_MWR <= '0' when vbus_mode = '0' and is_ram = '1' and N_WR = '0' and CLK_CPU = '0' 
				else '1';

	is_buf_wr <= '1' when vbus_mode = '0' and CLK_CPU = '0' else '0';
	
	DO <= buf_md;
	
	N_OE <= '0' when is_ram = '1' and N_RD = '0' else '1';
		
	mux <= A(15 downto 14);
		
	process (mux, RAM_EXT, RAM_BANK, SCR, SCO)
	begin
		case mux is
			when "00" => ram_page <= "000000";                                       						                         -- Seg0 ROM 0000-3FFF or Seg0 RAM 0000-3FFF	
			when "01" => if SCO='0' then 
								ram_page <= "000101";
							 else 
								ram_page <= RAM_EXT(2 downto 0) & RAM_BANK(2 downto 0); 
							 end if;	                               -- Seg1 RAM 4000-7FFF	
			when "10" => if SCR='0' then 
								ram_page <= "000010"; 	
							 else 
								ram_page <= "000110"; 
							 end if;                                                                                   -- Seg2 RAM 8000-BFFF
			when "11" => if SCO='0' then 
								ram_page <= RAM_EXT(2 downto 0) & RAM_BANK(2 downto 0);	
							 else 
								ram_page <= "000111";                                               									          -- Seg3 RAM C000-FFFF	
							 end if;
			when others => null;
		end case;
	end process;
		
	MA(13 downto 0) <= 
		A(13 downto 0) when vbus_mode = '0' else -- spectrum ram 
		VA; -- video ram (read by video controller)

	MA(19 downto 14) <= ram_page(5 downto 0) when vbus_mode = '0' else 
		"0001" & VID_PAGE & '1' when vbus_mode = '1' and DS80 = '0' else -- spectrum screen
		"0001" & VID_PAGE & '0' when vbus_mode = '1' and DS80 = '1' and vid_rd = '0' else -- profi bitmap 
		"1110" & VID_PAGE & '0' when vbus_mode = '1' and DS80 = '1' and vid_rd = '1' else -- profi attributes
		"000000";
	
	MD(7 downto 0) <= 
		D(7 downto 0) when vbus_mode = '0' and ((is_ram = '1' or (N_IORQ = '0' and N_M1 = '1')) and N_WR = '0') else 
		(others => 'Z');
		
	-- fill memory buf
	process(is_buf_wr)
	begin 
		if (is_buf_wr'event and is_buf_wr = '0') then  -- high to low transition to lattch the MD into BUF
			buf_md(7 downto 0) <= MD(7 downto 0);
		end if;
	end process;	
	
	process( CLK2X, CLKX, vbus_mode, vbus_req, vbus_ack )
	begin
		-- lower edge of 14 mhz clock
		if CLK2X'event and CLK2X = '1' then 
			if (CLKX = '0') then
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
			
end RTL;

