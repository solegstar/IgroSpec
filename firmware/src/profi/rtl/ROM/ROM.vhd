-- ROM

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.ALL;  
entity ROM is                    
	port(
		CLK				:in std_logic;
		ADR				:in std_logic_vector (15 downto 0);
		DATA				:in std_logic_vector (7 downto 0);
		nRESET			:in std_logic;
		nWR				:in std_logic;
		nRD				:in std_logic;
		nIORQ				:in std_logic;
		nMREQ				:in std_logic;
		nDOS				:in std_logic;
		nROM_EN			:in std_logic;
		blok				:out std_logic;
		rom_a				:out std_logic_vector (18 downto 15);
		rom_we			:out std_logic;
		rom_oe			:out std_logic;
		IORQGE_ROM		:out std_logic;
		OE_BUF			:out std_logic
	);
end ROM;

architecture ROM_arch of ROM is

signal mem_rd			:std_logic;
signal mem_wr			:std_logic;
signal rom_en			:std_logic;
signal blok_rom		:std_logic;
signal cs_romreg_37	:std_logic;
signal romreg_37		:std_logic_vector (7 downto 0) := "00000000";
signal cs_reg_1ffd	:std_logic;
signal reg_1ffd		:std_logic_vector (7 downto 0) := "00000000";

begin

--    ------------------------------------------------------------------------------------
--    --                      Управление памятью ROM
--    ------------------------------------------------------------------------------------
--    -- Порт xx37h = 00110111b
--    ------------------------------------------------------------------------------------
--    WR_37 = !(CA[6..4] == B"011") # CS_X7 # C_WR;
--
--    ROM_PAGE_r[2..0].d     = CD[2..0];
--    ROM_PAGE_r[2..0].clk   = WR_37;
--    ROM_PAGE_r[2..0].clrn  = C_RESET;
--
--    ROM_WrEn_r.d      = CD[7];
--    ROM_WrEn_r.clk    = WR_37;
--    ROM_WrEn_r.clrn   = C_RESET;
--    ------------------------------------------------------------------------------------
--    -- Формирование управляющих сигналов ROM памяти
--    ------------------------------------------------------------------------------------
--    ROM_A16 = !C_DOS # ROM_Page_r[0].q;		-- сигнал RA16 = DOS # RPage0;
--    ROM_A17 = C_DOS & ROM_Page_r[1].q;		-- сигнал RA17 = DOS/ & RPage1;
--    ROM_A18 = C_DOS & ROM_Page_r[2].q;		-- сигнал RA18 = DOS/ & RPage2;
--
--    -----------------------------------------------------------------------------------
--    -- Сигнал записи в ПЗУ
--    ------------------------------------------------------------------------------------
--    WR_ROM = !ROM_WrEn_r.q # !C_A45 # C_WR # C_MREQ; 	-- сигнал WRROM/ = !A45 # WR # MREQ # !RWREN
--    ------------------------------------------------------------------------------------

mem_rd <= nRD or nMREQ;
mem_wr <= nWR or nMREQ;

rom_en <= ADR(15) or ADR(14) or nROM_EN;

cs_romreg_37 <= '0' when ADR(7 downto 0)=x"37" and nIORQ='0' else '1';
process(CLK, nWR, nRESET, DATA)
	begin
		if nRESET='0' then
			romreg_37 <= x"00";
		elsif CLK'event and CLK='1' then
			if cs_romreg_37='0' and nWR='0' then
				romreg_37 <= DATA;
			end if;
		end if;
end process;

cs_reg_1ffd <= '0' when ADR(15 downto 0)=x"1ffd" and nIORQ='0' else '1';
process(CLK, nWR, nRESET, DATA)
	begin
		if nRESET='0' then
			reg_1ffd <= x"00";
		elsif CLK'event and CLK='1' then
			if cs_reg_1ffd='0' and nWR='0' then
				reg_1ffd <= DATA;
			end if;
		end if;
end process;

rom_a(15) <= nDOS xor reg_1ffd(3);
rom_a(16) <= romreg_37(0);
rom_a(17) <= romreg_37(1);
rom_a(18) <= romreg_37(2);

blok <= '0';

rom_we <= rom_en or mem_wr or not romreg_37(7);
rom_oe <= rom_en or mem_rd;

OE_BUF <= cs_romreg_37 and cs_reg_1ffd and (rom_en or (nRD and nWR));	 
IORQGE_ROM <= not (cs_romreg_37 and cs_reg_1ffd);

end ROM_arch;